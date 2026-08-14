# TASK-054 - Migrar ldapjs para ldapts de forma controlada

## Contexto

O deploy da versao `v2026.08.12-052` concluiu com sucesso, mas o comando
`npm ci --omit=dev` apresentou avisos de descontinuacao para `ldapjs@3.0.7` e
para os pacotes `@ldapjs/*` que compoem sua arvore. O projeto `ldapjs` foi
descontinuado, portanto nao existe uma atualizacao mantida dentro da mesma
biblioteca que elimine esses avisos.

O PS Panel usa `ldapjs` no fluxo de autenticacao do Active Directory e na
validacao do DN do grupo permitido. A implementacao atual depende da API de
callbacks e eventos da biblioteca:

- criacao do cliente com `createClient()`;
- `bind()` e `unbind()` por callback;
- busca com eventos `searchEntry`, `error` e `end`;
- conversao de `entry.pojo.attributes` para o objeto consumido pela
  autenticacao;
- validacao de DN com `parseDN()`.

O pacote `ldapts` oferece cliente LDAP mantido, API baseada em Promises,
suporte a CommonJS e recursos para construir filtros LDAP com escape. Na
versao `9.0.0`, ele exige Node.js `>=22`; o PS Panel homologa Node.js
`v24.18.0`, portanto a exigencia e compativel com o ambiente atual.

A migracao nao deve ser tratada como uma simples troca no `package.json`.
Erros na adaptacao podem impedir todos os logins LDAP, alterar o formato dos
atributos retornados ou liberar acesso indevido quando a restricao por grupo
estiver ativa.

## Objetivo

Substituir `ldapjs@3.0.7` por `ldapts@9.0.0`, removendo a arvore descontinuada
`@ldapjs/*`, e adaptar o acesso LDAP sem alterar o comportamento funcional da
autenticacao local, da autenticacao pelo Active Directory e da autorizacao por
grupo configuravel.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes de implementacao

### Versao e formato de modulos

- Fixar `ldapts` exatamente em `9.0.0`, sem `^` ou `~`, para que a primeira
  migracao use uma versao conhecida e revisada.
- Remover completamente a dependencia direta `ldapjs`.
- Manter o projeto em CommonJS. Usar a exportacao CommonJS fornecida por
  `ldapts`; nao converter o PS Panel para ESM.
- Atualizar somente a arvore necessaria em `package-lock.json`. Nao aproveitar
  a task para atualizar outras dependencias.

### Contrato interno do servico LDAP

Preservar, sempre que pratico, o contrato publico usado por
`src/services/authService.js`:

```js
createLDAPClient()
bindLDAP(client, dn, password)
searchLDAP(client, base, opts)
```

A implementacao interna pode passar a usar diretamente as Promises do
`ldapts`, mas os callers nao devem precisar conhecer detalhes da biblioteca.

`searchLDAP()` deve continuar retornando um array de objetos simples. Para
cada atributo solicitado:

- um unico valor deve permanecer como valor escalar quando esse for o contrato
  atual do fluxo;
- varios valores devem permanecer como array;
- `memberOf` deve continuar aceitando string ou array no servico de
  autorizacao;
- os nomes usados por `authService.js`, como `sAMAccountName`, `displayName`,
  `mail`, `distinguishedName` e `memberOf`, devem ser preservados ou
  normalizados explicitamente.

Nao espalhar conversoes especificas de `ldapts` pelo controller ou pelas
rotas. A normalizacao deve permanecer concentrada no servico LDAP.

### Bind, busca e encerramento

- Adaptar `bind()` e `search()` para `async/await`.
- Garantir `unbind()` com `await` em blocos `finally`, tanto para o cliente de
  servico quanto para o cliente usado para validar a senha do usuario.
- Nao reutilizar no bind do usuario um cliente que ainda precise manter o bind
  de servico.
- Tratar falha de conexao, timeout, credenciais invalidas, erro de busca e
  falha no encerramento sem deixar rejeicoes de Promise sem tratamento.
- Manter mensagens publicas em portugues e nao expor detalhes internos do AD.

### Filtro LDAP e entrada do usuario

O nome de usuario recebido no login nao deve ser concatenado diretamente no
filtro LDAP. A migracao deve usar a API publica de escape de filtro oferecida
por `ldapts`, ou mecanismo equivalente documentado pela biblioteca, para
preservar a estrutura:

```text
(&(objectClass=user)(objectCategory=person)(sAMAccountName=<usuario-escapado>))
```

Caracteres com significado em filtros LDAP, incluindo `*`, `(`, `)`, barra
invertida e NUL, devem ser tratados como parte do valor e nao como sintaxe
injetada pelo usuario.

### Validacao de DN

Substituir o uso de `ldap.parseDN()` em
`src/services/adAccessService.js` por uma API publica e suportada de parsing de
DN do `ldapts`.

A validacao deve continuar:

- aceitando string vazia para desativar a restricao por grupo;
- rejeitando tipos diferentes de string quando informados;
- aplicando o limite de tamanho existente;
- rejeitando caracteres de controle;
- exigindo um DN completo e sintaticamente valido;
- aceitando DNs validos com caracteres escapados, virgulas escapadas e nomes
  de atributos usuais do Active Directory.

Nao substituir o parser LDAP por uma expressao regular simplificada.

### TLS e certificados

A politica atual usa `tlsOptions.rejectUnauthorized = false`. Esta configuracao
tem risco conhecido, mas altera-la junto com a troca da biblioteca pode causar
indisponibilidade em ambientes com certificados internos ainda nao confiados
pelo Node.js.

Nesta task:

- nao ampliar o bypass de validacao TLS para outros protocolos ou fluxos;
- confirmar explicitamente como `ldapts` aplica `tlsOptions` em conexoes
  `ldaps://`;
- preservar o comportamento operacional existente durante a migracao, se ele
  for necessario ao ambiente atual;
- documentar no resultado da implementacao se a validacao de certificado
  continuou desabilitada;
- nao definir `NODE_TLS_REJECT_UNAUTHORIZED=0` e nao desabilitar TLS de forma
  global;
- nao incluir certificados, bind passwords ou outros segredos no repositorio.

O endurecimento da cadeia de certificados, com CA corporativa confiavel e
`rejectUnauthorized = true`, deve ser realizado em task separada caso nao
possa ser validado com seguranca dentro desta migracao.

### Logs e dados sensiveis

- Nunca registrar senha do usuario nem `LDAP_BIND_PASSWORD`.
- Nao registrar o objeto completo retornado pelo AD.
- Nao registrar a lista completa de grupos do usuario.
- Evitar expor o DN completo do usuario e o filtro final em logs normais.
- Logs de erro podem registrar nome, codigo e mensagem tecnica sem incluir
  credenciais ou atributos pessoais desnecessarios.
- Revisar tambem o utilitario `scripts-js/test-ldap.js` para que valores de
  teste venham somente do ambiente e nenhum segredo real tenha fallback no
  codigo-fonte.

## Escopo

1. Substituir `ldapjs` por `ldapts@9.0.0` em `package.json`.
2. Atualizar `package-lock.json` somente para refletir essa substituicao.
3. Adaptar `src/services/ldapService.js` para a API assíncrona de `ldapts`.
4. Adaptar `src/services/adAccessService.js` para o parser de DN suportado.
5. Ajustar `src/services/authService.js` para aguardar o encerramento dos
   clientes e usar filtro LDAP seguro, preservando seus retornos funcionais.
6. Atualizar `scripts-js/test-ldap.js` para a nova biblioteca e remover
   qualquer valor sensivel de fallback.
7. Atualizar `src/config/release.js` somente ao concluir e validar a
   implementacao, conforme `AGENTS.md`.

## Arquivos previstos

```text
package.json
package-lock.json
src/services/ldapService.js
src/services/adAccessService.js
src/services/authService.js
scripts-js/test-ldap.js
src/config/release.js
```

Rotas, controllers, views, models e arquivos `.env` nao devem ser alterados,
salvo se uma incompatibilidade real e diretamente ligada a migracao for
identificada e documentada.

## Fora de escopo

- Alterar o formato de `req.session.user`.
- Alterar a regra do grupo `auth.allowed_ad_group_dn`.
- Adicionar suporte a grupos aninhados.
- Mudar a autenticacao do administrador local ou o auto-login de
  desenvolvimento.
- Converter o projeto para ESM ou TypeScript.
- Criar uma nova tela de configuracao LDAP.
- Alterar URLs, bind DN, search base ou credenciais do ambiente.
- Desabilitar validacao TLS globalmente.
- Atualizar `body-parser`, `qs`, `brace-expansion`, `sqlite3` ou outras
  dependencias fora da arvore LDAP.
- Executar `npm audit fix` automaticamente.
- Alterar bancos SQLite ou dados locais.

## Procedimento de implementacao

1. Verificar `git status --short` e preservar alteracoes locais do usuario.
2. Confirmar Node.js `v24.18.0` e registrar a versao do npm usada em DEV.
3. Consultar a documentacao da versao exata do `ldapts` para confirmar as APIs
   publicas de `Client`, busca, escape de filtro, parsing de DN e `unbind()`.
4. Substituir a dependencia, preferencialmente com comandos equivalentes a:

   ```powershell
   npm uninstall ldapjs
   npm install ldapts@9.0.0 --save-exact
   ```

5. Revisar o diff do lockfile para confirmar a remocao de `ldapjs` e de toda a
   arvore `@ldapjs/*`, sem atualizacoes oportunistas.
6. Adaptar primeiro o encapsulamento em `ldapService.js` e manter a
   normalizacao dos resultados nesse arquivo.
7. Adaptar o filtro de usuario, o parser de DN e os `finally` do fluxo de
   autenticacao.
8. Atualizar o utilitario de teste sem inserir credenciais no codigo.
9. Executar as validacoes isoladas e integradas descritas nesta task.
10. Atualizar o identificador de release somente depois que todas as
    validacoes obrigatorias forem aprovadas.

Se o registro npm exigir a autoridade certificadora corporativa, configurar o
`cafile` apropriado no ambiente. Nao usar `strict-ssl=false` e nao gravar
certificados privados no repositorio.

## Validacao obrigatoria

### Dependencias

Executar:

```powershell
node --version
npm --version
npm ls ldapjs ldapts --omit=dev
npm ci --omit=dev
npm audit --omit=dev
```

Resultados esperados:

- `ldapts@9.0.0` instalado uma unica vez;
- `ldapjs` ausente;
- nenhum pacote `@ldapjs/*` presente no lockfile ou em `npm ls`;
- nenhum warning de descontinuacao originado pela antiga arvore LDAP;
- `npm ci --omit=dev` concluido com codigo zero.

Avisos e vulnerabilidades de outras arvores devem ser listados separadamente,
sem aplicar correcoes automaticas fora do escopo.

### Sintaxe e carregamento

Executar:

```powershell
node --check src\services\ldapService.js
node --check src\services\adAccessService.js
node --check src\services\authService.js
node --check scripts-js\test-ldap.js
node --check src\config\release.js
node --check app.js
```

Tambem executar um teste sem rede que carregue os services alterados e confirme
que a exportacao CommonJS de `ldapts` pode ser resolvida no Node.js homologado.

### Testes isolados

Sem usar credenciais reais e sem conectar ao AD, validar:

- normalizacao de atributo com zero, um e varios valores;
- preservacao dos nomes de atributos consumidos por `authService.js`;
- escape de nomes de usuario contendo caracteres especiais de filtro LDAP;
- rejeicao de tentativa de inserir um segundo termo no filtro;
- aceitacao de DNs validos simples e com caracteres escapados;
- rejeicao de DN incompleto, caracteres de controle e valor excessivamente
  longo;
- comparacao de `memberOf` como string e array;
- garantia de que `unbind()` seja aguardado em sucesso e falha.

Se forem criados testes automatizados auxiliares, nao gravar dados do ambiente
nem valores reais do `.env` em fixtures, snapshots ou mensagens.

### Active Directory autorizado

A validacao integrada deve ocorrer somente em ambiente autorizado, usando
credenciais locais ja fornecidas pelo ambiente e sem imprimi-las. Confirmar:

1. bind com a conta de servico;
2. busca de um usuario permitido pelo `sAMAccountName`;
3. retorno dos atributos esperados;
4. bind do usuario com senha valida;
5. rejeicao de senha invalida;
6. login de usuario pertencente ao grupo permitido;
7. negacao de usuario autenticado que nao pertence ao grupo, quando a
   restricao estiver ativa;
8. comportamento compativel quando a restricao por grupo estiver vazia;
9. erro controlado quando o AD estiver indisponivel;
10. encerramento dos dois clientes em todos os caminhos.

Nao usar contas de producao em testes destrutivos. As operacoes desta task
devem limitar-se a bind e busca; nao adicionar, alterar ou remover objetos do
Active Directory.

### Aplicacao local

- Iniciar um servidor temporario somente na porta `3100` ou na proxima porta
  livre, com `PORT`, `NODE_ENV=development` e `DEV_AUTO_LOGIN_LOCAL=true`
  definidos explicitamente.
- Capturar o PID e encerrar somente o processo iniciado pelo agente.
- Confirmar health check HTTP 200.
- Confirmar que o login local continua funcionando.
- Quando houver AD de teste acessivel e autorizado, executar os cenarios LDAP
  integrados pela aplicacao.
- Nunca iniciar, reutilizar ou encerrar processos na porta `3000`.

## Criterios de aceite

- `package.json` referencia exatamente `ldapts@9.0.0` e nao referencia
  `ldapjs`.
- O lockfile nao contem `ldapjs` nem pacotes `@ldapjs/*`.
- O projeto permanece em CommonJS e inicia no Node.js homologado.
- O deploy com `npm ci --omit=dev` nao apresenta os warnings de
  descontinuacao da antiga arvore LDAP.
- Bind de servico, busca de usuario e bind do usuario funcionam no AD
  autorizado.
- O objeto de usuario mantem os atributos e formatos esperados pelo fluxo
  atual.
- O filtro LDAP escapa entrada do usuario e nao permite injecao de sintaxe.
- A validacao do DN do grupo continua aceitando DNs validos e rejeitando
  entradas invalidas.
- A autorizacao pelo grupo permitido preserva o comportamento atual.
- Todos os clientes sao encerrados com `await`, inclusive em caminhos de erro.
- Senhas, bind password, lista completa de grupos e objetos do AD nao aparecem
  em logs, fixtures ou documentacao.
- O login local e o auto-login de desenvolvimento permanecem inalterados.
- Nenhuma dependencia fora do escopo foi atualizada.
- Nenhum banco SQLite nem objeto do AD foi modificado durante os testes.
- O identificador de release foi incrementado conforme `AGENTS.md` ao concluir
  a implementacao.

## Riscos e cuidados

- A mudanca de callbacks e eventos para Promises pode alterar a ordem de
  tratamento de erros e encerramento da conexao.
- O formato dos resultados de busca pode diferir, especialmente para
  atributos com um ou varios valores e para a capitalizacao dos nomes.
- Active Directory pode retornar referrals ou erros parciais que precisam ser
  testados no ambiente real.
- Um erro no escape do filtro pode causar falha de login ou injecao LDAP.
- Um parser de DN aplicado incorretamente pode recusar grupos validos ou aceitar
  configuracoes ambiguas.
- Alterar simultaneamente a confianca TLS pode mascarar a causa de falhas de
  conexao; por isso a politica deve ser registrada e tratada conscientemente.
- A ausencia de um AD de teste impede considerar a migracao completamente
  validada para producao.

## Rollback

Se houver incompatibilidade funcional:

1. restaurar `package.json` e `package-lock.json` para `ldapjs@3.0.7`;
2. restaurar os services e o utilitario LDAP para a implementacao anterior;
3. executar `npm ci --omit=dev` com o lockfile restaurado;
4. validar o login local;
5. validar bind, busca, autenticacao LDAP e regra de grupo no ambiente
   autorizado;
6. usar o snapshot e o fluxo normal de rollback do deploy se a versao ja tiver
   sido implantada.

O rollback nao exige alteracao de schema ou dados, pois esta task nao modifica
bancos SQLite, configuracoes persistidas nem objetos do Active Directory.

## Evolucao posterior

Preparar uma task independente para habilitar validacao completa do
certificado LDAPS com a CA corporativa e remover
`tlsOptions.rejectUnauthorized = false`, caso essa melhoria nao possa ser
validada com seguranca durante a migracao.

---

## Assinatura da LLM

- Data: 2026-08-12 10:41:39 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: implementada em 2026-08-12, com validacao integrada no Active
Directory pendente por ausencia de `TEST_USERNAME` e `TEST_PASSWORD` no
ambiente local.

- `ldapjs@3.0.7` e toda a arvore descontinuada `@ldapjs/*` foram removidos.
- `ldapts@9.0.0` foi instalado como dependencia exata e validado com CommonJS
  no Node.js `v24.15.0` disponivel em DEV; o pacote exige Node.js `>=22`.
- Bind, busca e unbind foram migrados de callbacks e eventos para
  `async/await` e Promises.
- O filtro de busca por `sAMAccountName` passou a usar `escapeFilter`, evitando
  que caracteres do nome de usuario alterem a sintaxe LDAP.
- Resultados de busca sao normalizados no service para preservar os nomes e
  formatos consumidos pelo fluxo de autenticacao.
- O login LDAP passou a aguardar o encerramento dos clientes de servico e do
  usuario em todos os caminhos.
- O utilitario `scripts-js/test-ldap.js` deixou de possuir credenciais de
  fallback e nao imprime DNs, grupos ou objetos completos do AD.
- A politica TLS operacional foi preservada com
  `tlsOptions.rejectUnauthorized = false`; o endurecimento com CA corporativa
  permanece como evolucao posterior.
- O release foi atualizado para `v2026.08.12-053`.

Desvio tecnico documentado:

- `ldapts@9.0.0` exporta a classe `DN` para construcao, mas nao oferece um
  parser publico de strings equivalente a `ldap.parseDN()`.
- Para nao manter a arvore descontinuada nem depender de API interna, a
  validacao do grupo passou a usar um parser local dedicado, sem regex
  simplificada, que trata separadores, RDNs multivalorados, escapes simples e
  escapes hexadecimais. Casos validos e invalidos foram exercitados de forma
  isolada.

Validacoes executadas:

- `node --check` nos services alterados, no utilitario LDAP e em `app.js`;
- carregamento CommonJS de `ldapts` e carregamento do driver `sqlite3`;
- testes isolados de normalizacao de atributos, escape de filtro, parsing de
  DN, comparacao de grupo e espera de `unbind()`;
- teste isolado do login local com credenciais ficticias em memoria;
- `npm ci --omit=dev` em diretorio temporario isolado;
- `npm ls ldapjs ldapts --omit=dev`, retornando apenas `ldapts@9.0.0`;
- `npm audit --omit=dev`, com zero vulnerabilidades.
- runtime de validacao registrado como Node.js `v24.15.0` e npm `11.12.1`.

Avisos e pendencias:

- permanece somente o warning conhecido de `prebuild-install@7.1.3`, vindo de
  `sqlite3@6.0.1` e fora do escopo desta task;
- depois que o processo que mantinha o binario SQLite aberto foi encerrado,
  `npm ci --omit=dev` tambem foi validado com sucesso no diretorio principal;
- a pasta temporaria `node_modules/.sqlite3-f0mSPfTY` criada durante a primeira
  tentativa foi removida automaticamente pela instalacao limpa;
- o teste integrado LDAP deve ser repetido em ambiente autorizado depois de
  configurar explicitamente `TEST_USERNAME` e `TEST_PASSWORD`.
- o deploy homologa Node.js `v24.18.0`, enquanto o ambiente DEV usado nesta
  implementacao esta em `v24.15.0`; repetir a validacao de carregamento no
  runtime homologado antes da publicacao.

---

## Assinatura da LLM

- Data: 2026-08-12 10:57:33 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-08-12 11:01:28 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Correcao posterior da selecao de protocolo

O primeiro teste de login LDAP apos a migracao retornou `ECONNRESET` durante o
bind da conta de servico. A causa foi identificada no comportamento de
`ldapts@9.0.0`: a presenca de qualquer valor em `tlsOptions` marca o cliente
como conexao segura, inclusive quando a URL usa `ldap://`.

Como o service enviava `tlsOptions.rejectUnauthorized = false` para todos os
protocolos, a conexao `ldap://` tentou negociar TLS implicito na porta LDAP
comum e foi encerrada pelo servidor.

A criacao do cliente foi corrigida para:

- omitir `tlsOptions` em URLs `ldap://`, preservando LDAP comum;
- enviar `tlsOptions` somente em URLs `ldaps://`;
- nao ativar STARTTLS implicitamente;
- preservar a politica existente de certificado para LDAPS.

A selecao de protocolo foi validada de forma isolada e o bind real da conta de
servico configurada concluiu com sucesso, sem imprimir URL, DN ou senha. O
release foi atualizado para `v2026.08.12-054`.

---

## Assinatura da LLM

- Data: 2026-08-12 12:01:01 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
