# TASK-015 - Modularizar menu lateral das views autenticadas

## Contexto

As views autenticadas do PS Panel renderizam HTML completo por pagina e repetem o bloco do menu lateral diretamente em cada arquivo EJS.

A avaliacao encontrou o mesmo padrao de sidebar nas seguintes telas:

```text
views/index.ejs
views/history.ejs
views/schedules.ejs
views/schedule-form.ejs
views/schedule-audit.ejs
views/settings.ejs
```

O bloco repetido contem:

- cabecalho com link para `/`, icone `fa-terminal` e titulo `PS Panel`;
- navegacao para Scripts, Agendamentos, Historico e Configuracoes;
- classe `active` aplicada manualmente ao link da tela atual;
- rodape com dados do usuario;
- link de logout para `/logout`.

Ha pequenas diferencas entre as copias, principalmente no rodape do usuario:

- algumas views exibem `displayName` e `email`;
- outras exibem apenas `displayName || username`;
- algumas formatam o link de logout em uma linha e outras em multiplas linhas.

Essas variacoes indicam que a modularizacao deve preservar o comportamento visual atual, mas tambem pode padronizar o rodape se isso for aceito como parte da tarefa.

## Objetivo

Reduzir repeticao nas views autenticadas extraindo o menu lateral para um partial EJS reutilizavel, mantendo o mesmo visual e comportamento das telas atuais.

## Escopo

- Criar um partial EJS para a sidebar.
- Atualizar as views autenticadas que exibem a sidebar para incluir o partial.
- Permitir indicar qual item do menu deve ficar ativo em cada tela.
- Preservar a exibicao do usuario autenticado.
- Manter textos visiveis em portugues.
- Nao introduzir dependencias, framework frontend ou build step.

## Fora de escopo

- Criar um layout EJS completo para todas as paginas.
- Reescrever a estrutura HTML inteira das views.
- Mover CSS global ou reorganizar `public/styles.css`.
- Alterar rotas, controllers, models ou regras de autenticacao.
- Alterar comportamento de logout.
- Alterar menus ou adicionar novos itens de navegacao.
- Migrar para React, Vue, Alpine, Web Components ou outro framework.
- Refatorar scripts inline das paginas.

## Arquivos provaveis

```text
views/partials/sidebar.ejs
views/index.ejs
views/history.ejs
views/schedules.ejs
views/schedule-form.ejs
views/schedule-audit.ejs
views/settings.ejs
```

Possivelmente:

```text
src/controllers/*.js
src/routes/*.js
```

Somente se for necessario passar uma variavel explicita de item ativo pelo controller. Preferir evitar alteracoes de backend se a propria view puder chamar o partial com o valor local.

## Situacao atual relevante

O projeto ja usa partial EJS em `views/index.ejs`:

```ejs
<%- include('partials/rename-script-modal') %>
```

Portanto, a modularizacao da sidebar pode seguir o mesmo mecanismo sem mudar a stack.

As views autenticadas ja recebem `user` e, em boa parte dos casos, `messages`. A sidebar depende apenas de `user` e do item ativo.

## Requisitos funcionais

1. O menu lateral deve continuar aparecendo nas mesmas telas autenticadas.
2. O link `Scripts` deve continuar apontando para `/`.
3. O link `Agendamentos` deve continuar apontando para `/schedules`.
4. O link `Historico` deve continuar apontando para `/history`.
5. O link `Configuracoes` deve continuar apontando para `/settings`.
6. O item ativo deve continuar correto em cada tela.
7. Telas de agendamento, formulario de agendamento e auditoria devem manter `Agendamentos` como item ativo.
8. A tela principal deve manter `Scripts` como item ativo.
9. A tela de historico deve manter `Historico` como item ativo.
10. A tela de configuracoes deve manter `Configuracoes` como item ativo.
11. O usuario logado deve continuar sendo exibido no rodape da sidebar.
12. O link `Sair` deve continuar apontando para `/logout`.

## Requisitos tecnicos

- Criar `views/partials/sidebar.ejs`.
- Usar `<%- include(...) %>` para incluir o partial nas views.
- Passar o item ativo na chamada do partial, por exemplo:

```ejs
<%- include('partials/sidebar', { activeMenu: 'scripts', user: user }) %>
```

- Usar chaves simples e estaveis para o menu:

```text
scripts
schedules
history
settings
```

- No partial, aplicar `class="active"` somente ao link correspondente.
- Usar `<%= ... %>` para dados do usuario.
- Nao usar `<%- ... %>` para dados vindos de `user`.
- Manter Font Awesome como dependencia visual ja existente.
- Nao introduzir helpers globais no Express sem necessidade.
- Evitar alterar controllers apenas para esta modularizacao, salvo se a implementacao escolhida exigir explicitamente.
- Manter a indentacao e o estilo EJS proximos ao padrao atual.

## Sugestao de implementacao

1. Criar `views/partials/sidebar.ejs` com o HTML atual da sidebar.
2. Dentro do partial, definir uma variavel local segura para o menu ativo:

```ejs
<% const currentMenu = typeof activeMenu !== 'undefined' ? activeMenu : ''; %>
```

3. Aplicar a classe ativa nos links por comparacao simples:

```ejs
<a href="/" class="<%= currentMenu === 'scripts' ? 'active' : '' %>">
```

4. Padronizar o rodape para exibir:
   - `user.displayName`, quando existir;
   - `user.username`, quando `displayName` nao existir;
   - `user.email`, quando existir.
5. Substituir o bloco da sidebar nas views por chamadas ao partial:

```ejs
<%- include('partials/sidebar', { activeMenu: 'scripts', user: user }) %>
```

6. Usar `activeMenu: 'schedules'` em:
   - `views/schedules.ejs`;
   - `views/schedule-form.ejs`;
   - `views/schedule-audit.ejs`.
7. Usar `activeMenu: 'history'` em `views/history.ejs`.
8. Usar `activeMenu: 'settings'` em `views/settings.ejs`.
9. Usar `activeMenu: 'scripts'` em `views/index.ejs`.
10. Remover apenas os blocos duplicados da sidebar, evitando reorganizar conteudo nao relacionado.

## Criterios de aceite

- Existe um partial `views/partials/sidebar.ejs`.
- As views autenticadas listadas no contexto usam o partial em vez de manter copia propria da sidebar.
- O menu lateral continua visualmente igual ou equivalente ao atual.
- O item ativo esta correto em todas as telas afetadas.
- O rodape continua exibindo o usuario autenticado.
- O email do usuario, quando disponivel, nao deixa de aparecer nas telas onde ja aparecia, salvo decisao explicita de padronizacao.
- O link de logout continua funcionando.
- Nenhuma dependencia nova e adicionada.
- Nenhuma rota ou regra de autenticacao e enfraquecida.
- Nao ha alteracao em arquivos SQLite ou dados locais.

## Testes sugeridos

- Abrir `/` autenticado e confirmar `Scripts` ativo.
- Abrir `/schedules` autenticado e confirmar `Agendamentos` ativo.
- Abrir `/schedules/new` autenticado e confirmar `Agendamentos` ativo.
- Abrir `/schedules/audit` autenticado e confirmar `Agendamentos` ativo.
- Abrir `/history` autenticado e confirmar `Historico` ativo.
- Abrir `/settings` autenticado e confirmar `Configuracoes` ativo.
- Confirmar que o nome do usuario aparece no rodape da sidebar.
- Confirmar que o email aparece quando `user.email` estiver disponivel.
- Clicar em cada link do menu e confirmar que navega para a rota esperada.
- Clicar em `Sair` e confirmar que o logout continua funcionando.
- Validar em largura pequena que o menu nao perdeu comportamento responsivo existente.

## Validacao esperada

Como a mudanca proposta envolve apenas EJS, validar visualmente as telas afetadas com o servidor em execucao quando possivel.

Se algum arquivo JavaScript for alterado por necessidade inesperada, rodar `node --check` no arquivo alterado. A implementacao esperada nao deve exigir alteracao em JavaScript.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
