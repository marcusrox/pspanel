# AGENTS.md

Instrucoes para agentes de IA trabalhando neste repositorio. O objetivo e gerar mudancas pequenas, seguras e alinhadas ao PS Panel, evitando leitura excessiva, vazamento de segredos e quebras por refatoracoes amplas.

## Contexto rapido

PS Panel e uma aplicacao monolitica Node.js/Express para executar e agendar scripts PowerShell por uma interface web.

- Bootstrap principal: `app.js` na raiz.
- Views server-side: `views/*.ejs`.
- Rotas: `src/routes/*Routes.js`.
- Controllers: `src/controllers/*Controller.js`.
- Models SQLite: `src/models/*.js`.
- Services: `src/services/*.js`.
- Assets: `public/`.
- Worker de agendamentos: `scripts-js/schedule-worker.js`.
- Scripts executaveis pela aplicacao: `scripts-ps/*.ps1`.
- Bancos locais: `database/*.sqlite`.

Leia primeiro `docs/patterns.md` para seguir o estilo do projeto. Use `docs/architecture.md` apenas quando precisar entender fluxo, seguranca ou persistencia em mais detalhe.

## Como trabalhar com eficiencia

- Comece por arquivos diretamente relacionados ao pedido. Evite varrer `node_modules`, bancos SQLite, imagens e arquivos gerados.
- Use `rg` ou `rg --files` para localizar codigo. Nao leia arquivos grandes sem necessidade.
- Antes de alterar, identifique o ponto de entrada ativo. Para a aplicacao web, e o `app.js` da raiz, nao `src/app.js`.
- Prefira editar poucos arquivos. Se a tarefa parecer exigir refatoracao ampla, explique a razao e divida em etapas pequenas.
- Nao reescreva views, CSS ou rotas inteiras quando um patch localizado resolve.
- Nao atualize dependencias, `package-lock.json` ou formato global do projeto sem pedido explicito.
- Nao altere arquivos SQLite versionados/localizados em `database/` ou `src/database/` salvo quando a tarefa for especificamente sobre dados locais ou migracao.

## Comandos uteis

```powershell
npm start
npm run dev
npm run schedule-worker
node --check app.js
node --check src\routes\mainRoutes.js
```

Observacao: `npm test` ainda nao possui testes reais e retorna erro por configuracao do proprio `package.json`. Para validacao minima, use `node --check` nos arquivos JavaScript alterados e, quando aplicavel, teste manualmente o fluxo afetado.

## Padroes de codigo

- Use CommonJS (`require`, `module.exports`). Nao introduza ESM.
- Mantenha mensagens de usuario em portugues.
- Siga a organizacao atual:
  - rotas em `src/routes/`;
  - controllers em `src/controllers/`;
  - models em `src/models/`;
  - services em `src/services/`;
  - views em `views/`.
- Para CRUD ou fluxos com formularios, prefira controller. Para ajustes pequenos em fluxo existente, siga o padrao local.
- Models SQLite devem usar placeholders `?`, nunca concatenacao de SQL com entrada do usuario.
- Datas novas devem preferir ISO string (`new Date().toISOString()`), salvo exibicao em view.
- Use `async/await` em controllers e services. Ao envolver APIs callback (`sqlite3`, `ldapjs`, `spawn`), mantenha Promises pequenas e claras.

## Rotas, sessao e views

- Rotas autenticadas devem usar `isAuthenticated` em `app.js` ou checagem equivalente no router.
- Views autenticadas geralmente precisam receber `user: req.session.user` e `messages: res.locals.messages`.
- Use `<%= ... %>` para saida escapada em EJS. Use `<%- ... %>` apenas com HTML confiavel e documente a razao.
- Acoes destrutivas devem continuar usando `POST` e confirmacao visual quando houver interface.
- Ao adicionar rotas parametrizadas, coloque rotas especificas como `/new` e `/audit` antes de `/:id`.

## Seguranca obrigatoria

- Nunca leia, imprima ou inclua conteudo real de `.env` em respostas, logs ou documentacao. Use `.env.example` como referencia.
- Nunca registre senhas, tokens, headers sensiveis, LDAP bind password, `SESSION_SECRET` ou parametros secretos em `console.log`.
- Nao enfraqueca autenticacao, sessao, validacao de script ou protecoes de rota para facilitar implementacao.
- Scripts executaveis devem permanecer restritos a `scripts-ps/`.
- Ao receber nome de script, valide:
  - termina com `.ps1`;
  - nao contem `..`;
  - nao contem `/` nem `\`;
  - existe dentro de `scripts-ps/`.
- Ao renderizar saida de PowerShell em HTML, escape conteudo nao confiavel para evitar XSS.
- Ao executar processos, use `spawn` com array de argumentos. Nao monte comando concatenado com entrada de usuario.
- Nao introduza `ExecutionPolicy Bypass` em novos pontos sem necessidade clara. Quando mantiver padrao existente do worker, nao amplie permissao alem do fluxo atual.

## PowerShell e parametros

- A execucao manual e o worker ja usam `child_process.spawn`.
- Preserve separacao entre `stdout` e `stderr` quando alterar execucao de scripts.
- Registre historico antes da execucao e atualize status ao finalizar.
- Parametros hoje sao simples. Se precisar suportar aspas, caminhos com espaco ou escaping, crie parser compartilhado e cubra os dois fluxos: manual e agendado.
- Nao modifique scripts em `scripts-ps/` como efeito colateral de alteracoes no painel, exceto se o pedido for sobre esses scripts.

## Agendamentos

- O worker fica em `scripts-js/schedule-worker.js` e chama `Schedule.executeDueJobs(projectRoot)`.
- Preserve o lock `worker_lock_until` ao alterar execucao agendada.
- Mantenha auditoria para criacao, atualizacao, exclusao, inicio, erro e fim de execucao.
- Falhas de job devem continuar sendo tratadas sem derrubar toda a fila, salvo mudanca solicitada.

## Banco de dados

- Bancos ficam em `database/*.sqlite`.
- Schemas sao criados por models com `CREATE TABLE IF NOT EXISTS`.
- Para novas tabelas ou colunas, prefira mudanca compativel e inicializacao idempotente.
- Evite apagar, recriar ou limpar tabelas em codigo de aplicacao.
- Nao inclua dados locais de SQLite em commits ou respostas.

## Frontend

- O projeto usa EJS, CSS global em `public/styles.css` e estilos locais em algumas views.
- Mantenha idioma `pt-BR`, sidebar, header e padrao visual existentes.
- Nao transforme a interface em landing page. Este e um painel operacional.
- Ajustes visuais devem ser pontuais e responsivos. Verifique que textos nao se sobrepoem em larguras pequenas.
- Use Font Awesome quando a view ja usar essa dependencia; nao adicione nova biblioteca de icones sem necessidade.

## Escopo de mudanca

Antes de editar, classifique mentalmente a tarefa:

- Correcao pequena: altere apenas o arquivo do fluxo afetado e valide sintaxe.
- Nova tela ou CRUD: adicione rota, controller, view e model somente se todos forem necessarios.
- Mudanca de seguranca: mantenha compatibilidade quando possivel, remova logs sensiveis e valide caminhos/entradas.
- Refatoracao: faca apenas se solicitada ou se reduzir risco imediato. Caso contrario, prefira patch local.

Evite:

- renomear arquivos publicos ou rotas existentes sem pedido;
- alterar contrato de views sem atualizar todos os callers;
- mover logica entre camadas em uma tarefa que so pedia ajuste pequeno;
- misturar limpeza, formatacao e feature no mesmo patch;
- alterar `.env`, dados SQLite, `node_modules` ou arquivos gerados.

## Validacao esperada

Apos alterar codigo:

- Rode `node --check` nos arquivos JavaScript alterados.
- Se mexer no bootstrap, rode `node --check app.js`.
- Se mexer em rotas/controllers, valide tambem o arquivo de rota ou controller alterado.
- Se mexer no worker, rode `node --check scripts-js\schedule-worker.js` e, quando seguro, `npm run schedule-worker`.
- Para views/CSS, abra a tela afetada quando houver servidor disponivel ou descreva que a validacao visual nao foi executada.

Se uma validacao nao puder ser executada, informe isso claramente junto com o motivo.

## Git e preservacao do trabalho local

- Verifique `git status --short` antes de mudancas maiores.
- Nao reverta alteracoes existentes sem pedido explicito.
- Se houver mudancas de usuario no mesmo arquivo, leia com cuidado e preserve-as.
- Nao use `git reset --hard`, `git checkout --` ou comandos destrutivos sem autorizacao explicita.

## Resposta final do agente

Ao concluir, responda de forma breve:

- arquivos alterados;
- comportamento implementado ou corrigido;
- validacoes executadas;
- riscos ou pendencias relevantes.

Nao cole trechos longos de codigo se o arquivo ja foi alterado no workspace.
