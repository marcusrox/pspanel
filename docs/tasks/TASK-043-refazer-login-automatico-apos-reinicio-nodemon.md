# TASK-043 - Refazer login automatico apos reinicio do nodemon

## Contexto

A TASK-041 implementou o login automatico do administrador local quando `npm run dev` abre inicialmente o navegador em `/dev-login`.

O projeto usa o store em memoria padrao do `express-session`. Quando o `nodemon` detecta uma alteracao no codigo e reinicia o processo Node, o navegador conserva o cookie de sessao, mas o novo processo nao possui mais o registro correspondente em memoria. Com isso, `req.session.user` deixa de existir e a aplicacao redireciona o navegador para `/login` na proxima requisicao.

O processo reiniciado pelo `nodemon` continua recebendo do inicializador:

```text
NODE_ENV=development
DEV_AUTO_LOGIN_LOCAL=true
```

Portanto, o fluxo de desenvolvimento pode refazer a autenticacao local usando `ADMIN_USER` e `ADMIN_PASSWORD` do ambiente quando o navegador chegar novamente a `/login`.

## Objetivo

Refazer automaticamente a autenticacao do administrador local na primeira navegacao realizada depois que o `nodemon` reiniciar a aplicacao.

O usuario deve retornar a raiz autenticada sem preencher o formulario, sem precisar fechar ou reabrir o navegador e sem persistir sessoes em banco ou arquivo.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisao de simplicidade

Nao e necessario diferenciar estes cenarios:

- sessao perdida porque o processo foi reiniciado;
- sessao encerrada por logout explicito;
- usuario local que acessou manualmente `/login`.

Em todos eles, quando o ambiente de desenvolvimento autorizado estiver ativo e a requisicao vier de loopback, o sistema pode executar novamente o login automatico.

Assim, depois de um logout explicito, o redirecionamento para `/login` pode autenticar imediatamente o administrador local outra vez. Esse comportamento e intencional e aceito para simplificar o fluxo de desenvolvimento.

## Solucao proposta

Reaproveitar a rota `/dev-login` criada na TASK-041 e transformar o `GET /login` no ponto de recuperacao da sessao.

Fluxo esperado depois do reinicio:

```text
nodemon reinicia o processo Node
  -> MemoryStore perde req.session.user
  -> navegador faz a proxima requisicao
  -> rota protegida redireciona para /login
  -> GET /login confirma desenvolvimento, flag interna e loopback
  -> redirect para /dev-login
  -> /dev-login autentica com ADMIN_USER e ADMIN_PASSWORD no servidor
  -> req.session.user e recriado
  -> redirect para /
```

A recuperacao acontece na primeira requisicao feita pelo navegador depois do reinicio. O `nodemon` nao precisa atualizar a pagina nem abrir outra aba automaticamente.

## Condicoes obrigatorias

O redirecionamento de `/login` para `/dev-login` somente pode ocorrer quando todas as condicoes forem verdadeiras:

1. `process.env.NODE_ENV === 'development'`;
2. `process.env.DEV_AUTO_LOGIN_LOCAL === 'true'`;
3. a requisicao vier diretamente de uma interface de loopback;
4. nao houver uma sessao autenticada;
5. a requisicao nao estiver marcada para exibir o login manual depois de uma falha do auto-login.

Continuar aceitando apenas os enderecos locais ja previstos pela TASK-041:

```text
127.0.0.1
::1
::ffff:127.0.0.1
```

Nao confiar em `X-Forwarded-For` e nao habilitar `trust proxy` para essa verificacao.

## Prevencao de loop em falhas

O fluxo atual de `/dev-login` redireciona para `/login` quando as credenciais estao ausentes, a autenticacao falha ou a sessao nao pode ser salva. Se `/login` passar a encaminhar sempre para `/dev-login`, essas falhas podem criar um loop de redirecionamento.

A implementacao deve impedir esse loop de maneira simples. Solucao sugerida:

```text
/dev-login falhou
  -> redirect para /login?skipAutoLogin=1
  -> GET /login identifica skipAutoLogin=1
  -> renderiza o formulario e a mensagem de erro
```

O marcador nao deve conter credenciais, detalhes internos ou mensagens sensiveis. Aceitar somente o valor exato definido pela aplicacao, ignorando outros valores.

Uma nova navegacao para `/login` sem o marcador pode tentar o login automatico novamente.

## Escopo

- Ajustar `GET /login` em `src/routes/authRoutes.js` para redirecionar ao auto-login nas condicoes autorizadas.
- Reutilizar a verificacao de loopback ja existente, sem duplicar listas de enderecos.
- Ajustar todos os caminhos de falha de `/dev-login` para impedir loop de redirecionamento.
- Preservar as mensagens amigaveis do login manual.
- Manter a autenticacao por `authenticateUser(process.env.ADMIN_USER, process.env.ADMIN_PASSWORD, 'local')`.
- Continuar armazenando somente `result.user` em `req.session.user`.
- Manter as credenciais exclusivamente no processo do servidor.
- Atualizar o controle de release em `src/config/release.js` ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Trocar o `MemoryStore` por SQLite, Redis, arquivo ou outro store persistente.
- Adicionar dependencia de armazenamento de sessao.
- Persistir o perfil do administrador no navegador.
- Criar cookie, token ou marcador para distinguir reinicio de logout.
- Preservar o estado de logout explicito em desenvolvimento.
- Abrir uma nova aba ou janela a cada reinicio do `nodemon`.
- Reiniciar ou alterar o processo pai de `scripts-js/dev.js`.
- Alterar o login LDAP.
- Habilitar auto-login em `npm start` ou producao.
- Ler, alterar, imprimir ou versionar o arquivo `.env`.
- Expor `ADMIN_USER` ou `ADMIN_PASSWORD` em URL, HTML, cookie, log ou argumento de processo.

## Arquivos provaveis

```text
src/routes/authRoutes.js
src/config/release.js
```

`scripts-js/dev.js`, `app.js`, `src/middleware/authMiddleware.js` e `src/services/authService.js` nao devem precisar de alteracao para a solucao proposta. Se a implementacao identificar uma necessidade real, manter o patch localizado e documentar o motivo.

## Criterios de aceite

- `npm run dev` continua abrindo inicialmente o navegador e autenticando o administrador local.
- Depois de uma reinicializacao pelo `nodemon`, a primeira navegacao refaz o login e retorna a aplicacao autenticada.
- Nenhuma nova aba ou janela e aberta quando o `nodemon` reinicia.
- Nao e necessario reiniciar manualmente `npm run dev`.
- A recuperacao funciona tanto para `/` quanto para rotas protegidas que redirecionam a `/login`.
- Um logout explicito pode resultar em novo login automatico ao chegar a `/login`.
- Acesso manual a `/login` em desenvolvimento local pode resultar em login automatico.
- Falta de `ADMIN_USER` ou `ADMIN_PASSWORD` exibe o login manual sem loop de redirecionamento.
- Credenciais invalidas exibem o login manual sem loop de redirecionamento.
- Erro ao salvar a sessao exibe erro controlado sem loop.
- Uma requisicao originada de outro computador continua sem receber sessao administrativa.
- `npm start` e `NODE_ENV=production` continuam sem auto-login.
- O login manual permanece disponivel quando o auto-login falha ou esta desabilitado.
- O login LDAP permanece inalterado.
- Nenhuma credencial aparece em URL, HTML, cookie, argumentos de processo ou logs.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

1. Executar `npm run dev` e confirmar o login automatico inicial.
2. Alterar e salvar um arquivo JavaScript observado pelo `nodemon`.
3. Aguardar o processo reiniciar e atualizar a pagina ja aberta.
4. Confirmar que o navegador passa por `/login` e `/dev-login` e retorna autenticado a `/`.
5. Repetir o reinicio enquanto estiver em uma rota protegida diferente da raiz.
6. Confirmar que o reinicio nao abre outra aba ou janela.
7. Executar logout e confirmar que o redirecionamento para `/login` pode autenticar novamente o admin.
8. Simular `ADMIN_USER` ausente em ambiente controlado e confirmar exibicao do login sem loop.
9. Simular `ADMIN_PASSWORD` ausente ou invalido e confirmar exibicao do login sem loop.
10. Simular falha em `req.session.save` e confirmar tratamento controlado.
11. Tentar acessar `/login` a partir de outro computador da rede e confirmar que o formulario manual e exibido.
12. Iniciar com `npm start` e confirmar que `/login` nao encaminha para `/dev-login`.
13. Iniciar com `NODE_ENV=production` e a flag habilitada por engano, confirmando que o auto-login permanece indisponivel.
14. Inspecionar URL, logs e argumentos dos processos para confirmar ausencia de credenciais.

Nunca imprimir valores reais do `.env` durante os testes ou registrar credenciais em evidencias.

## Validacao esperada na implementacao

```powershell
node --check src\routes\authRoutes.js
node --check src\config\release.js
```

Realizar teste manual controlado com `npm run dev`, incluindo pelo menos um reinicio real provocado pelo `nodemon`. Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 17/07/2026 13:37:41
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
