const test = require('node:test');
const assert = require('node:assert/strict');
const { EventEmitter } = require('events');
const nativeFs = require('fs');
const childProcess = require('child_process');
const {
    createRequest,
    createResponse,
    freshRequire,
    getRouteHandler,
    installModuleMock,
    patchObject,
    projectPath
} = require('../test-support/testUtils');

function loadMainRouter(t, overrides = {}) {
    const history = overrides.history || {
        addEntry: async () => 1,
        updateEntry: async () => 1
    };
    const restoreHistory = installModuleMock(
        projectPath('src', 'models', 'History.js'),
        history
    );
    const restorePromises = patchObject(nativeFs.promises, {
        readdir: overrides.readdir || (async () => []),
        readFile: overrides.readFile || (async () => '')
    });
    const restoreFs = patchObject(nativeFs, {
        existsSync: overrides.existsSync || (() => true)
    });
    const restoreChildProcess = patchObject(childProcess, {
        spawn: overrides.spawn || (() => {
            throw new Error('O teste tentou iniciar um processo real.');
        })
    });

    t.after(() => {
        delete require.cache[require.resolve('../src/routes/mainRoutes')];
        restoreChildProcess();
        restoreFs();
        restorePromises();
        restoreHistory();
    });

    return freshRequire(projectPath('src', 'routes', 'mainRoutes.js'));
}

function createFakeProcess({ code = 0, stdout = '', stderr = '', processError = null } = {}) {
    const process = new EventEmitter();
    process.stdout = new EventEmitter();
    process.stderr = new EventEmitter();

    queueMicrotask(() => {
        if (stdout) process.stdout.emit('data', Buffer.from(stdout, 'utf8'));
        if (stderr) process.stderr.emit('data', Buffer.from(stderr, 'utf8'));
        if (processError) process.emit('error', processError);
        process.emit('close', code);
    });
    return process;
}

test('painel lista somente scripts simulados e ignora outras entradas', async (t) => {
    const restoreConsole = patchObject(console, { error: () => {} });
    t.after(restoreConsole);
    const router = loadMainRouter(t, {
        readdir: async () => ['Pasta', 'README.txt', 'Dois.ps1', 'um.ps1'],
        readFile: async () => {
            const error = new Error('Conteudo indisponivel no fixture');
            error.code = 'ENOENT';
            throw error;
        }
    });
    const handler = getRouteHandler(router, 'get', '/');
    const response = createResponse();

    await handler(createRequest(), response);

    assert.equal(response.view, 'index');
    assert.deepEqual(response.body.scripts.map((script) => script.name), ['Dois.ps1', 'um.ps1']);
    assert.ok(response.body.scripts.every((script) => script.parameters === null));
});

test('painel responde com catalogo vazio quando o filesystem simulado falha', async (t) => {
    const restoreConsole = patchObject(console, { error: () => {} });
    t.after(restoreConsole);
    const router = loadMainRouter(t, {
        readdir: async () => { throw new Error('Falha simulada'); }
    });
    const response = createResponse();

    await getRouteHandler(router, 'get', '/')(createRequest(), response);

    assert.equal(response.view, 'index');
    assert.deepEqual(response.body.scripts, []);
});

test('execucao manual simulada registra running e conclui com saida escapada', async (t) => {
    const historyCalls = [];
    const spawned = [];
    const restoreConsole = patchObject(console, { log: () => {}, error: () => {} });
    t.after(restoreConsole);
    const router = loadMainRouter(t, {
        history: {
            addEntry: async (...args) => { historyCalls.push(['add', ...args]); return 17; },
            updateEntry: async (...args) => { historyCalls.push(['update', ...args]); return 1; }
        },
        spawn: (command, args) => {
            spawned.push({ command, args });
            return createFakeProcess({ stdout: '<script>alert("x")</script>' });
        }
    });
    const request = createRequest({
        body: { script: 'Exemplo.ps1', params: '-Mensagem "Olá mundo"' }
    });
    const response = createResponse();

    await getRouteHandler(router, 'post', '/run-script')(request, response);
    await response.done;

    assert.equal(spawned.length, 1);
    assert.equal(spawned[0].command, 'pwsh.exe');
    assert.ok(spawned[0].args.includes('Olá mundo'));
    assert.equal(historyCalls[0][0], 'add');
    assert.equal(historyCalls[0][1], 'Exemplo.ps1');
    assert.equal(historyCalls[0][4].executionSource, 'manual');
    assert.deepEqual(historyCalls[1].slice(0, 4), [
        'update',
        17,
        '<script>alert("x")</script>',
        'success'
    ]);
    assert.ok(response.body.includes('&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;'));
    assert.equal(response.body.includes('<script>alert'), false);
});

test('execucao manual simulada registra erro sem iniciar processo real', async (t) => {
    const historyCalls = [];
    const restoreConsole = patchObject(console, { log: () => {}, error: () => {} });
    t.after(restoreConsole);
    const router = loadMainRouter(t, {
        history: {
            addEntry: async () => 22,
            updateEntry: async (...args) => { historyCalls.push(args); return 1; }
        },
        spawn: () => createFakeProcess({ code: 1, stderr: 'Falha <interna>' })
    });
    const response = createResponse();

    await getRouteHandler(router, 'post', '/run-script')(
        createRequest({ body: { script: 'Falha.ps1', params: '' } }),
        response
    );
    await response.done;

    assert.equal(historyCalls.length, 1);
    assert.equal(historyCalls[0][0], 22);
    assert.equal(historyCalls[0][2], 'error');
    assert.equal(historyCalls[0][3], 'Falha <interna>');
    assert.ok(response.body.includes('Falha &lt;interna&gt;'));
});

test('execucao manual rejeita nome invalido antes de historico e executor', async (t) => {
    let historyCalled = false;
    let spawnCalled = false;
    const restoreConsole = patchObject(console, { log: () => {}, error: () => {} });
    t.after(restoreConsole);
    const router = loadMainRouter(t, {
        history: {
            addEntry: async () => { historyCalled = true; },
            updateEntry: async () => {}
        },
        spawn: () => { spawnCalled = true; throw new Error('nao deveria executar'); }
    });
    const response = createResponse();

    await getRouteHandler(router, 'post', '/run-script')(
        createRequest({ body: { script: '../segredo.ps1' } }),
        response
    );

    assert.equal(response.statusCode, 400);
    assert.equal(response.body, 'Nome de script invalido');
    assert.equal(historyCalled, false);
    assert.equal(spawnCalled, false);
});
