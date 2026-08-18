const test = require('node:test');
const assert = require('node:assert/strict');
const {
    RETRY_SETTINGS,
    RETRY_DEFAULTS,
    validateRetrySetting,
    normalizeRetryPolicy,
    buildRetryDecision,
    buildScheduleFailureState
} = require('../src/services/scheduleRetryPolicy');

test('normaliza defaults e valores persistidos válidos', () => {
    assert.deepEqual(normalizeRetryPolicy({}, { warn: () => {} }), RETRY_DEFAULTS);
    assert.deepEqual(normalizeRetryPolicy({
        schedules: { retry_interval_minutes: '30', max_retry_attempts: '0' }
    }), { retryIntervalMinutes: 30, maxRetryAttempts: 0 });
});

test('valida inteiros e limites da configuração', () => {
    assert.equal(validateRetrySetting(RETRY_SETTINGS.INTERVAL_MINUTES, '1'), '1');
    assert.equal(validateRetrySetting(RETRY_SETTINGS.INTERVAL_MINUTES, '1440'), '1440');
    assert.equal(validateRetrySetting(RETRY_SETTINGS.MAX_ATTEMPTS, '0'), '0');
    assert.equal(validateRetrySetting(RETRY_SETTINGS.MAX_ATTEMPTS, '20'), '20');

    for (const invalid of ['', '-1', '1.5', 'texto', '1441']) {
        assert.throws(() => validateRetrySetting(RETRY_SETTINGS.INTERVAL_MINUTES, invalid));
    }
    assert.throws(() => validateRetrySetting(RETRY_SETTINGS.MAX_ATTEMPTS, '21'));
});

test('usa fallback seguro para configuração persistida inválida', () => {
    const warnings = [];
    const policy = normalizeRetryPolicy({
        schedules: { retry_interval_minutes: 'invalido', max_retry_attempts: '-1' }
    }, { warn: (message) => warnings.push(message) });

    assert.deepEqual(policy, RETRY_DEFAULTS);
    assert.equal(warnings.length, 2);
});

test('agenda somente a quantidade configurada de retentativas', () => {
    const policy = { retryIntervalMinutes: 10, maxRetryAttempts: 3 };
    const failedAt = new Date('2026-08-17T13:00:00.000Z');

    assert.deepEqual(buildRetryDecision(0, policy, failedAt), {
        retryScheduled: true,
        retryExhausted: false,
        retryAttemptCount: 1,
        nextRunAt: '2026-08-17T13:10:00.000Z'
    });
    assert.equal(buildRetryDecision(1, policy, failedAt).retryAttemptCount, 2);
    assert.equal(buildRetryDecision(2, policy, failedAt).retryAttemptCount, 3);
    assert.deepEqual(buildRetryDecision(3, policy, failedAt), {
        retryScheduled: false,
        retryExhausted: true,
        retryAttemptCount: 0,
        nextRunAt: null
    });
});

test('limite zero esgota a ocorrência na primeira falha', () => {
    const decision = buildRetryDecision(0, { retryIntervalMinutes: 5, maxRetryAttempts: 0 });
    assert.equal(decision.retryScheduled, false);
    assert.equal(decision.retryExhausted, true);
});

test('esgotamento avança cron e desativa execução única', () => {
    const failedAt = new Date('2026-08-17T13:00:00.000Z');
    const policy = { retryIntervalMinutes: 5, maxRetryAttempts: 1 };
    const cronState = buildScheduleFailureState({
        enabled: 1,
        retry_attempt_count: 1,
        schedule_type: 'cron',
        cron_expression: '0 8 * * *',
        schedule_timezone: 'America/Sao_Paulo'
    }, policy, failedAt);
    const onceState = buildScheduleFailureState({
        enabled: 1,
        retry_attempt_count: 1,
        schedule_type: 'once'
    }, policy, failedAt);

    assert.equal(cronState.retryAttemptCount, 0);
    assert.equal(cronState.enabled, true);
    assert.equal(cronState.nextDestination, 'next_cron_occurrence');
    assert.equal(cronState.nextRunAt, '2026-08-18T11:00:00.000Z');
    assert.equal(onceState.retryAttemptCount, 0);
    assert.equal(onceState.enabled, false);
    assert.equal(onceState.nextDestination, 'disabled_once');
    assert.equal(onceState.nextRunAt, '2099-12-31T23:59:59.999Z');
});
