# TASK-060 - Preparar atualizador para execucao remota

## Contexto

`deploy/windows/Update-PSPanel.ps1` ja realiza snapshot, parada do servico e do
worker, instalacao de uma tag ou commit, validacoes, health check e rollback.
Ele foi desenhado para uso interativo local e precisa ter um contrato claro
para ser chamado de uma sessao PowerShell Remoting sem perder as protecoes
atuais.

## Objetivo

Tornar o atualizador seguro e previsivel em execucao nao interativa, mantendo
compatibilidade com o uso local atual e fornecendo um resultado estruturado
para o futuro wrapper remoto.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

1. Revisar todos os prompts e garantir que o chamador possa usar
   `-Confirm:$false` de forma explicita.
2. Preservar `-WhatIf` sem parada de componentes, checkout, instalacao ou
   alteracao de dados.
3. Manter a validacao de tag ou hash imutavel e a recusa de referencias moveis
   sem `-Force`.
4. Emitir ao final um objeto estruturado contendo, no minimo:
   - operacao;
   - versao solicitada;
   - commit anterior;
   - commit ativo;
   - snapshot criado;
   - status do servico;
   - estado e ultimo resultado do worker;
   - resultado do health check;
   - caminho do log;
   - indicacao de rollback automatico, quando ocorrer.
5. Garantir codigo de saida ou excecao adequada em falha de deploy e em falha
   critica de rollback.
6. Registrar identidade do executor remoto somente quando disponivel, sem
   registrar credenciais ou tokens.
7. Preservar o resumo textual para uso manual.

## Compatibilidade obrigatoria

- Continuar aceitando tag `vAAAA.MM.DD-NNN` e hash de commit.
- Continuar executando como administrador.
- Continuar usando `C:\Apps\PSPanel` por padrao.
- Preservar WinSW `PSPanelWeb`, tarefa `PSPanel Schedule Worker`, backups,
  lock, retencao e health check.
- Nao alterar `.env`, banco ou XML fora do fluxo de snapshot/restauracao atual.
- Nao alterar a estrategia de checkout detached.

## Arquivos previstos

```text
deploy/windows/Update-PSPanel.ps1
README.md
INSTALL.md
src/config/release.js
```

## Fora de escopo

- Habilitar ou configurar WinRM.
- Criar conta, grupo AD, firewall ou endpoint JEA.
- Criar o wrapper da estacao DEV.
- Remover suporte a deploy local.
- Remover tags ou migrar para trunk deployment.
- Alterar WinSW ou a tarefa agendada.

## Testes sugeridos

Criar testes PowerShell isolados ou funcoes testaveis que simulem comandos
nativos e componentes Windows, cobrindo:

- `-WhatIf` sem efeitos colaterais;
- sucesso com resultado estruturado;
- tag inexistente;
- falha em `git fetch`;
- falha em `npm ci`;
- falha no health check com rollback bem-sucedido;
- falha critica no rollback;
- aplicacao ja na versao solicitada;
- execucao com `-Confirm:$false` sem prompt.

Nao parar servicos reais nem alterar Scheduled Tasks na estacao DEV.

## Validacao obrigatoria

- Parser PowerShell sem erros.
- `Update-PSPanel.ps1 -Version <tag-valida> -WhatIf -Confirm:$false` em ambiente
  autorizado.
- Confirmar que a saida pode ser capturada por `Invoke-Command`.
- Confirmar que erros propagam falha ao processo chamador.
- Repetir um deploy local controlado em ambiente DEV antes de habilitar o uso
  remoto em producao.

## Criterios de aceite

- O atualizador pode ser executado sem interacao quando explicitamente pedido.
- Uso local interativo continua funcionando.
- `-WhatIf` permanece seguro.
- O chamador recebe dados suficientes para apresentar o resultado do deploy.
- Rollback e logs existentes sao preservados.
- Nenhum segredo aparece na saida estruturada ou textual.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

Nenhuma dependencia tecnica das tasks de teste, embora seja recomendavel
executa-la depois da TASK-059 para seguir a ordem operacional planejada.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

`Update-PSPanel.ps1` passou a emitir `PSPanel.DeploymentResult` em simulacao,
sucesso, versao ja instalada e falhas operacionais. O contrato inclui operacao,
versao solicitada, commits anterior/alvo/ativo, snapshot, servico, worker,
ultimo resultado do worker, health check, log e situacao do rollback automatico.

Falhas em pre-validacao e deploy continuam terminantes. Quando existe resultado
estruturado, ele e emitido antes da excecao e anexado como `TargetObject` do
`ErrorRecord`. Falha critica do rollback possui identificador proprio e mantem
o diagnostico dos dois erros.

O `-WhatIf` permanece antes da criacao de log e lock e antes de qualquer parada,
snapshot, checkout ou instalacao. Ele agora retorna status
`SimulacaoAprovada`. `-Confirm:$false` usa o suporte nativo de `ShouldProcess` e
nao ha outros prompts interativos no script.

A identidade do executor remoto e registrada no log e no manifesto somente
quando `PSSenderInfo` a fornece. A URL exibida no plano omite usuario, senha,
query e fragmento. Mensagens de ferramentas nativas passam por redacao de
credenciais em URI e valores nomeados como senha, token ou segredo antes de
serem gravadas. Referencias moveis seguras continuam exigindo `-Force`, enquanto
tags de release e hashes permanecem aceitos sem essa opcao.

Validacoes executadas:

- parser no PowerShell 7.6.4 e no Windows PowerShell 5.1: sem erros;
- contrato estruturado exercitado com servico e worker simulados;
- retorno nulo, estados, health check e serializacao JSON conferidos;
- URL com usuario, senha e token simulados: nenhum segredo apareceu no destino
  sanitizado;
- mensagem nativa simulada com credencial em URI, token e senha: valores
  redigidos antes do log;
- falha terminante controlada: objeto recebido pelo pipeline e como
  `TargetObject` do erro;
- `-WhatIf -Confirm:$false` em clone temporario com componentes simulados:
  resultado capturado, commit preservado e nenhum log, lock, checkout ou
  comando operacional executado;
- falha completa de pre-validacao: status `FalhaPreValidacao`, identificador de
  erro proprio e o mesmo objeto disponivel no pipeline e no erro;
- `npm test`: 47 testes aprovados;
- `git diff --check`.

Nao foram parados servicos, alteradas tarefas agendadas, acessados bancos ou
executados deploys reais nesta estacao. O `-WhatIf` e o deploy local controlado
em uma instalacao autorizada ainda devem ser repetidos antes de habilitar o uso
remoto em producao. O release foi atualizado para `v2026.08.18-061`.

---

## Assinatura da LLM

- Data: 2026-08-18 14:49:56 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
