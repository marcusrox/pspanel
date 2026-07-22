# TASK-048 - Gestao de usuarios e trilhas de auditoria

## Contexto

O PS Panel possui um administrador local e autenticacao integrada ao Active Directory, mas ainda nao mantem um cadastro persistente dos usuarios que acessam a aplicacao.

Atualmente existem registros parciais relacionados ao usuario:

- `script_history.username` identifica quem iniciou uma execucao manual; execucoes do worker usam `Agendamento (worker)`;
- `schedule_audit.username` identifica quem criou, editou ou excluiu um agendamento e tambem registra eventos do worker;
- o login cria apenas `req.session.user`, sem registrar primeiro acesso, ultimo acesso, IP ou historico de autenticacoes.

Como os registros usam somente texto livre em `username`, nao existe uma identidade persistente que permita consultar, de forma confiavel e consolidada, os acessos, as execucoes e as alteracoes de agendamentos de cada usuario.

## Objetivo

Criar um cadastro automatico de usuarios a partir do primeiro login bem-sucedido e disponibilizar uma area administrativa para consultar usuarios e suas trilhas de auditoria.

A solucao deve atender aos seguintes pontos:

1. registrar o primeiro e o ultimo login de cada usuario, a forma de autenticacao e metadados seguros do acesso;
2. manter uma trilha de sucessos e falhas de autenticacao, encerramentos de sessao e recusas de acesso relevantes;
3. relacionar execucoes manuais ao usuario persistido, preservando a identificacao textual historica;
4. relacionar criacao, edicao e exclusao de agendamentos ao usuario persistido;
5. permitir consulta administrativa dos usuarios e, por usuario, dos acessos, execucoes e alteracoes de agendamentos.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes funcionais

### Cadastro automatico

Nao sera criado um formulario manual de cadastro nesta etapa.

Depois que a autenticacao e a autorizacao forem concluidas com sucesso, mas antes de disponibilizar a sessao autenticada, o sistema deve:

1. localizar o usuario pela combinacao de forma de autenticacao e nome de usuario normalizado;
2. criar o registro quando for o primeiro login;
3. atualizar os dados conhecidos quando o usuario ja existir;
4. registrar o evento `LOGIN_SUCCESS`;
5. adicionar o identificador persistido do usuario ao objeto salvo em `req.session.user`.

Logins malsucedidos nunca devem criar usuarios. Um usuario LDAP so deve ser criado depois da validacao da senha e da autorizacao pelo grupo configurado, quando essa restricao estiver ativa.

O fluxo deve valer para:

- login manual do administrador local;
- login automatico local de desenvolvimento em `/dev-login`;
- login LDAP/Active Directory.

### Identidade e normalizacao

Cada usuario deve ser identificado unicamente por:

```text
auth_type + normalized_username
```

Regras:

- `auth_type` deve aceitar inicialmente `local` ou `ldap`;
- `normalized_username` deve ser obtido com `trim()` e conversao para minusculas;
- manter tambem `username` com a grafia mais recente retornada pela autenticacao;
- usuarios local e LDAP com o mesmo nome devem continuar sendo identidades diferentes;
- `display_name` e `email` devem ser atualizados em logins posteriores quando a origem de autenticacao retornar novos valores;
- valores vazios nao devem apagar dados validos ja persistidos, salvo regra explicita e testada durante a implementacao.

### Escopo do log de acessos

Nesta task, **log de acessos** significa trilha de autenticacao e sessao, nao o registro de cada pagina ou requisicao HTTP visitada.

Eventos iniciais:

| Acao | Quando registrar |
| --- | --- |
| `LOGIN_SUCCESS` | Autenticacao e autorizacao concluidas e usuario persistido. |
| `LOGIN_FAILURE` | Credenciais invalidas, usuario nao encontrado ou erro de autenticacao. |
| `ACCESS_DENIED` | Credenciais validas, mas autorizacao recusada, por exemplo por grupo do AD. |
| `LOGOUT` | Encerramento solicitado pela rota de logout. |
| `SESSION_ERROR` | Falha ao persistir uma sessao que seria autenticada. |

O registro de expiracao natural da sessao fica fora do escopo, pois o armazenamento atual de sessoes nao fornece um callback confiavel para esse evento.

Falhas de login devem guardar o nome de usuario informado de forma limitada e normalizada para auditoria, mas nao devem criar um registro em `users`. Quando for possivel associar a tentativa a um usuario ja existente sem alterar a resposta publica, `user_id` pode ser preenchido.

As mensagens apresentadas no login nao devem revelar se existe um cadastro local correspondente, nem expor detalhes do AD.

### Metadados do acesso

Guardar, quando disponivel:

- data/hora em ISO string;
- endereco IP;
- `User-Agent`, limitado a um tamanho seguro;
- forma de autenticacao;
- resultado e codigo de motivo controlado pela aplicacao;
- nome de usuario em formato de snapshot;
- identificador do usuario, quando conhecido.

O endereco IP deve ser obtido por um helper compartilhado. Nao confiar diretamente em `X-Forwarded-For` nem habilitar `trust proxy` de forma ampla. Se a instalacao usar proxy reverso, a confianca no proxy deve ser configurada explicitamente para os proxies conhecidos antes de considerar o IP encaminhado.

Nao armazenar:

- senha;
- hash de senha;
- bind password do LDAP;
- cookie ou identificador bruto de sessao;
- headers de autenticacao;
- lista completa de grupos do AD;
- stack trace ou mensagem bruta de erro de LDAP no banco.

### Acesso a area administrativa

Os dados de usuarios e auditoria sao sensiveis. Nesta etapa, a nova area deve ser acessivel somente pelo administrador local autenticado.

A autorizacao deve ser aplicada no servidor por middleware dedicado, alem de ocultar o item do menu para usuarios sem permissao. A checagem deve considerar `req.session.user.type === 'local'` e confirmar o usuario administrativo configurado sem expor o valor de `ADMIN_USER` na interface ou em logs.

Usuarios LDAP continuam podendo usar as funcionalidades atualmente autenticadas, mas nao podem consultar a nova area. Papeis administrativos para usuarios LDAP ficam fora do escopo.

## Modelo de dados proposto

### Tabela `users`

| Campo | Uso |
| --- | --- |
| `id` | Identificador interno do usuario. |
| `username` | Nome mais recente retornado pela autenticacao. |
| `normalized_username` | Nome normalizado para busca e unicidade. |
| `display_name` | Nome de exibicao mais recente, quando disponivel. |
| `email` | E-mail mais recente, quando disponivel. |
| `auth_type` | `local` ou `ldap`. |
| `first_login_at` | Data do primeiro login bem-sucedido. |
| `last_login_at` | Data do login bem-sucedido mais recente. |
| `last_login_ip` | IP do login bem-sucedido mais recente. |
| `last_user_agent` | Navegador/cliente mais recente, com limite de tamanho. |
| `login_count` | Quantidade de logins bem-sucedidos. |
| `created_at` | Data de criacao do registro. |
| `updated_at` | Data da ultima atualizacao do cadastro. |

Criar restricao unica para `(auth_type, normalized_username)` e indices para as consultas por ultimo login, tipo de autenticacao e nome normalizado.

### Tabela `access_audit`

| Campo | Uso |
| --- | --- |
| `id` | Identificador do evento. |
| `user_id` | Usuario relacionado, permitindo `NULL` em falhas sem usuario conhecido. |
| `username` | Snapshot do nome informado ou autenticado. |
| `auth_type` | Forma de autenticacao solicitada. |
| `action` | Acao controlada, como `LOGIN_SUCCESS`, `LOGIN_FAILURE`, `ACCESS_DENIED`, `LOGOUT` ou `SESSION_ERROR`. |
| `success` | Inteiro `1` ou `0`. |
| `reason_code` | Codigo interno nao sensivel e de vocabulario controlado. |
| `ip_address` | IP normalizado, quando disponivel. |
| `user_agent` | Identificacao limitada do cliente, quando disponivel. |
| `details` | JSON textual opcional somente com dados permitidos. |
| `created_at` | Data do evento em ISO string. |

Criar indices ao menos para `user_id + created_at`, `created_at`, `action` e `username`.

### Evolucao de `script_history`

Adicionar campos opcionais aos registros de execucao:

| Campo | Uso |
| --- | --- |
| `user_id` | Usuario persistido que iniciou a execucao manual. |
| `auth_type` | Forma de autenticacao usada pelo usuario naquele momento. |
| `client_ip` | IP da requisicao que iniciou a execucao manual. |
| `execution_source` | `manual` ou `schedule_worker`. |

Manter `username` como snapshot para compatibilidade e legibilidade. Execucoes do worker devem continuar usando `Agendamento (worker)`, com `user_id` nulo e `execution_source = 'schedule_worker'`.

### Evolucao de `schedule_audit`

Adicionar campos opcionais:

| Campo | Uso |
| --- | --- |
| `user_id` | Usuario persistido responsavel pela acao administrativa. |
| `auth_type` | Forma de autenticacao usada pelo usuario naquele momento. |
| `client_ip` | IP da requisicao que originou a alteracao. |

Manter `username` como snapshot. Eventos do worker devem permanecer com `user_id` nulo.

Para `CREATE`, `UPDATE` e `DELETE`, os detalhes devem permitir entender a alteracao sem guardar segredos. Em `UPDATE`, registrar a lista de campos alterados e, quando util, valores anteriores e novos apenas para campos nao sensiveis. Parametros de scripts devem continuar mascarados; nunca copiar senhas ou valores sensiveis para a auditoria.

## Migracao e compatibilidade

Usar o mecanismo de migracoes idempotentes de `src/database/schema.js`.

A migracao deve:

- criar `users` e `access_audit` com `CREATE TABLE IF NOT EXISTS`;
- criar os indices necessarios com `CREATE INDEX IF NOT EXISTS`;
- adicionar as novas colunas a `script_history` e `schedule_audit` somente quando ainda nao existirem;
- nao editar manualmente os arquivos `.sqlite`;
- nao apagar, recriar ou reescrever registros existentes.

Registros historicos existentes permanecem com `user_id` nulo e continuam consultaveis por seu `username` textual. Nao tentar inferir retroativamente `auth_type`, IP ou identidade, pois esses dados nao existem e nomes iguais podem pertencer a origens diferentes.

O administrador local e os usuarios LDAP serao cadastrados gradualmente em seus proximos logins bem-sucedidos.

## Fluxos esperados

### Login bem-sucedido

```text
requisicao de login
  -> validar credenciais
  -> aplicar autorizacao LDAP, quando configurada
  -> coletar metadados seguros da requisicao
  -> criar ou atualizar users
  -> registrar LOGIN_SUCCESS
  -> incluir user.id em req.session.user
  -> salvar a sessao
  -> redirecionar para a aplicacao
```

Se nao for possivel persistir o usuario ou o evento obrigatorio de sucesso, nao criar uma sessao autenticada. Exibir mensagem generica e registrar no console somente informacoes nao sensiveis.

Se `req.session.save` falhar depois do registro de sucesso, registrar `SESSION_ERROR` para deixar claro que a autenticacao ocorreu, mas o acesso nao foi concluido.

### Login malsucedido

```text
requisicao de login
  -> autenticacao ou autorizacao falha
  -> registrar LOGIN_FAILURE ou ACCESS_DENIED sem criar usuario
  -> manter a resposta publica atual e segura
  -> nao criar req.session.user
```

Uma falha secundaria ao gravar a auditoria de uma tentativa recusada nao deve transformar a tentativa em sucesso nem substituir a mensagem segura apresentada ao usuario.

### Logout

Registrar `LOGOUT` com os dados do usuario e da requisicao antes de destruir a sessao. Se a auditoria falhar, o logout ainda deve prosseguir para nao manter o usuario preso a uma sessao.

### Execucao manual

Ao criar a entrada em `script_history`, informar `req.session.user.id`, tipo de autenticacao, IP seguro e `execution_source = 'manual'`, alem do `username` ja gravado.

### Agendamentos

Ao criar, editar ou excluir um agendamento, informar ao model um contexto de auditoria contendo `user_id`, `username`, `auth_type` e IP. Evitar aumentar a lista de argumentos posicionais; preferir um objeto explicito.

Eventos automaticos `EXECUTE_START`, `EXECUTE_ERROR` e `EXECUTE_FINISH` continuam identificados como worker e sem usuario humano associado.

## Tela de usuarios e auditoria

Criar uma area **Usuarios e auditoria**, integrada ao menu lateral apenas para o administrador local.

### Lista de usuarios

Rota sugerida:

```text
GET /users
```

Exibir:

- nome de usuario;
- nome de exibicao;
- e-mail, quando disponivel;
- forma de autenticacao;
- primeiro login;
- ultimo login;
- IP do ultimo login;
- quantidade de logins bem-sucedidos.

Permitir busca por usuario, nome de exibicao ou e-mail, filtro por forma de autenticacao e paginacao. Usar placeholders `?` e limites maximos controlados no servidor.

### Detalhe do usuario

Rota sugerida:

```text
GET /users/:id
```

Exibir o resumo do cadastro e secoes ou abas para:

- acessos e autenticacoes;
- execucoes de scripts;
- criacao, edicao e exclusao de agendamentos.

Cada trilha deve ser ordenada da mais recente para a mais antiga, possuir paginacao propria ou limite controlado e mostrar apenas dados seguros. Datas devem ser formatadas em `pt-BR`, preservando os valores ISO no banco.

### Auditoria global

Rota sugerida:

```text
GET /users/audit
```

Essa rota deve ser declarada antes de `/:id`.

Permitir consultar eventos de todos os usuarios com filtros por usuario, origem de autenticacao, categoria (`acesso`, `execucao`, `agendamento`), acao/status e intervalo de datas. A implementacao pode consolidar os tres conjuntos no controller/service, mas nao deve substituir as tabelas especializadas por uma unica tabela generica nem duplicar todos os eventos.

Na trilha consolidada, distinguir visualmente:

- usuario humano;
- administrador local;
- worker de agendamentos;
- registro historico sem vinculo persistido.

Detalhes JSON de auditoria devem ser interpretados no servidor ou apresentados como texto escapado. Nunca renderizar conteudo nao confiavel com `<%- ... %>`.

## Alteracoes propostas

### Persistencia

Criar models dedicados, por exemplo:

```text
src/models/User.js
src/models/AccessAudit.js
```

Responsabilidades esperadas:

- inicializacao pelo schema compartilhado;
- criacao/atualizacao atomica do usuario no login;
- incremento seguro de `login_count`;
- registro de eventos com vocabulario controlado;
- consultas paginadas e filtradas;
- uso exclusivo de placeholders `?` para valores recebidos.

### Autenticacao

Em `src/routes/authRoutes.js` e, se necessario, em um service pequeno de auditoria/autenticacao:

- integrar o cadastro automatico aos dois pontos de login bem-sucedido;
- diferenciar falha de credenciais e falha de autorizacao por codigo interno, sem depender de comparar mensagens em portugues;
- coletar IP e `User-Agent` de forma centralizada;
- registrar logout;
- salvar `id` no perfil da sessao;
- preservar o contrato atual de `username`, `displayName`, `email`, `groups` e `type`.

O `authService` nao deve receber `req`. Metadados HTTP e persistencia da auditoria devem permanecer na camada de rota/controller ou em service chamado por ela.

### Execucoes

Em `src/routes/mainRoutes.js` e `src/models/History.js`:

- ampliar `History.addEntry` por objeto de opcoes ou parametro final compativel;
- vincular execucoes manuais ao usuario da sessao e ao IP;
- preservar todas as chamadas do worker;
- manter a saida e os erros protegidos contra XSS nas telas.

### Agendamentos

Em `src/controllers/scheduleController.js` e `src/models/Schedule.js`:

- montar contexto de auditoria a partir da sessao e da requisicao;
- relacionar `CREATE`, `UPDATE` e `DELETE` ao `user_id`;
- melhorar os detalhes de `UPDATE` para identificar campos alterados sem registrar valores sensiveis;
- preservar eventos automaticos e a tela atual `/schedules/audit`.

### Rotas e views

Criar, quando necessario:

```text
src/routes/userRoutes.js
src/controllers/userController.js
src/middleware/adminMiddleware.js
views/users.ejs
views/user-detail.ejs
views/user-audit.ejs
```

Registrar `/users` no `app.js` principal com `isAuthenticated` e o middleware administrativo dedicado. Inicializar os novos models no startup de forma consistente com os models atuais.

Atualizar `views/partials/sidebar.ejs` para incluir o item **Usuarios e auditoria** somente para o administrador local, com `activeMenu` apropriado.

### Controle de release e documentacao

Ao concluir a implementacao:

- atualizar `src/config/release.js` com a data/hora atual e incrementar em 1 o numero sequencial;
- atualizar `docs/architecture.md` com as novas tabelas, rotas, models e fluxo de autenticacao/auditoria.

## Seguranca e privacidade

- Nunca registrar senhas, tokens, cookies, IDs brutos de sessao ou segredos do `.env`.
- Nao registrar parametros sensiveis de scripts nas novas trilhas.
- Limitar tamanhos de `username`, IP, `User-Agent`, codigos e detalhes antes da persistencia.
- Validar `auth_type`, `action`, `success`, paginacao, ordenacao e filtros com listas permitidas.
- Usar placeholders `?` em todas as consultas SQLite.
- Usar `<%= ... %>` para saida EJS escapada.
- Nao expor e-mail, IP, eventos ou detalhes de auditoria a usuarios LDAP comuns.
- Nao confiar em headers de proxy sem configuracao explicita de proxies confiaveis.
- Nao enfraquecer `isAuthenticated`, a validacao de scripts, a autorizacao LDAP ou as protecoes de sessao.
- Nao imprimir conteudo real de `.env` durante implementacao ou testes.

## Fora de escopo

- Cadastro manual de usuarios antes do primeiro login.
- Edicao ou exclusao de usuarios.
- Bloqueio/desativacao de usuarios.
- Perfis, papeis e permissoes granulares.
- Conceder acesso administrativo a usuarios LDAP.
- Sincronizacao previa ou em lote com o Active Directory.
- Armazenar grupos completos do AD no cadastro ou na auditoria.
- Registrar toda pagina ou requisicao HTTP acessada.
- Auditar expiracao natural de sessao.
- Encerrar sessoes existentes quando um cadastro for alterado.
- Inferir ou preencher retroativamente `user_id`, IP ou forma de autenticacao em registros antigos.
- Politica automatica de retencao ou expurgo de auditoria.
- Exportacao CSV/PDF das trilhas.
- Alterar dependencias ou `package-lock.json`.
- Alterar manualmente arquivos SQLite.

## Arquivos provaveis

```text
app.js
src/database/schema.js
src/models/User.js
src/models/AccessAudit.js
src/models/History.js
src/models/Schedule.js
src/routes/authRoutes.js
src/routes/mainRoutes.js
src/routes/userRoutes.js
src/controllers/scheduleController.js
src/controllers/userController.js
src/middleware/adminMiddleware.js
src/services/requestAuditContext.js
views/users.ejs
views/user-detail.ejs
views/user-audit.ejs
views/partials/sidebar.ejs
docs/architecture.md
src/config/release.js
```

Os nomes dos novos arquivos podem ser ajustados durante a implementacao, desde que as responsabilidades permaneçam separadas e a mudanca seja localizada.

## Criterios de aceite

- O primeiro login bem-sucedido local ou LDAP cria exatamente um registro de usuario.
- Logins posteriores da mesma origem atualizam o usuario existente, sem duplicacao por diferenca de maiusculas/minusculas.
- Usuarios local e LDAP com o mesmo nome geram registros distintos.
- O cadastro guarda forma de autenticacao, primeiro login, ultimo login, IP mais recente, cliente mais recente e contador de logins.
- Dados de exibicao e e-mail vindos do AD podem ser atualizados sem apagar valores validos por respostas vazias.
- Login LDAP recusado pela regra de grupo nao cria usuario.
- Login bem-sucedido registra `LOGIN_SUCCESS` e inclui `user.id` na sessao.
- Falhas de credenciais registram `LOGIN_FAILURE` sem senha, detalhes brutos do LDAP ou criacao indevida de usuario.
- Falha de autorizacao registra `ACCESS_DENIED` sem expor o grupo permitido.
- Logout registra `LOGOUT` e encerra a sessao mesmo se a gravacao da auditoria falhar.
- Falha ao salvar uma sessao autenticada registra `SESSION_ERROR` quando possivel.
- O auto-login local de desenvolvimento tambem cadastra/atualiza o administrador e gera auditoria.
- Execucoes manuais novas possuem `user_id`, snapshot de usuario, forma de autenticacao, IP e origem `manual`.
- Execucoes agendadas continuam funcionando com origem `schedule_worker` e `user_id` nulo.
- Criacao, edicao e exclusao de agendamentos novas possuem vinculo com o usuario persistido e snapshot textual.
- A auditoria de edicao identifica os campos alterados sem registrar parametros sensiveis.
- Registros historicos com `user_id` nulo continuam aparecendo nas telas existentes e na consulta consolidada.
- A lista de usuarios possui busca, filtro por autenticacao e paginacao.
- O detalhe do usuario apresenta acessos, execucoes e alteracoes de agendamentos em ordem decrescente.
- A auditoria global permite filtrar categoria, usuario, acao/status e periodo.
- A nova area e o item de menu ficam disponiveis somente para o administrador local.
- Uma requisicao direta de usuario LDAP a `/users` ou subrota recebe resposta de acesso negado apropriada e nao revela dados.
- IP e `User-Agent` sao exibidos de forma escapada e armazenados com limites definidos.
- Nenhum segredo, cookie, ID bruto de sessao, grupo completo do AD ou senha aparece no banco, HTML ou logs.
- A migracao e idempotente e preserva todos os registros existentes.
- As telas atuais de historico e auditoria de agendamentos continuam funcionando.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

1. Em banco de teste, autenticar pela primeira vez com o administrador local e confirmar a criacao do usuario e de `LOGIN_SUCCESS`.
2. Repetir o login com variacao de caixa no nome e confirmar que o mesmo registro foi atualizado e `login_count` incrementado.
3. Autenticar um usuario LDAP permitido e confirmar os dados retornados pelo AD, o tipo `ldap` e a auditoria.
4. Usar nomes iguais nas origens local e LDAP e confirmar que existem dois usuarios distintos.
5. Informar senha incorreta para usuario local e LDAP e confirmar `LOGIN_FAILURE`, ausencia de senha e ausencia de novo usuario.
6. Tentar login LDAP valido fora do grupo permitido e confirmar `ACCESS_DENIED` sem provisionamento.
7. Validar `/dev-login` em ambiente de desenvolvimento autorizado e confirmar cadastro e auditoria.
8. Forcar uma falha controlada ao salvar a sessao e confirmar `SESSION_ERROR` sem acesso autenticado.
9. Fazer logout e confirmar o evento e a destruicao da sessao.
10. Executar manualmente um script seguro e confirmar o vinculo com usuario, IP, origem e snapshot textual.
11. Executar um agendamento pelo worker e confirmar `user_id` nulo e origem automatica.
12. Criar, editar e excluir um agendamento e confirmar os tres eventos vinculados ao usuario.
13. Editar um agendamento com parametro sensivel e confirmar que o valor real nao foi gravado na auditoria.
14. Abrir `/users`, testar busca, filtro, paginacao e formatacao de datas.
15. Abrir o detalhe de um usuario e conferir as tres trilhas, inclusive registros sem dados opcionais.
16. Abrir `/users/audit` e testar filtros combinados e limites de pagina.
17. Autenticar como usuario LDAP comum e confirmar que o menu nao aparece e que o acesso direto a todas as rotas administrativas e negado.
18. Testar valores malformados e excessivamente longos de `User-Agent`, filtros e identificadores.
19. Aplicar a inicializacao mais de uma vez e confirmar que a migracao nao duplica tabelas, colunas ou indices.
20. Confirmar que `/history` e `/schedules/audit` continuam exibindo registros antigos e novos.

Nunca imprimir valores reais do `.env`, senhas, cookies ou credenciais durante os testes.

## Validacao esperada na implementacao

Executar `node --check` em todos os arquivos JavaScript criados ou alterados, incluindo no minimo:

```powershell
node --check app.js
node --check src\database\schema.js
node --check src\models\User.js
node --check src\models\AccessAudit.js
node --check src\models\History.js
node --check src\models\Schedule.js
node --check src\routes\authRoutes.js
node --check src\routes\mainRoutes.js
node --check src\routes\userRoutes.js
node --check src\controllers\scheduleController.js
node --check src\controllers\userController.js
node --check src\middleware\adminMiddleware.js
node --check src\services\requestAuditContext.js
node --check src\config\release.js
```

Validar visualmente as novas telas e os fluxos autenticados em servidor temporario na porta `3100` ou na proxima porta livre, sempre com `PORT` definido explicitamente. Nunca iniciar, reutilizar ou encerrar processos na porta `3000`, e encerrar somente o processo iniciado pelo proprio agente.

Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 22/07/2026 11:40
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
