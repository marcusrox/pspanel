# TASK-061 - Criar wrapper de deploy remoto

## Contexto

Depois que uma tag e publicada e chega a janela de implantacao, o operador
precisa conectar-se manualmente ao Windows Server para executar
`Update-PSPanel.ps1`. Estacao DEV e servidor de producao estao na mesma rede
corporativa e podem usar PowerShell Remoting com Kerberos.

## Objetivo

Criar `deploy/windows/Invoke-PSPanelRemoteDeploy.ps1` para a estacao DEV validar
a tag e solicitar ao servidor que execute o atualizador local no momento
escolhido pelo operador.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Parametros previstos

- `ComputerName`: hostname ou FQDN do servidor, sem valor corporativo real
  fixado no repositorio;
- `Version`: tag `vAAAA.MM.DD-NNN` obrigatoria;
- `ProjectRoot`: padrao `C:\Apps\PSPanel`;
- `ConfigurationName`: endpoint PowerShell opcional;
- `Credential`: opcional, sem persistencia;
- `HealthCheckUrl`: opcional para validacao adicional a partir da estacao;
- `WhatIf` e `Confirm` pelos common parameters.

## Fluxo esperado

1. Validar localmente o formato da tag.
2. Confirmar que a tag existe no remote Git configurado, sem expor credenciais.
3. Validar conectividade com o servidor por WSMan.
4. Abrir sessao usando hostname/FQDN e Kerberos por padrao.
5. Confirmar remotamente a raiz, o atualizador, Git, Node.js, npm, servico e
   worker esperados.
6. Executar remotamente uma pre-validacao equivalente a `-WhatIf`.
7. Em modo real, apresentar o alvo e solicitar uma unica confirmacao local.
8. Chamar o atualizador remoto com `-Confirm:$false`, pois a confirmacao ja foi
   obtida pelo wrapper.
9. Capturar a saida estruturada criada na TASK-060.
10. Fazer health check adicional a partir da estacao quando a URL for
    informada.
11. Exibir resumo em portugues e retornar falha quando o comando remoto falhar.
12. Sempre encerrar a PSSession em bloco `finally`.

## Seguranca obrigatoria

- Usar Kerberos por padrao.
- Nao adicionar automaticamente hosts a `TrustedHosts`.
- Nao habilitar CredSSP.
- Nao aceitar IP como destino no fluxo Kerberos padrao.
- Nao armazenar senha, token, deploy key ou conteudo de `.env`.
- Nao enviar credenciais Git como parametro remoto.
- Nao copiar banco, `.env` ou codigo entre as maquinas.
- Validar a tag antes de inclui-la no script block remoto.
- Passar valores com `-ArgumentList`, sem construir texto executavel por
  concatenacao.
- Incluir comment-based help completo.

## Arquivos previstos

```text
deploy/windows/Invoke-PSPanelRemoteDeploy.ps1
README.md
src/config/release.js
```

## Fora de escopo

- Executar `Enable-PSRemoting` remotamente.
- Modificar firewall, GPO, grupos AD ou administradores locais.
- Instalar certificados ou configurar WinRM HTTPS.
- Configurar credenciais Git no servidor.
- Implementar JEA ou CredSSP.
- Automatizar horario de deploy.
- Criar GitHub Actions.

## Testes sugeridos

- Parser PowerShell sem erros.
- Rejeicao de tag, hostname e caminho invalidos.
- `-WhatIf` sem chamar deploy real.
- Falha controlada quando WSMan estiver indisponivel.
- Falha controlada quando o atualizador remoto nao existir.
- Captura correta de sucesso, rollback e falha critica simulados.
- Garantia de fechamento da PSSession em sucesso e erro.
- Teste integrado primeiro contra servidor DEV autorizado.

## Criterios de aceite

- O operador pode simular e executar uma tag a partir da estacao DEV.
- O codigo de deploy continua sendo executado no servidor.
- O wrapper nao possui nomes, usuarios ou segredos corporativos fixos.
- Kerberos e usado sem `TrustedHosts` ou CredSSP no cenario de dominio.
- O resultado informa tag, commits, snapshot, componentes e log remoto.
- Falha remota resulta em falha local perceptivel.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-060 concluida.

## Pre-requisitos externos ao repositorio

- WinRM habilitado e restringido pela equipe responsavel.
- Resolucao DNS e Kerberos funcionando entre estacao e servidor.
- Usuario autorizado a executar o atualizador como administrador.
- `git fetch origin --tags --prune` funcionando em sessao nao interativa no
  servidor.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

Foi criado `deploy/windows/Invoke-PSPanelRemoteDeploy.ps1`. O wrapper valida
hostname/FQDN, tag e caminho, confirma a tag no `origin`, testa WSMan com
Kerberos, abre a PSSession e verifica remotamente raiz, atualizador, Git,
Node.js, npm, servico e worker.

Antes de qualquer deploy, o wrapper executa `Update-PSPanel.ps1 -WhatIf` no
servidor. O modo efetivo usa uma unica confirmacao local e chama o atualizador
com `-Confirm:$false`. Valores remotos sao enviados por `-ArgumentList`, sem
construcao de codigo por concatenacao. A PSSession e removida em `finally`.

O resultado `PSPanel.RemoteDeploymentResult` preserva tag, commits, snapshot,
servico, worker, health checks, rollback e log remoto. Falhas remotas produzem
erro local terminante com o resultado anexado. O health check opcional da
estacao aceita apenas URL HTTP/HTTPS sem credenciais, query ou fragmento.

Controles confirmados:

- Kerberos fixado como autenticacao padrao;
- IP rejeitado como destino;
- nenhum uso de TrustedHosts, CredSSP ou Enable-PSRemoting;
- nenhuma transferencia de codigo, banco ou `.env`;
- credencial opcional usada somente nos cmdlets WSMan/PSSession;
- nenhum hostname, usuario ou segredo corporativo fixado.

Validacoes executadas com `origin`, tag e PSSession simulados:

- parser no PowerShell 7.6.4 e no Windows PowerShell 5.1: sem erros;
- tag e endereco IP invalidos rejeitados antes de conexao;
- `-WhatIf`: uma pre-validacao remota, nenhum deploy e sessao fechada;
- sucesso sem health check externo: pre-validacao e deploy executados uma vez,
  resultado estruturado capturado e sessao fechada;
- health check externo simulado: HTTP 204 aprovado;
- atualizador remoto ausente: falha local e sessao fechada;
- falha critica remota simulada: snapshot, componentes e rollback preservados
  no resultado, excecao local propagada e sessao fechada;
- falha do health check externo depois de sucesso remoto: falha local
  preservando o resultado do servidor;
- `npm test`: 47 testes aprovados;
- `git diff --check`.

Nenhum servidor corporativo foi acessado e nenhuma configuracao WinRM, firewall,
conta, servico ou tarefa foi alterada. O primeiro teste integrado ainda deve ser
feito contra um servidor DEV autorizado. O release foi atualizado para
`v2026.08.18-062`.

---

## Assinatura da LLM

- Data: 2026-08-18 15:07:38 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
