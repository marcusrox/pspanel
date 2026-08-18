# TASK-062 - Documentar release e deploy remoto

## Contexto

Depois das tasks anteriores, o processo operacional passa a combinar testes
automatizados, criacao de tag na estacao DEV e execucao remota do atualizador
na janela de producao. O procedimento precisa ser documentado sem incluir
nomes internos, usuarios, credenciais ou configuracoes reais da empresa.

## Objetivo

Atualizar a documentacao do PS Panel com um runbook completo de preparacao da
release, habilitacao segura do PowerShell Remoting, deploy, verificacao e
rollback.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo da documentacao

### Release na estacao DEV

Documentar:

1. pre-requisitos de Node.js, npm, Git e PowerShell;
2. incremento de `src/config/release.js`;
3. arvore limpa e sincronizada com `origin/main`;
4. execucao de `npm test` e `Test-PSPanelRelease.ps1`;
5. simulacao e execucao de `New-PSPanelReleaseTag.ps1`;
6. verificacao da tag publicada.

### Preparacao externa do servidor

Documentar, sem executar automaticamente:

- uso de hostname/FQDN em dominio para Kerberos;
- `Enable-PSRemoting -Force` em console administrativo autorizado;
- verificacao com `Get-Service WinRM` e `Get-PSSessionConfiguration`;
- porta TCP 5985 ou 5986 conforme politica corporativa;
- restricao da regra de firewall a estacao ou sub-rede administrativa;
- grupo AD ou grupo local de operadores autorizados;
- necessidade de privilegios administrativos devido a
  `#Requires -RunAsAdministrator`;
- proibicao de documentar senhas, tokens ou chaves reais;
- ausencia de necessidade de `TrustedHosts` no cenario Kerberos;
- risco de CredSSP e decisao de nao usa-lo no fluxo padrao.

### Autenticacao Git nao interativa

Explicar o teste obrigatorio de `git fetch` dentro de `Invoke-Command` e as
alternativas aprovaveis quando ele falhar:

- deploy key SSH de leitura protegida por ACL; ou
- credencial Git dedicada no perfil da conta de deploy.

Nao incluir uma chave, PAT, URL autenticada ou comando que imprima credenciais.

### Deploy e rollback

Documentar:

- teste de conectividade com `Test-WSMan`;
- simulacao com `Invoke-PSPanelRemoteDeploy.ps1 -WhatIf`;
- execucao real na janela aprovada;
- leitura do resumo e do log em `C:\Apps\PSPanel\log\deploy`;
- verificacao do servico, worker e health check;
- rollback automatico;
- rollback manual por snapshot;
- contingencia local quando WinRM estiver indisponivel.

## Arquivos previstos

```text
README.md
INSTALL.md
docs/architecture.md
src/config/release.js
```

Evitar repetir integralmente o mesmo runbook em todos os arquivos. Manter o
procedimento detalhado em `INSTALL.md`, um resumo operacional em `README.md` e
somente a arquitetura relevante em `docs/architecture.md`.

## Fora de escopo

- Executar comandos de infraestrutura.
- Alterar firewall, WinRM, GPO, AD ou credenciais.
- Criar arquivos com valores reais do ambiente corporativo.
- Implementar GitHub Actions.
- Alterar scripts de deploy alem de correcao documental indispensavel.

## Validacao obrigatoria

- Conferir todos os comandos e caminhos contra os scripts implementados.
- Confirmar que exemplos usam placeholders claros.
- Buscar por possiveis usuarios, servidores, dominios, tokens ou senhas reais.
- Confirmar que o procedimento nao orienta uso de IP, `TrustedHosts` ou
  CredSSP no fluxo padrao.
- Confirmar que a contingencia preserva `.env`, banco e backups.

## Criterios de aceite

- Um operador novo consegue seguir o processo completo sem conhecimento
  implicito.
- Release, deploy, verificacao e rollback estao claramente separados.
- As etapas externas ao repositorio estao identificadas como responsabilidade
  operacional.
- Nenhum segredo ou identificador corporativo real aparece na documentacao.
- Os exemplos correspondem aos parametros reais dos scripts.
- Nao ha contradicao entre README, INSTALL e arquitetura.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-056 a TASK-061 concluidas, para documentar o comportamento efetivamente
  implementado.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

- Status: implementada em 2026-08-18.
- O `INSTALL.md` passou a conter o runbook completo de preparação externa,
  acesso Git não interativo, geração da release, deploy remoto, verificação,
  rollback e contingência local.
- O `README.md` recebeu um resumo operacional com referência ao runbook.
- `docs/architecture.md` documenta as fronteiras entre estação DEV, Git,
  WinRM/Kerberos, VM e dados locais.
- A contingência usa o atualizador oficial e preserva snapshot, `.env`, banco e
  configuração do serviço.
- Nenhum comando de infraestrutura foi executado e nenhum identificador ou
  segredo real foi incluído.
- O release foi atualizado para `v2026.08.18-063`.

---

## Assinatura da LLM

- Data: 2026-08-18 15:30:03 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
