const test = require('node:test');
const assert = require('node:assert/strict');
const {
    freshRequire,
    installModuleMock,
    patchObject,
    projectPath
} = require('../test-support/testUtils');

function buildFailureState(row, policy, failedAt) {
    const currentAttempt = Number(row.retry_attempt_count) || 0;
    if (currentAttempt < policy.maxRetryAttempts) {
        return {
            retryScheduled: true,
            retryExhausted: false,
            retryAttemptCount: currentAttempt + 1,
            nextRunAt: new Date(failedAt.getTime() + policy.retryIntervalMinutes * 60000).toISOString(),
            enabled: true,
            nextDestination: 'retry'
        };
    }

    return {
        retryScheduled: false,
        retryExhausted: true,
        retryAttemptCount: 0,
        nextRunAt: '2099-12-31T23:59:59.999Z',
        enabled: row.schedule_type === 'cron',
        nextDestination: row.schedule_type === 'cron' ? 'next_cron_occurrence' : 'disabled_once'
    };
}

function loadSchedule(t, { database = {}, history = {} } = {}) {
    const restores = [
        installModuleMock(projectPath('src', 'database', 'connection.js'), {
            run: async () => ({ changes: 1, lastID: 1 }),
            get: async () => null,
            all: async () => [],
            ...database
        }),
        installModuleMock(projectPath('src', 'database', 'schema.js'), {
            initialize: async () => {}
        }),
        installModuleMock(projectPath('src', 'models', 'History.js'), {
            addEntry: async () => 1,
            updateEntry: async () => 1,
            ...history
        }),
        installModuleMock(projectPath('src', 'services', 'powerShellRunner.js'), {
            getPowerShellExecutable: () => 'pwsh.exe',
            buildPowerShellCommandArgs: () => [],
            isPowerShellExecutionSuccessful: (code, stderr) => code === 0 && !stderr
        }),
        installModuleMock(projectPath('src', 'services', 'scheduleRecurrence.js'), {
            SCHEDULE_TYPES: { ONCE: 'once', CRON: 'cron' },
            getNextOccurrence: () => '2026-08-19T11:00:00.000Z'
        }),
        installModuleMock(projectPath('src', 'services', 'powerShellParameters.js'), {
            parseScriptParametersFromContent: () => ({ parameters: [] }),
            getMissingRequiredParameters: () => [],
            parseRawNamedParameters: () => ({}),
            tokenizePowerShellArgs: () => []
        }),
        installModuleMock(projectPath('src', 'services', 'scheduleRetryPolicy.js'), {
            DISABLED_NEXT_RUN_AT: '2099-12-31T23:59:59.999Z',
            loadScheduleRetryPolicy: async () => ({ retryIntervalMinutes: 5, maxRetryAttempts: 1 }),
            buildScheduleFailureState: buildFailureState
        })
    ];

    t.after(() => {
        delete require.cache[require.resolve('../src/models/Schedule')];
        restores.reverse().forEach((restore) => restore());
    });
    return freshRequire(projectPath('src', 'models', 'Schedule.js'));
}

test('worker seleciona somente jobs vencidos, habilitados e sem lock vigente', async (t) => {
    const now = Date.now();
    const queries = [];
    const Schedule = loadSchedule(t, {
        database: {
            all: async (sql) => {
                queries.push(sql);
                return [
                    { id: 1, enabled: 1, next_run_at: new Date(now - 60000).toISOString(), worker_lock_until: null },
                    { id: 2, enabled: 1, next_run_at: new Date(now + 60000).toISOString(), worker_lock_until: null },
                    { id: 3, enabled: 1, next_run_at: new Date(now - 60000).toISOString(), worker_lock_until: new Date(now + 60000).toISOString() }
                ];
            }
        }
    });

    assert.deepEqual((await Schedule.findDueCandidates()).map((row) => row.id), [1]);
    assert.match(queries[0], /WHERE enabled = 1/);
});

test('worker usa executor fake, atualiza historico e continua depois de falha', async (t) => {
    const historyCalls = [];
    const Schedule = loadSchedule(t, {
        history: {
            addEntry: async (...args) => { historyCalls.push(['add', ...args]); return historyCalls.length; },
            updateEntry: async (...args) => { historyCalls.push(['update', ...args]); return 1; }
        }
    });
    const rows = [
        { id: 1, script_name: 'Falha.ps1', parameters: '', enabled: 1, schedule_type: 'once', retry_attempt_count: 0 },
        { id: 2, script_name: 'Sucesso.ps1', parameters: '', enabled: 1, schedule_type: 'once', retry_attempt_count: 0 }
    ];
    const audits = [];
    const runResults = [];
    const failures = [];
    const restores = [
        patchObject(Schedule, {
            clearStaleLocks: async () => {},
            findDueCandidates: async () => rows,
            setLock: async () => true,
            appendAudit: async (...args) => { audits.push(args); },
            recordRunResult: async (...args) => { runResults.push(args); },
            recordFailure: async (row, policy, details) => {
                failures.push({ row, policy, details });
                return { retryScheduled: true };
            }
        })
    ];
    t.after(() => restores.reverse().forEach((restore) => restore()));
    const executed = [];
    const fixedNow = new Date('2026-08-18T14:00:00.000Z');

    const results = await Schedule.executeDueJobs('C:\Fixture', {
        fileSystem: {
            existsSync: () => true,
            readFileSync: () => ''
        },
        executeProcess: async (scriptPath) => {
            executed.push(scriptPath);
            if (scriptPath.endsWith('Falha.ps1')) {
                return { code: 1, stdout: '', stderr: 'falha simulada' };
            }
            return { code: 0, stdout: 'ok', stderr: '' };
        },
        history: {
            addEntry: async (...args) => { historyCalls.push(['add', ...args]); return historyCalls.length; },
            updateEntry: async (...args) => { historyCalls.push(['update', ...args]); return 1; }
        },
        loadRetryPolicy: async () => ({ retryIntervalMinutes: 5, maxRetryAttempts: 1 }),
        parseParameters: () => ({ parameters: [] }),
        getMissingParameters: () => [],
        parseProvidedParameters: () => ({}),
        tokenizeArguments: () => [],
        now: () => new Date(fixedNow)
    });

    assert.equal(executed.length, 2);
    assert.deepEqual(results, [
        { id: 1, ok: false, exitCode: 1, retryScheduled: true },
        { id: 2, ok: true, exitCode: 0 }
    ]);
    assert.equal(failures.length, 1);
    assert.equal(failures[0].details.auditAction, 'EXECUTE_FINISH');
    assert.equal(runResults.length, 1);
    assert.equal(runResults[0][1].enabled, false);
    assert.equal(runResults[0][1].retry_attempt_count, 0);
    assert.ok(audits.some((call) => call[1] === 'EXECUTE_START'));
    assert.ok(audits.some((call) => call[1] === 'EXECUTE_FINISH'));
    assert.ok(historyCalls.some((call) => call[0] === 'update' && call[3] === 'error'));
    assert.ok(historyCalls.some((call) => call[0] === 'update' && call[3] === 'success'));
});

test('falha do worker agenda retry e limpa lock pelo resultado persistido', async (t) => {
    const Schedule = loadSchedule(t);
    const recorded = [];
    const audits = [];
    const restore = patchObject(Schedule, {
        recordRunResult: async (...args) => { recorded.push(args); },
        appendAudit: async (...args) => { audits.push(args); }
    });
    t.after(restore);
    const row = {
        id: 9,
        script_name: 'Agendado.ps1',
        schedule_type: 'once',
        retry_attempt_count: 0,
        enabled: 1
    };

    const state = await Schedule.recordFailure(row, {
        retryIntervalMinutes: 5,
        maxRetryAttempts: 1
    }, {
        exitCode: 1,
        output: 'falha simulada',
        errorMessage: 'falha simulada',
        auditAction: 'EXECUTE_FINISH'
    });

    assert.equal(state.retryScheduled, true);
    assert.equal(state.retryAttemptCount, 1);
    assert.equal(recorded[0][0], 9);
    assert.equal(recorded[0][1].retry_attempt_count, 1);
    assert.ok(audits.some((call) => call[1] === 'EXECUTE_FINISH'));
});

test('persistencia do resultado remove worker_lock_until', async (t) => {
    const statements = [];
    const Schedule = loadSchedule(t, {
        database: {
            run: async (sql, params) => { statements.push({ sql, params }); return { changes: 1 }; }
        }
    });

    await Schedule.recordRunResult(5, {
        last_run_at: '2026-08-18T14:00:00.000Z',
        last_run_exit_code: 0,
        last_run_output: 'ok',
        next_run_at: '2099-12-31T23:59:59.999Z',
        enabled: false,
        retry_attempt_count: 0
    });

    assert.equal(statements.length, 1);
    assert.match(statements[0].sql, /worker_lock_until = NULL/);
});
