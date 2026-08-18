const test = require('node:test');
const assert = require('node:assert/strict');
const nativeFs = require('fs');
const {
    createRequest,
    createResponse,
    freshRequire,
    installModuleMock,
    patchObject,
    projectPath
} = require('../test-support/testUtils');

function loadController(t, schedule) {
    const restoreSchedule = installModuleMock(
        projectPath('src', 'models', 'Schedule.js'),
        schedule
    );
    const retryModulePath = projectPath('src', 'services', 'scheduleRetryPolicy.js');
    const restoreRetryPolicy = installModuleMock(retryModulePath, {
        loadScheduleRetryPolicy: async () => ({ retryIntervalMinutes: 5, maxRetryAttempts: 3 })
    });
    const restorePromises = patchObject(nativeFs.promises, {
        readdir: async () => [],
        readFile: async () => ''
    });
    const restoreFs = patchObject(nativeFs, { existsSync: () => true });

    t.after(() => {
        delete require.cache[require.resolve('../src/controllers/scheduleController')];
        restoreFs();
        restorePromises();
        restoreRetryPolicy();
        restoreSchedule();
    });
    return freshRequire(projectPath('src', 'controllers', 'scheduleController.js'));
}

test('controller lista agendamentos com politica de retry simulada', async (t) => {
    const controller = loadController(t, {
        findAll: async () => [{
            id: 1,
            script_name: 'Rotina.ps1',
            parameters: '',
            schedule_type: 'cron',
            cron_expression: '0 8 * * *',
            schedule_timezone: 'America/Sao_Paulo',
            retry_attempt_count: 0
        }]
    });
    const response = createResponse();

    await controller.list(createRequest(), response);

    assert.equal(response.view, 'schedules');
    assert.equal(response.body.schedules.length, 1);
    assert.equal(response.body.schedules[0].script_name, 'Rotina.ps1');
    assert.equal(response.body.schedules[0].retry_max_attempts, 3);
});

test('controller cria agendamento once e registra contexto de auditoria', async (t) => {
    const created = [];
    const controller = loadController(t, {
        create: async (value) => { created.push(value); return 10; }
    });
    const request = createRequest({
        body: {
            script_name: 'Rotina.ps1',
            parameters: '',
            enabled: 'on',
            schedule_type: 'once',
            next_run_at: '2026-08-20T08:00'
        }
    });
    const response = createResponse();

    await controller.create(request, response);

    assert.equal(response.redirectedTo, '/schedules');
    assert.equal(created.length, 1);
    assert.equal(created[0].schedule_type, 'once');
    assert.equal(created[0].cron_expression, null);
    assert.equal(created[0].next_run_at, '2026-08-20T11:00:00.000Z');
    assert.equal(created[0].audit_context.username, 'tester');
    assert.deepEqual(request.flashes.at(-1), { type: 'success', message: 'Agendamento criado.' });
});

test('controller cria agendamento cron com proxima execucao calculada', async (t) => {
    let created;
    const controller = loadController(t, {
        create: async (value) => { created = value; return 11; }
    });
    const response = createResponse();

    await controller.create(createRequest({
        body: {
            script_name: 'Recorrente.ps1',
            parameters: '',
            enabled: 'on',
            schedule_type: 'cron',
            recurrence_days: ['1', '5'],
            recurrence_cadence: 'fixed_time',
            recurrence_time: '08:00',
            recurrence_interval: '1'
        }
    }), response);

    assert.equal(response.redirectedTo, '/schedules');
    assert.equal(created.cron_expression, '0 8 * * 1,5');
    assert.equal(created.schedule_timezone, 'America/Sao_Paulo');
    assert.match(created.next_run_at, /^\d{4}-\d{2}-\d{2}T/);
});

test('controller rejeita agendamento invalido antes de persistir', async (t) => {
    let createCalled = false;
    const controller = loadController(t, {
        create: async () => { createCalled = true; }
    });
    const response = createResponse();

    await controller.create(createRequest({
        body: { script_name: '../invalido.ps1', schedule_type: 'once' }
    }), response);

    assert.equal(createCalled, false);
    assert.equal(response.redirectedTo, '/schedules/new');
    assert.equal(response.statusCode, 200);
});

test('controller atualiza e exclui agendamento existente', async (t) => {
    const calls = [];
    const existing = {
        id: 7,
        script_name: 'Anterior.ps1',
        parameters: '',
        schedule_type: 'once'
    };
    const controller = loadController(t, {
        findById: async () => existing,
        update: async (...args) => { calls.push(['update', ...args]); return 1; },
        delete: async (...args) => { calls.push(['delete', ...args]); return 1; }
    });
    const updateRequest = createRequest({
        params: { id: '7' },
        body: {
            script_name: 'Atual.ps1',
            parameters: '',
            enabled: 'on',
            schedule_type: 'once',
            next_run_at: '2026-08-21T09:30'
        }
    });
    const updateResponse = createResponse();
    await controller.update(updateRequest, updateResponse);

    const deleteResponse = createResponse();
    await controller.delete(createRequest({ params: { id: '7' } }), deleteResponse);

    assert.equal(calls[0][0], 'update');
    assert.equal(calls[0][1], 7);
    assert.equal(calls[0][2].script_name, 'Atual.ps1');
    assert.equal(calls[0][3].username, 'tester');
    assert.equal(calls[1][0], 'delete');
    assert.equal(calls[1][1], 7);
    assert.equal(calls[1][2].username, 'tester');
    assert.equal(updateResponse.redirectedTo, '/schedules');
    assert.equal(deleteResponse.redirectedTo, '/schedules');
});
