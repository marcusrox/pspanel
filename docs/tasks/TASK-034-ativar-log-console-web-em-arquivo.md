# TASK-034 - Ativar log de console web em arquivo

## Contexto

A aplicacao web do PS Panel escreve mensagens operacionais no console com `console.log`, `console.info`, `console.warn` e `console.error`. Essas mensagens incluem startup, tentativas de login, execucao manual de scripts, saidas de PowerShell e erros capturados durante o fluxo web.

A `TASK-019` descreveu a necessidade de registrar essas saidas em arquivo. Atualmente ja existe o service `src/services/webLogger.js`, que espelha chamadas de console para arquivo diario e aplica mascaramento basico de valores sensiveis. Porem, esse service ainda precisa ser ativado no bootstrap principal para capturar as mensagens da aplicacao.

## Objetivo

Ativar o logger de console web existente para que as mensagens exibidas no terminal tambem sejam gravadas em arquivo de log, preservando a saida atual no console e evitando vazamento de segredos.

## Escopo

- Alterar o bootstrap principal `app.js`.
- Importar e chamar `installConsoleFileLogger()` cedo o suficiente para capturar logs de startup.
- Confirmar que o arquivo diario e gravado na pasta esperada pelo service.
- Revisar se a pasta de log gerada esta ignorada pelo Git.
- Validar que os logs de login e execucao de script nao gravam senhas ou parametros sensiveis em claro.

## Fora de escopo

- Criar uma tela para visualizar logs.
- Alterar historico de execucoes em SQLite.
- Alterar auditoria de agendamentos.
- Adicionar dependencia externa de logging.
- Criar rotacao, compactacao ou limpeza automatica de logs antigos.
- Registrar logs do worker `scripts-js/schedule-worker.js`.
- Refatorar todos os `console.log` existentes.

## Arquivos provaveis

- `app.js`
- `src/services/webLogger.js`
- `.gitignore`
- `src/routes/mainRoutes.js` apenas se a revisao encontrar vazamento de parametro sensivel
- `src/services/authService.js` apenas se a revisao encontrar vazamento de senha

## Situacao atual relevante

- `src/services/webLogger.js` ja possui `installConsoleFileLogger(options = {})`.
- O service grava por padrao em `path.join(process.cwd(), 'log')`.
- O nome do arquivo diario segue `web-YYYY-MM-DD.log`.
- O `.gitignore` ignora `logs`, mas nao necessariamente `log/`.
- `app.js` ainda nao importa nem chama `installConsoleFileLogger()`.

## Requisitos funcionais

1. Ao iniciar a aplicacao web, as mensagens de startup devem continuar aparecendo no terminal.
2. As mesmas mensagens devem ser gravadas no arquivo diario de log web.
3. Mensagens posteriores de `console.log`, `console.info`, `console.warn` e `console.error` tambem devem ser gravadas no arquivo.
4. O logger deve criar a pasta de log automaticamente se ela nao existir.
5. Falhas ao abrir ou escrever o arquivo de log nao devem derrubar a aplicacao.
6. Logs de execucao de script devem incluir eventos operacionais, como inicio, script solicitado, total de argumentos, saida e erro do PowerShell.
7. Logs de login devem continuar mascarando senha.

## Requisitos de seguranca

- Nao ler, imprimir ou documentar conteudo real de `.env`.
- Nao gravar senhas, tokens, secrets ou chaves em claro.
- Confirmar que `FortiPassword` e outros parametros com nomes sensiveis nao sao gravados com valor real.
- Confirmar que o redator de `webLogger.js` cobre nomes contendo `password`, `senha`, `token`, `secret` e `key`.
- Nao registrar headers sensiveis.
- Nao adicionar exemplos com credenciais reais.

## Sugestao de implementacao

1. Em `app.js`, importar o service:

```js
const { installConsoleFileLogger } = require('./src/services/webLogger');
```

2. Chamar `installConsoleFileLogger()` logo apos os requires/configuracoes iniciais e antes do primeiro `console.log` relevante.
3. Verificar se `.gitignore` deve incluir `log/`, mantendo tambem regras existentes para `logs`.
4. Revisar rapidamente os logs de `mainRoutes.js` e `authService.js` para confirmar que valores sensiveis nao sao impressos.
5. Rodar validacoes de sintaxe.

## Criterios de aceite

- Ao iniciar a aplicacao, existe arquivo `log/web-YYYY-MM-DD.log`.
- As mensagens `Servidor rodando na porta`, `URL`, `Iniciando servidor em ambiente` e `Data e hora` aparecem no terminal e no arquivo.
- Uma tentativa de login registra evento operacional sem senha em claro.
- Uma execucao manual de script registra saida/erro operacional no arquivo.
- Valores de parametros sensiveis, como `FortiPassword`, nao aparecem em claro no arquivo.
- A pasta/arquivos de log nao entram no Git.

## Testes sugeridos

- `node --check app.js`
- `node --check src\\services\\webLogger.js`
- Iniciar a aplicacao com `npm start` ou `npm run dev`.
- Confirmar a criacao de `log/web-YYYY-MM-DD.log`.
- Fazer login e confirmar que a senha aparece mascarada ou nao aparece.
- Executar um script e confirmar que mensagens de stdout/stderr aparecem no arquivo.
- Rodar `git status --short` e confirmar que arquivos de log nao aparecem como novos.

## Validacao esperada

- Validar sintaxe dos arquivos JavaScript alterados.
- Fazer validacao manual com a aplicacao web em execucao.
- Se a validacao exigir login, usar credenciais locais apenas no ambiente e nunca registrar os valores na resposta ou documentacao.

---

## Assinatura da LLM

- Data: 2026-07-13
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao
