const test = require('node:test');
const assert = require('node:assert/strict');
const {
    createRequest,
    createResponse,
    freshRequire,
    getRouteHandler,
    installModuleMock,
    projectPath
} = require('../test-support/testUtils');

function createHistoryModel(t) {
    const rows = [];
    let nextId = 1;
    const database = {
        async run(sql, params) {
            if (sql.includes('INSERT INTO script_history')) {
                const row = {
                    id: nextId++,
                    script_name: params[0],
                    parameters: params[1],
                    username: params[2],
                    start_time: params[3],
                    user_id: params[4],
                    auth_type: params[5],
                    client_ip: params[6],
                    execution_source: params[7],
                    status: 'running',
                    output: null,
                    error_message: null,
                    end_time: null
                };
                rows.push(row);
                return { lastID: row.id, changes: 1 };
            }

            if (sql.includes('UPDATE script_history')) {
                const row = rows.find((candidate) => candidate.id === params[4]);
                if (!row) return { changes: 0 };
                Object.assign(row, {
                    output: params[0],
                    status: params[1],
                    error_message: params[2],
                    end_time: params[3]
                });
                return { changes: 1 };
            }

            throw new Error(`SQL nao esperado no fake: ${sql}`);
        },
        async all(sql, params) {
            if (sql.includes('SELECT * FROM script_history')) {
                const limit = params[0];
                const offset = params[1];
                return [...rows]
                    .sort((a, b) => b.start_time.localeCompare(a.start_time))
                    .slice(offset, offset + limit);
            }
            throw new Error(`SQL nao esperado no fake: ${sql}`);
        },
        async get(sql, params = []) {
            if (sql.includes('COUNT(*)')) return { total: rows.length };
            if (sql.includes('WHERE id = ?')) {
                return rows.find((candidate) => candidate.id === params[0]);
            }
            throw new Error(`SQL nao esperado no fake: ${sql}`);
        }
    };
    const restoreDatabase = installModuleMock(
        projectPath('src', 'database', 'connection.js'),
        database
    );
    const restoreSchema = installModuleMock(
        projectPath('src', 'database', 'schema.js'),
        { initialize: async () => {} }
    );
    t.after(() => {
        delete require.cache[require.resolve('../src/models/History')];
        restoreSchema();
        restoreDatabase();
    });

    return { History: freshRequire(projectPath('src', 'models', 'History.js')), rows };
}

test('historico cria running, conclui sucesso ou erro e permite consulta isolada', async (t) => {
    const { History, rows } = createHistoryModel(t);
    const successId = await History.addEntry('Sucesso.ps1', '-Nome teste', 'tester', {
        startTime: '2026-08-18T10:00:00.000Z',
        userId: 7,
        authType: 'local',
        clientIp: '127.0.0.1',
        executionSource: 'manual'
    });
    const errorId = await History.addEntry('Falha.ps1', '', 'worker', {
        startTime: '2026-08-18T11:00:00.000Z',
        executionSource: 'schedule_worker'
    });

    assert.equal(rows[0].status, 'running');
    await History.updateEntry(successId, 'ok', 'success', null, '2026-08-18T10:01:00.000Z');
    await History.updateEntry(errorId, 'falhou', 'error', 'erro controlado', '2026-08-18T11:01:00.000Z');

    assert.equal((await History.getEntryById(successId)).status, 'success');
    assert.equal((await History.getEntryById(errorId)).error_message, 'erro controlado');
    assert.deepEqual((await History.getHistory(10, 0)).map((row) => row.id), [errorId, successId]);
    assert.equal(await History.countHistory(), 2);
});

function loadHistoryRouter(t, history) {
    const restoreHistory = installModuleMock(
        projectPath('src', 'models', 'History.js'),
        history
    );
    t.after(() => {
        delete require.cache[require.resolve('../src/routes/historyRoutes')];
        restoreHistory();
    });
    return freshRequire(projectPath('src', 'routes', 'historyRoutes.js'));
}

test('rota de historico lista e apresenta detalhe sem acessar banco local', async (t) => {
    const entry = {
        id: 3,
        script_name: 'Exemplo.ps1',
        parameters: '-Senha segredo',
        username: 'tester',
        start_time: '2026-08-18T10:00:00.000Z',
        end_time: '2026-08-18T10:01:00.000Z',
        status: 'success',
        execution_source: 'manual'
    };
    const router = loadHistoryRouter(t, {
        countHistory: async () => 1,
        getHistory: async () => [entry],
        countSearchHistory: async () => 0,
        searchHistory: async () => [],
        getEntryById: async (id) => id === 3 ? entry : null
    });
    const listResponse = createResponse();

    await getRouteHandler(router, 'get', '/')(createRequest(), listResponse);
    assert.equal(listResponse.view, 'history');
    assert.equal(listResponse.body.history[0].id, 3);
    assert.equal(listResponse.body.history[0].parameters.includes('segredo'), false);

    const detailResponse = createResponse();
    await getRouteHandler(router, 'get', '/entry/:id')(
        createRequest({ params: { id: '3' } }),
        detailResponse
    );
    assert.equal(detailResponse.body.id, 3);
    assert.equal(detailResponse.body.execution_source, 'manual');
});

test('detalhe do historico rejeita ID invalido e retorna 404 para ausente', async (t) => {
    const router = loadHistoryRouter(t, {
        getEntryById: async () => null
    });
    const invalidResponse = createResponse();
    await getRouteHandler(router, 'get', '/entry/:id')(
        createRequest({ params: { id: '../1' } }),
        invalidResponse
    );
    assert.equal(invalidResponse.statusCode, 400);

    const missingResponse = createResponse();
    await getRouteHandler(router, 'get', '/entry/:id')(
        createRequest({ params: { id: '99' } }),
        missingResponse
    );
    assert.equal(missingResponse.statusCode, 404);
    assert.equal(missingResponse.body.error, 'Registro não encontrado');
});
