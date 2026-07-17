# TASK-041 - Login automatico do admin local no ambiente de desenvolvimento

## Contexto

O comando `npm run dev` usa `scripts-js/dev.js` para iniciar o `nodemon`, aguardar o servidor responder e abrir o navegador padrao do sistema. Atualmente o navegador abre a raiz da aplicacao, mas o usuario ainda precisa preencher manualmente a tela de login.

O projeto ja oferece autenticacao local por meio de `authenticateUser`/`authenticateLocal`, usando `ADMIN_USER` e `ADMIN_PASSWORD` carregados do `.env`. A sessao autenticada e armazenada em `req.session.user`.

Em desenvolvimento, deseja-se que a janela aberta automaticamente pelo `npm run dev` ja chegue a raiz da aplicacao com a sessao do administrador local estabelecida.

## Objetivo

Ao executar `npm run dev`, autenticar automaticamente o navegador aberto pelo inicializador como administrador local e redireciona-lo para `/`.

A autenticacao deve reutilizar o fluxo local existente e ler as credenciais exclusivamente no servidor, por meio das variaveis:

```text
ADMIN_USER
ADMIN_PASSWORD
```

As credenciais nao podem ser enviadas ao navegador, inseridas na URL, gravadas em arquivo auxiliar, passadas em argumentos de processo ou exibidas em logs.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Ajustar `scripts-js/dev.js` para indicar explicitamente ao processo filho que ele foi iniciado pelo fluxo de desenvolvimento com login automatico.
- Criar uma rota de login automatico exclusiva desse fluxo, com nome claro, por exemplo `/dev-login`.
- Fazer o navegador abrir a rota de desenvolvimento, que deve autenticar no servidor e redirecionar para `/`.
- Reutilizar `authenticateUser(process.env.ADMIN_USER, process.env.ADMIN_PASSWORD, 'local')` ou uma funcao local compartilhada equivalente.
- Criar a sessao pelo mecanismo existente, atribuindo somente o perfil retornado pela autenticacao a `req.session.user`.
- Restringir o endpoint a `NODE_ENV=development` e a uma flag interna definida pelo inicializador `npm run dev`.
- Aceitar o login automatico somente quando a requisicao vier da interface de loopback local.
- Manter o login manual e o login LDAP inalterados.
- Atualizar o controle de release em `src/config/release.js` ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Ler, alterar ou versionar o arquivo `.env`.
- Criar credenciais padrao ou fallback para o administrador.
- Expor `ADMIN_USER`, `ADMIN_PASSWORD` ou `ADMIN_PASSWORD_HASH` ao frontend.
- Colocar credenciais em query string, fragmento, cookie, local storage ou corpo gerado pelo inicializador.
- Desabilitar autenticacao globalmente em desenvolvimento.
- Autenticar automaticamente processos iniciados por `npm start`.
- Disponibilizar a rota de login automatico em producao.
- Alterar a regra atual de autenticacao LDAP.
- Alterar o formato geral da sessao ou enfraquecer `isAuthenticated`.
- Adicionar nova dependencia somente para implementar o redirecionamento ou o login.

## Fluxo proposto

```text
npm run dev
  -> scripts-js/dev.js
  -> inicia app.js com NODE_ENV=development e flag interna de auto login
  -> aguarda o servidor responder
  -> abre http://localhost:<PORT>/dev-login
  -> servidor confirma ambiente, flag e origem loopback
  -> servidor le ADMIN_USER e ADMIN_PASSWORD do process.env
  -> authenticateUser(..., 'local')
  -> req.session.user recebe apenas o perfil autenticado
  -> redirect para /
```

O teste de disponibilidade feito por `scripts-js/dev.js` nao deve consumir ou depender da sessao que sera usada pelo navegador. Ele pode consultar uma rota publica, como `/login`, e abrir `/dev-login` somente depois que o servidor estiver pronto.

## Ativacao exclusiva pelo npm run dev

O inicializador deve fornecer ao processo da aplicacao uma flag interna com nome explicito, por exemplo:

```text
DEV_AUTO_LOGIN_LOCAL=true
```

Essa flag deve ser montada em memoria no `env` do `spawn`; nao deve ser adicionada automaticamente ao `.env` nem ao `.env.example` se ela for um detalhe interno do inicializador.

A rota somente pode executar o login quando todas as condicoes forem verdadeiras:

1. `process.env.NODE_ENV === 'development'`;
2. a flag interna do inicializador estiver habilitada com valor exato e conhecido;
3. a requisicao tiver origem na interface de loopback local;
4. `ADMIN_USER` e `ADMIN_PASSWORD` estiverem definidos e nao vazios;
5. a autenticacao local existente retornar sucesso.

Quando qualquer condicao de ativacao nao for atendida, o endpoint deve responder como rota inexistente (`404`) ou permanecer sem registro no router. Nao deve redirecionar silenciosamente para uma sessao privilegiada.

## Restricao a loopback

Validar a origem usando o endereco efetivo da conexao, sem confiar em headers fornecidos pelo cliente. Considerar somente os formatos locais esperados pelo runtime, como:

```text
127.0.0.1
::1
::ffff:127.0.0.1
```

Nao usar `X-Forwarded-For` para autorizar o login automatico. Nao habilitar `trust proxy` para contornar essa verificacao.

O objetivo e impedir que outro computador na rede obtenha uma sessao administrativa apenas por acessar a rota de desenvolvimento, mesmo se o servidor estiver escutando em todas as interfaces.

## Reutilizacao da autenticacao existente

A rota nao deve comparar diretamente usuario e senha nem duplicar a montagem do perfil. Ela deve chamar o service de autenticacao local existente para preservar o contrato atual:

```js
{
    username,
    displayName: 'Administrador Local',
    type: 'local'
}
```

Somente o objeto `result.user` pode ser armazenado na sessao. A senha e o objeto completo de entrada nunca devem ser persistidos.

Se for necessario exportar `authenticateLocal` para facilitar testes ou reutilizacao, fazer uma alteracao pequena no service e manter `authenticateUser` compativel com todos os callers atuais.

## Tratamento de erros

- Se `ADMIN_USER` ou `ADMIN_PASSWORD` estiver ausente, nao criar sessao.
- Informar no console apenas que a configuracao local esta incompleta, sem imprimir nomes de usuario ou valores.
- Se a autenticacao falhar, redirecionar para `/login` com mensagem amigavel ou retornar erro controlado, sem repetir credenciais.
- Nao encerrar o servidor por falha do login automatico.
- Se o navegador nao puder ser aberto, manter a mensagem atual com uma URL acessivel manualmente.
- A URL manual do fluxo de desenvolvimento pode apontar para `/dev-login`, desde que todas as protecoes continuem ativas.
- Nao registrar cookies, ID de sessao, senha, headers ou o conteudo real das variaveis de ambiente.

## Arquivos provaveis

```text
scripts-js/dev.js
src/routes/authRoutes.js
src/services/authService.js
src/config/release.js
```

Evitar alterar `app.js` se o endpoint puder ser registrado de forma localizada em `authRoutes.js`. Nao criar controller novo apenas para uma rota pequena, salvo se a implementacao crescer e justificar a separacao.

## Criterios de aceite

- Com `ADMIN_USER` e `ADMIN_PASSWORD` validos no ambiente, `npm run dev` abre o navegador na raiz com uma sessao local autenticada.
- O perfil exibido corresponde ao administrador local retornado pelo service existente.
- A senha nao aparece na URL aberta, no HTML, no historico do navegador, nos argumentos dos processos ou nos logs.
- O inicializador continua respeitando `PORT`, usando `3000` como fallback.
- O navegador e aberto somente uma vez, mesmo quando o `nodemon` reinicia a aplicacao.
- `npm start` nao ativa nem disponibiliza o login automatico.
- `NODE_ENV=production` nunca permite o endpoint, mesmo se a flag interna for definida por engano.
- Uma requisicao feita por outro computador da rede nao recebe sessao administrativa.
- Uma requisicao local sem a flag interna nao recebe sessao administrativa.
- Credenciais ausentes ou invalidas levam ao login manual sem derrubar o servidor.
- O formulario de login local continua funcionando normalmente.
- O login LDAP continua funcionando normalmente.
- O logout continua destruindo a sessao; um login automatico posterior exige novo acesso explicito a `/dev-login` durante o mesmo fluxo permitido.
- `isAuthenticated` permanece inalterado e continua protegendo as rotas atuais.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

1. Executar `npm run dev` com credenciais locais validas e confirmar que o navegador chega autenticado em `/`.
2. Reiniciar a aplicacao pelo `nodemon` e confirmar que nenhuma nova aba ou janela e aberta.
3. Fazer logout e confirmar que a sessao foi destruida e que a tela de login manual aparece.
4. Abrir manualmente `/dev-login` no mesmo computador durante `npm run dev` e confirmar o fluxo autorizado.
5. Iniciar com `npm start` e confirmar que `/dev-login` responde como rota inexistente.
6. Iniciar com `NODE_ENV=production` e a flag interna habilitada por engano, confirmando que `/dev-login` permanece indisponivel.
7. Remover temporariamente `ADMIN_USER` ou `ADMIN_PASSWORD` em um ambiente controlado e confirmar falha segura sem vazamento no log.
8. Usar credenciais invalidas em ambiente controlado e confirmar que nenhuma sessao e criada.
9. Acessar a rota a partir de outro equipamento da rede e confirmar rejeicao sem sessao.
10. Inspecionar URL, DevTools, cookies, logs e argumentos dos processos para confirmar ausencia das credenciais.
11. Efetuar login local manual e login LDAP para confirmar que os fluxos existentes nao sofreram regressao.

Nunca imprimir valores reais do `.env` durante os testes ou documentar credenciais em evidencias.

## Validacao esperada na implementacao

Executar verificacao de sintaxe nos JavaScript alterados:

```powershell
node --check scripts-js\dev.js
node --check src\routes\authRoutes.js
node --check src\services\authService.js
node --check src\config\release.js
```

Realizar o teste manual de `npm run dev` em ambiente local autorizado, confirmando abertura do navegador, criacao da sessao e redirecionamento final. Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 17/07/2026 09:40:59
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
