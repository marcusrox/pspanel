# TASK-047 - Restringir acesso a grupo do Active Directory configuravel

## Contexto

Atualmente, qualquer usuario encontrado no Active Directory que informe uma senha valida pode criar uma sessao e acessar o PS Panel.

O fluxo LDAP ja consulta o atributo `memberOf` e inclui os grupos encontrados em `result.user.groups`, mas essa informacao ainda nao e usada como criterio de autorizacao. A tela **Configuracoes** tambem nao possui um campo para definir qual grupo do AD pode acessar o sistema.

E necessario separar claramente:

- autenticacao: confirmar que usuario e senha sao validos no AD;
- autorizacao: depois da autenticacao, confirmar que o usuario pertence ao grupo permitido.

## Objetivo

Adicionar na tela **Configuracoes** um campo para informar o DN completo do grupo de usuarios do Active Directory autorizado a acessar o PS Panel.

Depois de validar as credenciais LDAP e antes de criar a sessao, o sistema deve verificar se o atributo `memberOf` do usuario contem o grupo configurado. Se o usuario nao pertencer ao grupo, o login deve ser recusado e a tela deve informar claramente que as credenciais foram aceitas, mas o usuario nao possui permissao para acessar o sistema.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes funcionais

### Formato da configuracao

Persistir a configuracao com a chave pontuada:

```text
auth.allowed_ad_group_dn
```

O campo deve receber o DN completo do grupo, por exemplo:

```text
CN=PSPanel-Usuarios,OU=Groups,DC=exemplo,DC=local
```

O valor deve ser removido de espacos nas extremidades antes de ser salvo e comparado.

### Compatibilidade na implantacao

O valor padrao deve ser vazio.

Enquanto `auth.allowed_ad_group_dn` estiver vazio, o login LDAP deve manter o comportamento atual, sem restricao por grupo. A tela de configuracoes deve exibir uma orientacao clara de que deixar o campo vazio permite o acesso de qualquer usuario autenticado no AD.

Essa compatibilidade permite publicar a mudanca, entrar com uma conta administrativa e somente entao ativar a restricao ao salvar o grupo permitido.

### Usuarios afetados

A verificacao de grupo deve valer somente para autenticacao LDAP.

O administrador local deve continuar podendo autenticar sem pertencer ao AD, funcionando como acesso de contingencia caso o grupo seja configurado incorretamente ou o AD esteja indisponivel. Nao alterar as protecoes existentes do login automatico local de desenvolvimento.

### Regra de associacao

Nesta task, considerar associacao direta ao grupo informado, conforme os valores retornados no atributo LDAP `memberOf`.

A comparacao deve:

- aceitar `memberOf` retornado como string unica ou array;
- ignorar diferenca entre letras maiusculas e minusculas;
- remover espacos apenas nas extremidades do DN completo;
- exigir correspondencia do DN completo, sem aceitar comparacao parcial por `CN` ou substring.

Grupos aninhados, nos quais o usuario pertence a outro grupo que por sua vez pertence ao grupo permitido, ficam fora do escopo desta task.

## Fluxo esperado

```text
usuario envia login LDAP
  -> sistema localiza o usuario no AD
  -> sistema valida a senha com bind usando o DN do usuario
  -> sistema carrega auth.allowed_ad_group_dn
  -> configuracao vazia: permite o login por compatibilidade
  -> configuracao preenchida e memberOf contem o DN: permite o login
  -> configuracao preenchida e memberOf nao contem o DN: nega o acesso
  -> somente um login autorizado cria req.session.user
```

A verificacao deve ocorrer depois da senha ser validada, para nao transformar a resposta de autorizacao em um meio de confirmar usuarios ou grupos sem credenciais validas.

## Mensagem de acesso negado

Quando as credenciais forem validas, mas o usuario nao pertencer ao grupo permitido, retornar uma mensagem amigavel e especifica, por exemplo:

```text
Acesso negado: seu usuario foi autenticado, mas nao pertence ao grupo do Active Directory autorizado a acessar o PS Panel.
```

A mensagem deve aparecer na tela de login com o estilo de erro ja existente. Nao criar sessao e nao redirecionar o usuario para uma rota autenticada.

Nao exibir na mensagem publica o DN completo configurado, a lista de grupos do usuario ou detalhes internos da consulta LDAP.

## Tratamento de erros e seguranca

- Se a configuracao estiver preenchida e nao puder ser carregada, negar o login LDAP com uma mensagem generica de erro interno; nao liberar acesso por falha de persistencia.
- Se `memberOf` estiver ausente ou vazio e houver grupo configurado, tratar o usuario como nao autorizado.
- Nao registrar senha, bind password, headers, tokens ou outros segredos.
- Evitar registrar a lista completa de grupos do usuario.
- Nao incluir o grupo permitido em `.env`; a fonte da configuracao deve ser a tabela `settings`.
- Usar placeholders `?` nas operacoes SQLite, preservando o model existente.
- Nao criar `req.session.user` antes da conclusao da autorizacao.
- Nao enfraquecer `isAuthenticated` nem as protecoes das rotas existentes.

## Alteracoes propostas

### Model de configuracoes

Em `src/models/Settings.js`:

- adicionar `auth.allowed_ad_group_dn` aos valores padrao, com string vazia;
- manter a persistencia pelo model e pelos placeholders ja existentes.

### Tela Configuracoes

Em `views/settings.ejs`:

- adicionar uma secao de acordeao chamada **Autenticacao e acesso**;
- adicionar um campo textual para `auth.allowed_ad_group_dn`;
- preencher o campo com o valor salvo usando saida EJS escapada;
- explicar que deve ser informado o DN completo do grupo;
- alertar que o campo vazio permite qualquer usuario autenticado no AD;
- incluir a nova secao no estado padrao do acordeao salvo em `localStorage`.

### Salvamento e validacao

Em `src/controllers/settingsController.js`:

- incluir `auth.allowed_ad_group_dn` na lista explicita de configuracoes permitidas;
- normalizar o valor com `trim()`;
- aceitar string vazia para desativar a restricao;
- quando preenchido, validar que o valor possui formato de DN LDAP aceitavel antes de persistir;
- rejeitar caracteres de controle e valores excessivamente longos;
- apresentar erro amigavel e preservar a configuracao anterior se a validacao falhar.

### Autorizacao LDAP

Em `src/services/authService.js`:

- carregar `auth.allowed_ad_group_dn` depois que o bind com as credenciais do usuario for concluido com sucesso;
- normalizar `user.memberOf` para uma lista segura;
- aplicar a comparacao de DN definida nesta task;
- retornar falha de autorizacao com mensagem especifica quando o grupo nao estiver presente;
- montar e retornar o perfil autenticado somente depois da verificacao;
- manter o login local fora dessa regra.

Se a implementacao extrair a verificacao para uma funcao auxiliar ou service pequeno para facilitar testes, manter a mudanca localizada e sem alterar o contrato publico desnecessariamente.

### Controle de release

Ao concluir a implementacao, atualizar `src/config/release.js` com a data/hora atual e incrementar o numero sequencial, conforme `AGENTS.md`.

## Comportamento de sessoes existentes

A regra sera aplicada em novos logins LDAP. Sessoes que ja existiam antes de salvar ou alterar o grupo permanecem validas ate logout, expiracao ou reinicio do armazenamento de sessoes.

Invalidacao imediata de todas as sessoes existentes fica fora do escopo desta task.

## Fora de escopo

- Suportar grupos aninhados ou a regra LDAP recursiva `LDAP_MATCHING_RULE_IN_CHAIN`.
- Permitir varios grupos autorizados.
- Consultar membros do grupo em uma segunda busca LDAP.
- Alterar o formato de `req.session.user`.
- Alterar o login do administrador local.
- Alterar o auto-login local de desenvolvimento.
- Criar perfis, papeis ou niveis de permissao dentro do PS Panel.
- Invalidar sessoes ja abertas quando a configuracao mudar.
- Mover a configuracao para `.env`.
- Alterar `LDAP_SEARCH_FILTER` ou outras configuracoes de conexao LDAP.
- Atualizar dependencias ou `package-lock.json`.
- Alterar arquivos SQLite manualmente.

## Arquivos provaveis

```text
src/models/Settings.js
src/controllers/settingsController.js
src/services/authService.js
views/settings.ejs
src/config/release.js
```

`src/routes/authRoutes.js` provavelmente nao precisa ser alterado, pois ja apresenta `result.message` quando `authenticateUser` retorna falha. Se a implementacao identificar uma necessidade real nesse arquivo, manter o patch pequeno e documentar o motivo.

## Criterios de aceite

- A tela **Configuracoes** possui uma secao **Autenticacao e acesso** com o campo do DN do grupo permitido.
- O valor salvo reaparece corretamente ao reabrir a tela.
- Um valor vazio e aceito e mantem o comportamento atual do login LDAP.
- A tela avisa claramente que um campo vazio nao restringe usuarios do AD.
- Um DN invalido nao e salvo e gera mensagem amigavel.
- Com o grupo configurado, um usuario LDAP com senha valida e associacao direta ao grupo consegue acessar o sistema.
- A comparacao funciona quando `memberOf` e string ou array e ignora diferencas de caixa.
- Com o grupo configurado, um usuario LDAP com senha valida que nao pertence diretamente ao grupo recebe uma mensagem clara de acesso negado.
- O usuario negado nao recebe `req.session.user` e permanece fora das rotas protegidas.
- Credenciais LDAP invalidas continuam exibindo a mensagem de autenticacao correspondente, sem antecipar informacao sobre autorizacao.
- Ausencia de `memberOf` resulta em acesso negado quando a restricao esta ativa.
- Falha ao carregar a configuracao nao libera o acesso LDAP quando a restricao deveria ser avaliada.
- O administrador local continua autenticando normalmente, independentemente do grupo configurado.
- O auto-login local de desenvolvimento permanece com as protecoes atuais.
- O DN permitido e os grupos do usuario nao sao expostos na mensagem apresentada ao usuario.
- Sessoes existentes nao sao encerradas automaticamente.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

1. Abrir `/settings` e confirmar a nova secao, o texto de ajuda e o campo vazio por padrao.
2. Salvar um DN valido, reabrir a tela e confirmar a persistencia.
3. Informar um DN invalido e confirmar que o valor anterior e preservado e uma mensagem de erro e exibida.
4. Deixar o campo vazio e confirmar que dois usuarios LDAP validos continuam autenticando, mesmo pertencendo a grupos diferentes.
5. Configurar um grupo e autenticar um usuario que seja membro direto dele.
6. Repetir com diferencas de letras maiusculas e minusculas no DN configurado.
7. Autenticar um usuario com senha valida que nao seja membro do grupo e confirmar a mensagem de acesso negado.
8. Confirmar que o usuario negado nao consegue acessar diretamente `/panel`, `/settings` ou outra rota protegida.
9. Testar um usuario sem atributo `memberOf` e confirmar o acesso negado.
10. Informar uma senha LDAP invalida e confirmar que a resposta nao revela a regra de grupo.
11. Simular falha controlada na leitura de `Settings` depois do bind e confirmar que o login LDAP nao e liberado.
12. Autenticar com o administrador local e confirmar que o acesso continua funcionando.
13. Em desenvolvimento local autorizado, confirmar que `/dev-login` continua funcionando.
14. Alterar o grupo configurado enquanto uma sessao LDAP esta aberta e confirmar o comportamento documentado para sessoes existentes.
15. Inspecionar logs e a resposta HTML para confirmar que senhas, DN permitido e grupos do usuario nao foram expostos indevidamente.

Nunca imprimir valores reais do `.env`, senhas ou credenciais durante os testes.

## Validacao esperada na implementacao

```powershell
node --check src\models\Settings.js
node --check src\controllers\settingsController.js
node --check src\services\authService.js
node --check src\config\release.js
```

Validar visualmente a tela de configuracoes e executar os testes manuais de login em servidor temporario na porta `3100` (ou na proxima porta livre), com `PORT` definido explicitamente. Nunca iniciar, reutilizar ou encerrar processos na porta `3000`.

Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados.

---

## Assinatura da LLM

- Data: 22/07/2026 11:05
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
