# TASK-063 - Criar runbook operacional enxuto de atualizacao

## Contexto

O procedimento completo de release e deploy remoto esta documentado no
`INSTALL.md`, junto com preparacao de WinRM, Kerberos, firewall, identidade de
operacao e acesso Git. Esse nivel de detalhe e necessario para instalar ou
preparar o ambiente, mas dificulta a consulta durante uma atualizacao rotineira.

O operador precisa de um documento curto, sequencial e voltado exclusivamente
a criacao da release, simulacao, implantacao, verificacao e rollback.

## Objetivo

Criar `UPDATE.md` na raiz do projeto como runbook operacional enxuto de
atualizacao do PS Panel, sem repetir instrucoes de instalacao ou configuracao
inicial do ambiente.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

### 1. Criar o documento operacional

Criar `UPDATE.md` com as secoes abaixo, nesta ordem:

1. finalidade e momento de uso;
2. pre-requisitos operacionais resumidos;
3. preparacao da release na estacao DEV;
4. verificacao da tag publicada;
5. teste de conectividade com a VM;
6. simulacao obrigatoria do deploy remoto;
7. execucao do deploy na janela aprovada;
8. verificacao do resultado, servico, worker e health checks;
9. consulta de log e identificacao do snapshot;
10. rollback manual por snapshot;
11. contingencia local quando o WinRM estiver indisponivel;
12. checklist de encerramento da mudanca.

### 2. Manter o documento enxuto

O `UPDATE.md` deve:

- assumir que a VM e a estacao DEV ja foram preparadas;
- usar comandos prontos para copiar, com placeholders evidentes;
- separar claramente simulacao e execucao efetiva;
- indicar o resultado esperado depois de cada etapa critica;
- evitar explicacoes arquiteturais extensas;
- apontar para `INSTALL.md` quando um pre-requisito nao estiver configurado;
- apontar para `docs/architecture.md` apenas quando o contexto tecnico for
  realmente necessario;
- evitar duplicar integralmente o runbook de preparacao do ambiente.

Como referencia de tamanho, o documento deve permanecer proximo de 100 a 150
linhas, salvo necessidade objetiva de seguranca ou clareza operacional.

### 3. Fluxo minimo da release

Documentar, com exemplos coerentes com os scripts existentes:

```powershell
npm test
.\deploy\windows\Test-PSPanelRelease.ps1
git status --short
.\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf
.\deploy\windows\New-PSPanelReleaseTag.ps1
```

O texto deve deixar claro que:

- `src/config/release.js` precisa ter sido incrementado;
- o commit precisa estar publicado e sincronizado com `origin/main`;
- a arvore precisa estar limpa antes da criacao da tag;
- o valor da tag deve ser lido de `src/config/release.js`;
- nao existe opcao para ignorar a suite de testes.

### 4. Fluxo minimo do deploy remoto

Usar variaveis com placeholders e documentar primeiro a simulacao:

```powershell
$server = '<FQDN_DO_SERVIDOR>'
$release = '<TAG_PUBLICADA>'

$preview = .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName $server `
    -Version $release `
    -WhatIf
```

Somente depois de conferir `SimulacaoAprovada`, documentar a execucao real:

```powershell
$result = .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName $server `
    -Version $release
```

Nao orientar uso de IP, `TrustedHosts`, CredSSP ou alteracao de firewall como
solucao de contingencia.

### 5. Verificacao obrigatoria

O runbook deve orientar a conferir, no minimo:

- `Status` e `Version`;
- `PreviousCommit`, `TargetCommit` e `ActiveCommit`;
- `SnapshotPath` e `RemoteLogFile`;
- `ServiceStatus`;
- `WorkerState` e `WorkerLastTaskResult`;
- `RemoteHealthCheck` e, quando configurado, `ExternalHealthCheck`;
- acesso autenticado a aplicacao pelo endereco corporativo.

O operador deve registrar o resultado da mudanca sem copiar credenciais,
tokens, conteudo do `.env` ou outros segredos.

### 6. Rollback e contingencia

Documentar rollback manual por snapshot usando
`deploy/windows/Update-PSPanel.ps1 -Rollback`, sempre com `-WhatIf` antes da
execucao efetiva.

Quando o WinRM estiver indisponivel, orientar acesso autorizado ao console ou
RDP da VM e execucao local do mesmo `Update-PSPanel.ps1`. Nao criar um fluxo
manual com `git reset`, troca direta de commit, copia de arquivos ou comandos
isolados para parar e iniciar componentes.

A contingencia deve preservar:

- `.env`;
- diretorio `database`;
- configuracao local do servico;
- snapshots anteriores;
- logs do deploy.

### 7. Ajustar navegacao da documentacao

Atualizar:

- `README.md`, adicionando um link visivel para `UPDATE.md` como procedimento
  de atualizacao rotineira;
- `INSTALL.md`, mantendo a preparacao detalhada e apontando para `UPDATE.md`
  nas operacoes recorrentes;
- `docs/architecture.md` somente se for necessario corrigir ou incluir uma
  referencia curta, sem copiar o runbook.

## Arquivos previstos

```text
UPDATE.md
README.md
INSTALL.md
docs/architecture.md (somente se necessario)
docs/tasks/TASK-063-criar-runbook-operacional-atualizacao.md
src/config/release.js
```

## Fora de escopo

- Alterar scripts de release, deploy ou rollback.
- Habilitar ou testar WinRM no ambiente corporativo.
- Alterar firewall, GPO, Active Directory, contas ou credenciais Git.
- Executar uma release, criar uma tag ou implantar em producao.
- Implementar GitHub Actions.
- Copiar para o novo documento toda a preparacao descrita no `INSTALL.md`.

## Validacao obrigatoria

- Conferir comandos, parametros e propriedades de retorno contra:
  - `deploy/windows/Test-PSPanelRelease.ps1`;
  - `deploy/windows/New-PSPanelReleaseTag.ps1`;
  - `deploy/windows/Invoke-PSPanelRemoteDeploy.ps1`;
  - `deploy/windows/Update-PSPanel.ps1`.
- Confirmar que todos os servidores, tags, snapshots e URLs usam placeholders
  ou valores claramente ficticios.
- Confirmar que nenhum segredo ou identificador corporativo real foi incluido.
- Confirmar que simulacao, deploy, verificacao e rollback estao separados.
- Confirmar que a contingencia usa o atualizador oficial e preserva os dados
  locais.
- Validar os links entre `README.md`, `INSTALL.md`, `UPDATE.md` e, quando
  alterado, `docs/architecture.md`.
- Executar `git diff --check`.

## Criterios de aceite

- Um operador com o ambiente ja preparado consegue concluir uma atualizacao
  consultando principalmente o `UPDATE.md`.
- O documento apresenta um fluxo linear, curto e seguro.
- A simulacao e obrigatoria antes do deploy e do rollback.
- Os resultados esperados e os pontos de verificacao estao explicitos.
- Problemas de preparacao remetem ao `INSTALL.md`, sem duplicacao extensa.
- README, INSTALL e UPDATE nao possuem instrucoes contraditorias.
- Nenhum comando de infraestrutura e executado durante a implementacao.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-058 a TASK-062 concluidas, pois o novo runbook resume o fluxo ja
  implementado e documentado por elas.

---

## Assinatura da LLM

- Data: 2026-08-18 16:53:50 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

- Status: implementada em 2026-08-18.
- Criado `UPDATE.md` com o fluxo recorrente de release, tag, conectividade,
  simulacao, deploy, verificacao, rollback e contingencia.
- `README.md` passou a destacar o runbook operacional.
- `INSTALL.md` manteve a preparacao de WinRM, Kerberos e acesso Git, remetendo
  as atualizacoes recorrentes ao novo documento.
- `docs/architecture.md` diferencia a documentacao operacional da preparacao
  de infraestrutura.
- Os scripts de release e deploy nao foram alterados e nenhum comando de
  infraestrutura ou producao foi executado.
- O release foi atualizado para `v2026.08.18-064`.

---

## Assinatura da LLM

- Data: 2026-08-18 16:57:32 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
