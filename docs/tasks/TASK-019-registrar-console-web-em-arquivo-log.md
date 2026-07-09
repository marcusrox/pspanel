# TASK-019 - Registrar console da aplicacao web em arquivo de log

## Contexto

A aplicacao web do PS Panel escreve mensagens operacionais diretamente em `console.log` e `console.error` a partir do bootstrap `app.js`, rotas, controllers e services. Durante a analise, nao foi encontrado logger centralizado, `createWriteStream`, `appendFile`, `writeFile` ou biblioteca como `winston`, `pino` ou `morgan` registrando essas mensagens em arquivo.

Existe uma pasta `log/` na raiz da aplicacao, mas o codigo web atual nao grava automaticamente nela as saidas geradas por `console.log` e `console.error`. O historico de execucao de scripts e salvo no SQLite por `History.addEntry` e `History.updateEntry`, mas isso nao equivale a log geral do processo web.

Tambem existem mensagens de depuracao em fluxos sensiveis de autenticacao que imprimem informacoes como usuario, senha e variaveis de ambiente. Antes de persistir saidas de console em arquivo, senhas precisam ser mascaradas para evitar gravacao permanente de segredo em disco.

## Objetivo

Fazer com que as saidas de console geradas pelo sistema WEB tambem sejam registradas em arquivo dentro da pasta `log/` da aplicacao, preservando a saida padrao atual no terminal.

## Escopo

- Criar um mecanismo centralizado de logging para o processo web iniciado por `app.js`.
- Espelhar chamadas de `console.log`, `console.info`, `console.warn` e `console.error` para arquivo, mantendo o comportamento atual de escrever em stdout/stderr.
- Gravar os arquivos na pasta `log/` da raiz do projeto.
- Criar a pasta `log/` automaticamente se ela nao existir.
- Usar arquivo diario com nome previsivel, por exemplo:

```text
log/web-YYYY-MM-DD.log
```


- Incluir timestamp ISO, nivel e mensagem em cada linha.
- Preservar objetos e erros de forma legivel, incluindo `error.stack` quando disponivel.
- Garantir que falha ao escrever no arquivo de log nao derrube a aplicacao web.
- Remover ou mascarar senhas antes de persistir qualquer console em arquivo.

## Fora de escopo

- Registrar saidas dos scripts PowerShell como substituto do historico existente.
- Alterar a persistencia de `script_history` ou `schedule_audit`.
- Alterar o worker `scripts-js/schedule-worker.js`, salvo se for explicitamente decidido que o worker tambem deve usar o mesmo logger em outra task.
- Criar tela web para visualizar logs.
- Criar rotacao avancada, compactacao ou limpeza automatica de logs antigos.
- Adicionar dependencia externa sem necessidade clara.
- Gravar conteudo real de `.env`, senhas, tokens, headers sensiveis, LDAP bind password ou parametros secretos em arquivo.

## Arquivos provaveis

```text
app.js
src/services/webLogger.js
src/services/authService.js
src/services/ldapService.js
src/routes/authRoutes.js
src/routes/mainRoutes.js
```

O arquivo `src/services/webLogger.js` e apenas uma sugestao. Usar outro nome equivalente se ficar mais alinhado ao projeto.

## Requisitos funcionais

1. Ao iniciar a aplicacao web, as mensagens de startup hoje exibidas no console devem continuar aparecendo no terminal.
2. As mesmas mensagens de startup devem ser gravadas no arquivo de log web.
3. Chamadas posteriores a `console.log`, `console.info`, `console.warn` e `console.error` feitas pelo processo web devem tambem aparecer no arquivo de log.
4. Mensagens de erro devem preservar detalhes uteis, incluindo stack trace quando houver objeto `Error`.
5. O arquivo de log deve ficar dentro da pasta `log/` na raiz do projeto.
6. Se a pasta `log/` nao existir, a aplicacao deve cria-la de forma segura no startup.
7. Se o arquivo de log nao puder ser aberto ou escrito, a aplicacao deve continuar funcionando e manter a saida padrao.
8. O logger deve ser inicializado cedo o suficiente em `app.js` para capturar as mensagens de startup da aplicacao.

## Requisitos de seguranca

- Antes de espelhar console para arquivo, revisar e ajustar logs sensiveis existentes.
- Remover ou mascarar logs como:
  - senha administrativa;
  - senha fornecida no login;
  - LDAP bind password;
  - tokens;
  - headers sensiveis;
  - conteudo real do `.env`;
  - parametros que possam conter segredo.
- Em `src/services/authService.js`, nao registrar `process.env.ADMIN_PASSWORD` nem a senha informada pelo usuario.
- Em fluxos LDAP, nao registrar credenciais senha de usuario.
- Evitar registrar parametros completos de scripts quando houver indicio de segredo no nome, por exemplo `password`, `senha`, `token`, `secret`, `key`.
- Nao ler nem imprimir o conteudo real do arquivo `.env` durante a implementacao.

## Sugestao de implementacao

1. Criar um service pequeno em `src/services/webLogger.js` com uma funcao, por exemplo `installConsoleFileLogger(options)`.
2. No service:
   - resolver o diretorio de log com `path.join(process.cwd(), 'log')`;
   - criar o diretorio com `fs.mkdirSync(logDir, { recursive: true })`;
   - abrir stream com `fs.createWriteStream(logFile, { flags: 'a' })`;
   - guardar referencias para os metodos originais de `console`;
   - sobrescrever `console.log/info/warn/error` para chamar primeiro o metodo original e depois gravar no arquivo.
3. Serializar argumentos com uma funcao pequena:
   - strings devem ser preservadas;
   - `Error` deve virar `stack` ou `message`;
   - objetos devem usar `JSON.stringify` com fallback para `String(value)`.
4. Prefixar cada linha com timestamp ISO e nivel:

```text
2026-05-26T21:00:00.000Z INFO Servidor rodando na porta 3000
```

5. Chamar o instalador logo no inicio de `app.js`, depois de carregar dependencias basicas e antes dos primeiros logs de startup.
6. Revisar os pontos com logs sensiveis, especialmente:
   - `src/services/authService.js`;
   - `src/services/ldapService.js`;
   - `src/routes/authRoutes.js`;
   - `src/routes/mainRoutes.js`.
7. Manter mensagens ao usuario em portugues e CommonJS.

## Criterios de aceite

- Ao rodar `npm start`, a pasta `log/` contem um arquivo de log web atualizado.
- As mensagens de startup aparecem tanto no terminal quanto no arquivo.
- Uma tentativa de login gera registros operacionais no arquivo sem gravar senha.
- Uma execucao manual de script registra eventos web no arquivo sem vazar parametros sensiveis.
- Erros capturados por `console.error` aparecem no arquivo com detalhe suficiente para diagnostico.
- A aplicacao continua iniciando mesmo se a escrita do arquivo de log falhar.
- Nenhum conteudo real de `.env` e registrado no arquivo de log.

## Testes sugeridos

- Rodar `node --check app.js`.
- Rodar `node --check src\services\webLogger.js`, se criado.
- Rodar `node --check` nos arquivos JavaScript alterados.
- Iniciar a aplicacao com `npm start`.
- Confirmar no terminal as mensagens de startup.
- Confirmar que o arquivo em `log/` recebeu as mesmas mensagens.
- Fazer login e confirmar que usuario/evento aparecem sem senha.
- Executar um script pelo painel e confirmar que eventos web aparecem no arquivo.
- Forcar um erro controlado, por exemplo script inexistente, e confirmar que `console.error` foi registrado.

## Validacao esperada

- `node --check app.js`
- `node --check src\services\webLogger.js`, se criado
- `node --check src\services\authService.js`, se alterado
- `node --check src\services\ldapService.js`, se alterado
- `node --check src\routes\authRoutes.js`, se alterado
- `node --check src\routes\mainRoutes.js`, se alterado
- Validacao manual com a aplicacao web em execucao, conferindo terminal e arquivo em `log/`.

Se a validacao manual exigir login, usar os dados do `.env` apenas localmente e nunca imprimir seu conteudo em logs, respostas ou arquivos de documentacao.
