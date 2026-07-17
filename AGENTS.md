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

## Como trabalhar

- Comece pelos arquivos diretamente relacionados ao pedido.
- Use `rg` ou `rg --files` para localizar codigo.
- Evite varrer `node_modules`, bancos SQLite, imagens e arquivos gerados.
- Antes de alterar a aplicacao web, confirme que o ponto de entrada ativo e `app.js`, nao `src/app.js`.
- Prefira patches pequenos e localizados.
- Nao reescreva views, CSS, rotas ou controllers inteiros quando um ajuste pontual resolve.
- Nao atualize dependencias, `package-lock.json` ou formato global do projeto sem pedido explicito.
- Nao altere `.env`, dados SQLite, `node_modules` ou arquivos gerados.
- Nao altere arquivos SQLite em `database/` ou `src/database/`, salvo quando a tarefa for especificamente sobre dados locais ou migracao.
- Quando criar uma Task MD em um prompt, nao execute a task automaticamente. Espere solicitacao ou confirmacao do usuario.
- Ao concluir a implementacao de uma Task MD, atualize o controle de release em `src/config/release.js`, usando a data/hora atual do ambiente e incrementando em 1 o numero sequencial no formato `Release DD/MM/YYYY HH:mm - NNN`.

### Assinatura em Task MD

Ao criar ou alterar arquivos `docs/tasks/TASK-*.md`, adicione ao final do arquivo uma assinatura da LLM responsavel pela criacao ou atualizacao da task.

Formato obrigatorio:

```md
---

## Assinatura da LLM

- Data: (data e hora)
- Modelo: nome-do-modelo
- Versao: versao-do-modelo-quando-disponivel (se não disponível, omitir essa linha)
- Acao: criacao | atualizacao
```

Regras:

- Use a data atual do ambiente.
- Informe o nome do modelo de linguagem usado quando estiver disponivel no ambiente ou na conversa.
- Se a versao exata do modelo nao estiver disponivel, use `nao informado`.
- Nao adicionar assinatura em arquivos de codigo-fonte, views, scripts, configs ou documentacao que nao seja task MD.
- Ao atualizar uma task existente, preserve assinaturas anteriores e adicione uma nova assinatura ao final.
- Nao usar essa assinatura como substituto de commit Git ou changelog.

## Padrões do projeto

Para padroes detalhados de codigo, rotas, controllers, models, views, PowerShell, agendamentos, banco e frontend, siga `docs/patterns.md`.

Regras essenciais:

- Use CommonJS (`require`, `module.exports`). Nao introduza ESM.
- Mantenha mensagens de usuario em portugues.
- Models SQLite devem usar placeholders `?`, nunca concatenacao de SQL com entrada do usuario.
- Datas novas devem preferir ISO string (`new Date().toISOString()`), salvo exibicao em view.
- Use `async/await` em controllers e services.
- Rotas autenticadas devem usar `isAuthenticated` em `app.js` ou checagem equivalente no router.
- Views autenticadas geralmente precisam receber `user: req.session.user` e `messages: res.locals.messages`.
- Em EJS, use `<%= ... %>` para saida escapada. Use `<%- ... %>` apenas com HTML confiavel e documente a razao.

## Segurança obrigatória

- Nunca leia, imprima ou inclua conteudo real de `.env` em respostas, logs ou documentacao. Use `.env.example` como referencia.
- Nunca registre senhas, tokens, headers sensiveis, LDAP bind password, `SESSION_SECRET` ou parametros secretos em `console.log`.
- Nao enfraqueca autenticacao, sessao, validacao de script ou protecoes de rota para facilitar implementacao.
- Scripts executaveis devem permanecer restritos a `scripts-ps/`.
- Ao receber nome de script, valide que termina com `.ps1`, nao contem `..`, nao contem `/` nem `\`, e existe dentro de `scripts-ps/`.
- Ao renderizar saida de PowerShell em HTML, escape conteudo nao confiavel para evitar XSS.
- Ao executar processos, use `spawn` com array de argumentos. Nao monte comando concatenado com entrada de usuario.
- Nao introduza `ExecutionPolicy Bypass` em novos pontos sem necessidade clara. Quando mantiver padrao existente do worker, nao amplie permissao alem do fluxo atual.

## Escopo de mudança

- Correcao pequena: altere apenas o arquivo do fluxo afetado e valide sintaxe.
- Nova tela ou CRUD: adicione rota, controller, view e model somente se todos forem necessarios.
- Mudanca de seguranca: mantenha compatibilidade quando possivel, remova logs sensiveis e valide caminhos/entradas.
- Refatoracao: faca apenas se solicitada ou se reduzir risco imediato.
- Evite renomear arquivos publicos ou rotas existentes sem pedido.
- Evite alterar contrato de views sem atualizar todos os callers.
- Evite mover logica entre camadas em tarefa que so pediu ajuste pequeno.
- Evite misturar limpeza, formatacao e feature no mesmo patch.

## Comandos úteis

```powershell
npm start
npm run dev
npm run schedule-worker
node --check app.js
node --check src\routes\mainRoutes.js
```

Observacao: `npm test` ainda nao possui testes reais e retorna erro por configuracao do proprio `package.json`. Para validacao minima, use `node --check` nos arquivos JavaScript alterados e, quando aplicavel, teste manualmente o fluxo afetado.

## Validação esperada

- Rode `node --check` nos arquivos JavaScript alterados.
- Se mexer no bootstrap, rode `node --check app.js`.
- Se mexer em rotas/controllers, valide tambem o arquivo de rota ou controller alterado.
- Se mexer no worker, rode `node --check scripts-js\schedule-worker.js` e, quando seguro, `npm run schedule-worker`.
- Para views/CSS, abra a tela afetada quando houver servidor disponivel ou descreva que a validacao visual nao foi executada.
- Se a validacao visual exigir login, use credenciais locais apenas quando ja fornecidas/autorizadas pelo usuario; nunca imprima ou documente valores do `.env`.
- Se uma validacao nao puder ser executada, informe claramente o motivo.

## Validação com servidor local

- A porta `3000` e exclusiva do usuário/desenvolvedor e pode estar ocupada por
  `npm run dev`.
- O agente nunca deve iniciar, testar, reutilizar ou encerrar processos na porta
  `3000`.
- Para validações HTTP próprias, o agente deve usar a porta `3100` como padrão.
- Sempre iniciar o servidor de validação com a variavel `PORT` definida
  explicitamente.
- Se `3100` estiver ocupada, usar a próxima porta livre a partir de `3101`.
- Ao iniciar servidor para validação, capturar o PID do processo iniciado.
- Ao finalizar a validação, encerrar somente o processo iniciado pelo próprio
  agente.
- Nunca encerrar processos descobertos por porta quando eles não foram iniciados
  pelo agente.

## Git e preservação do trabalho local

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

Ao concluir a implementacao de uma task MD, informe de forma alarmante ao usuario a necessidade de fazer o `git commit`.

Nao cole trechos longos de codigo se o arquivo ja foi alterado no workspace.
