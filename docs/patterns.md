# Patterns do PS Panel

Este guia pretende descrever COMO o código deve ser escrito. Ele descreve os padroes observados no codigo atual do PS Panel. Use-o como referencia ao implementar novas rotas, telas, modelos, workers e scripts, preservando o estilo existente enquanto o projeto evolui.

## Organizacao Geral

- O bootstrap principal da aplicacao fica em `app.js` na raiz.
- Rotas Express ficam em `src/routes/`.
- Controllers ficam em `src/controllers/` quando a rota tem fluxo de formulario ou mais de uma acao relacionada.
- Models ficam em `src/models/` e encapsulam acesso SQLite.
- Services ficam em `src/services/` para integracoes ou regras reutilizaveis fora de HTTP.
- Views EJS ficam em `views/`.
- Assets publicos ficam em `public/`.
- Scripts PowerShell executaveis pela plataforma ficam em `scripts-ps/`.
- Scripts Node auxiliares ou batch ficam em `scripts-js/`.

Ao adicionar uma funcionalidade nova, prefira seguir esta divisao:

```text
src/routes/<feature>Routes.js
src/controllers/<feature>Controller.js
src/models/<Feature>.js
views/<feature>.ejs
```

Para fluxos pequenos, o projeto ainda aceita logica diretamente na rota, como ocorre em `mainRoutes.js`. Para fluxos com CRUD, validacao e multiplas telas, use controller.

## Modulos e Exportacao

O projeto usa CommonJS:

```js
const express = require('express');
const router = express.Router();

module.exports = router;
```

Padroes existentes:

- Rotas exportam uma instancia de `router`.
- Controllers exportam funcoes em `exports.<acao>` ou uma classe com metodos `static`.
- Models exportam uma classe com metodos `static`.
- Services exportam funcoes nomeadas em um objeto.

Evite misturar ESM (`import/export`) com CommonJS neste projeto.

## Bootstrap Express

Novas configuracoes globais devem ser adicionadas no `app.js` principal:

```js
const featureRoutes = require('./src/routes/featureRoutes');

app.use('/feature', isAuthenticated);
app.use('/feature', featureRoutes);
```

Padroes observados:

- `dotenv` e carregado no inicio do bootstrap.
- EJS e configurado com `app.set('view engine', 'ejs')`.
- Views sao servidas a partir de `views/`.
- Assets estaticos sao servidos de `public/`.
- `express-session` armazena `req.session.user`.
- `connect-flash` alimenta `res.locals.messages`.
- Models com schema inicializavel devem ser chamados no startup com `.initialize().catch(console.error)`.

Ao criar uma base nova protegida, registre explicitamente o middleware de autenticacao para essa base.

## Rotas Express

Rotas seguem este formato:

```js
const express = require('express');
const router = express.Router();
const Controller = require('../controllers/controller');

router.get('/', Controller.list);
router.get('/new', Controller.newForm);
router.post('/', Controller.create);

module.exports = router;
```

Convencoes de rota existentes:

- Use `GET` para telas e consultas.
- Use `POST` para criacao, atualizacao, delecao e execucao.
- Para formularios, use redirect apos sucesso ou erro.
- Para endpoints JSON, responda com `res.json(...)`.
- Para erros de tela, use `res.status(500).render('error', { message, error })` quando fizer sentido.
- Para validacao de formulario, grave `req.flash('error', ...)` e redirecione de volta.

Ordem importa em rotas parametrizadas. Em `scheduleRoutes.js`, rotas especificas como `/audit` e `/new` aparecem antes de `/:id/edit`.

## Controllers

Controllers usam `async/await`, `try/catch`, flash messages e redirects:

```js
exports.create = async (req, res) => {
    try {
        await Model.create({ ...req.body, created_by: req.session.user.username });
        req.flash('success', 'Registro criado.');
        res.redirect('/feature');
    } catch (e) {
        console.error(e);
        req.flash('error', 'Erro ao criar registro.');
        res.redirect('/feature/new');
    }
};
```

Padroes a seguir:

- Valide entradas antes de chamar o model.
- Converta IDs com `parseInt(req.params.id, 10)`.
- Use `process.cwd()` para resolver caminhos relativos a raiz do projeto.
- Passe `user: req.session.user` para views autenticadas.
- Passe `messages: res.locals.messages` quando a view usa alerts.
- Preserve valores de formulario quando editar registros existentes.

Quando a validacao depende de arquivo local, use `path.join(process.cwd(), ...)` e confira existencia com `fs.existsSync`.

## Models SQLite

Models seguem uma classe com metodos estaticos e Promises envolvendo a API callback do `sqlite3`:

```js
class Feature {
    static async findById(id) {
        return new Promise((resolve, reject) => {
            db.get('SELECT * FROM feature WHERE id = ?', [id], (err, row) => {
                if (err) reject(err);
                resolve(row);
            });
        });
    }
}

module.exports = Feature;
```

Padroes existentes:

- O caminho do banco fica em `database/*.sqlite`.
- O diretorio `database/` e criado se nao existir.
- Schemas sao criados com `CREATE TABLE IF NOT EXISTS`.
- Indices sao criados com `CREATE INDEX IF NOT EXISTS` quando ha consultas recorrentes.
- Queries usam placeholders `?`, nao concatenacao de strings.
- Datas persistidas por codigo novo tendem a usar ISO string (`new Date().toISOString()`).
- Booleanos sao persistidos como inteiro `1`/`0`.
- Campos opcionais vazios geralmente viram `null`.

Para novas tabelas, prefira adicionar um metodo `initialize()` no model quando a tabela nao puder ser criada no carregamento do modulo.

## Historico e Auditoria

Execucoes de scripts devem registrar historico em `History`:

1. Antes de executar, chame `History.addEntry(scriptName, parameters, username)`.
2. Ao finalizar, chame `History.updateEntry(id, output, status, errorMessage)`.
3. Use `status` como `running`, `success` ou `error`.

Fluxos administrativos sensiveis podem registrar auditoria propria, como `Schedule.appendAudit`:

- Use acoes em caixa alta (`CREATE`, `UPDATE`, `DELETE`, `EXECUTE_START`).
- Armazene detalhes como JSON textual.
- Inclua o usuario quando houver `req.session.user.username`.

## Execucao de PowerShell

O projeto executa scripts com `child_process.spawn`.

Padrao manual atual:

```js
const ps = spawn('powershell.exe', ['-File', scriptPath, ...args]);
```

Padrao do worker:

```js
const ps = spawn('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    scriptPath,
    ...argList
]);
```

Ao adicionar novos fluxos de execucao:

- Restrinja scripts ao diretorio `scripts-ps/`.
- Aceite apenas nomes terminando em `.ps1`.
- Rejeite nomes contendo `..`, `/` ou `\`.
- Acumule `stdout` e `stderr` separadamente.
- Trate o evento `error` do processo.
- No evento `close`, use `code === 0` como sucesso.
- Registre saida e erro no historico.

Parametros hoje sao separados por espacos simples. Se precisar suportar aspas, caminhos com espaco ou escaping, crie um parser compartilhado antes de mudar apenas um fluxo.

## Agendamentos e Workers

Workers em `scripts-js/` devem:

- Calcular a raiz do projeto com `path.join(__dirname, '..')`.
- Fazer `process.chdir(projectRoot)` quando dependem de caminhos relativos.
- Inicializar models antes de executar regras.
- Imprimir resumo em stdout.
- Encerrar com `process.exit(1)` em erro fatal.

Padrao:

```js
async function main() {
    await Model.initialize();
    const results = await Model.executeDueJobs(projectRoot);
    console.log(JSON.stringify({ ran: results.length, results }, null, 2));
}

main().catch((err) => {
    console.error(err);
    process.exit(1);
});
```

Para jobs recorrentes, siga o padrao de lock:

- Limpar locks antigos antes de buscar candidatos.
- Aplicar `worker_lock_until` antes da execucao.
- Registrar inicio e fim em auditoria.
- Limpar lock ao gravar o resultado.
- Reagendar falhas para uma tentativa futura.

## Autenticacao e Sessao

O usuario autenticado vive em `req.session.user`:

```js
req.session.user = result.user;
```

Formato esperado:

```js
{
    username,
    displayName,
    email,
    groups,
    type
}
```

Views autenticadas esperam receber `user`. Rotas protegidas devem usar `isAuthenticated` de `src/middleware/authMiddleware.js` ou uma checagem equivalente.

Ao criar rotas novas, prefira protecao no `app.js`:

```js
app.use('/feature', isAuthenticated);
app.use('/feature', featureRoutes);
```

## Flash Messages

O `app.js` disponibiliza mensagens em `res.locals.messages`:

```js
res.locals.messages = {
    error: req.flash('error'),
    success: req.flash('success'),
    info: req.flash('info')
};
```

Padrao em controllers:

```js
req.flash('success', 'Operacao concluida.');
res.redirect('/feature');
```

Padrao em views:

```ejs
<% if (messages.error && messages.error.length) { %>
    <div class="alert alert-danger"><%= messages.error[0] %></div>
<% } %>
```

Algumas views antigas usam `success` e `error` separados. Em telas novas, prefira `messages` para alinhar com o bootstrap principal.

## Views EJS

As views seguem HTML completo por pagina, sem layout compartilhado efetivo. Componentes pequenos e repetidos podem usar partials EJS, como ocorre com a sidebar em `views/partials/sidebar.ejs`.

Padroes visuais:

- Idioma `pt-BR`.
- Sidebar via partial com links para Scripts, Agendamentos, Historico e Configuracoes.
- Header principal com titulo, subtitulo e, em algumas telas, `logo.png`.
- CSS global em `/styles.css`.
- CSS especifico da pagina em `<style>` dentro da view.
- Font Awesome via CDN para icones.
- HTMX aparece em algumas telas via CDN, mas nem toda view depende dele.

Padroes EJS:

- Use `<%= ... %>` para saida escapada.
- Use `<% ... %>` para controle de fluxo.
- Formate datas com `new Date(value).toLocaleString('pt-BR')`.
- Mostre fallback visual com `|| '—'` para campos vazios.
- Para tabelas, use `forEach`.

Ao criar uma view autenticada, inclua:

- Sidebar pelo partial `views/partials/sidebar.ejs`, passando `user` e `activeMenu`.
- Link ativo correspondente via `activeMenu`.
- `main.main-content`.
- Alerts de `messages`.

## Formularios

Padroes existentes:

- Formularios usam `method="POST"`.
- Inputs preservam valores no modo edicao.
- Acoes destrutivas usam formulario POST com `confirm(...)` no `onsubmit`.
- Botoes principais usam `primary-btn`.
- Acoes secundarias usam `secondary-btn`.
- Botoes compactos usam `icon-btn`.

Para telas com modo novo/editar, use uma variavel `mode`:

```ejs
<form method="POST" action="<%= mode === 'new' ? '/feature' : '/feature/' + item.id %>">
```

## Tratamento de Erros

Padroes observados:

- Logar erro com `console.error(...)`.
- Em telas administrativas, mostrar uma mensagem amigavel via flash.
- Em rotas JSON, retornar `status(500).json({ error: '...' })`.
- Em rotas de pagina, renderizar `error.ejs` quando nao houver um redirect mais adequado.

Exemplo:

```js
try {
    const rows = await Model.findAll();
    res.render('feature', { user: req.session.user, rows, messages: res.locals.messages });
} catch (error) {
    console.error('Erro ao carregar feature:', error);
    res.status(500).render('error', {
        message: 'Erro ao carregar feature',
        error
    });
}
```

## Configuracoes

Configuracoes persistentes usam chaves pontuadas:

```text
scripts.max_execution_time
ui.font_scale
```

`Settings.getAll()` transforma essas chaves em objeto agrupado:

```js
settings.scripts.max_execution_time
settings.ui.font_scale
```

Ao adicionar configuracoes:

- Use uma chave no formato `categoria.nome`.
- Adicione valor padrao em `Settings.initialize()`.
- Valide entradas no controller antes de chamar `Settings.set`.
- Mostre fallback na view.

## Nomes e Estilo

Padroes de nomenclatura:

- Arquivos de models usam PascalCase: `History.js`, `Schedule.js`, `Settings.js`.
- Arquivos de routes usam camelCase com sufixo `Routes`: `scheduleRoutes.js`.
- Arquivos de controllers usam camelCase com sufixo `Controller`: `settingsController.js`.
- Funcoes internas usam camelCase.
- Constantes de regra usam UPPER_SNAKE_CASE, como `LOCK_MS`.
- Mensagens ao usuario estao em portugues.

Estilo de codigo:

- Indentacao predominante de 4 espacos em `src/`, com alguns arquivos usando 2 espacos.
- Strings aparecem com aspas simples e duplas; em codigo novo, prefira aspas simples para alinhar com a maior parte de `src/`.
- Use `async/await` para fluxos assincornos.
- Use callbacks apenas ao adaptar APIs callback como `sqlite3`, `ldapjs` e eventos de `spawn`.

## Cuidados ao Evoluir

Antes de alterar comportamento, observe estes pontos do codigo atual:

- `app.js` da raiz e o bootstrap ativo; `src/app.js` parece legado.
- `/list-scripts` e `/render-scripts` nao tem protecao propria hoje.
- A senha local usa `ADMIN_PASSWORD`, nao `ADMIN_PASSWORD_HASH`.
- `LDAP_SEARCH_FILTER` existe no `.env.example`, mas nao e usado pelo service atual.
- Arquivos SQLite em `database/` contem estado local e podem aparecer modificados no git.

Ao corrigir qualquer um desses pontos, prefira fazer em mudanca pequena e documentada, porque eles podem estar acoplados a operacao atual.
