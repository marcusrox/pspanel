const {
    SCHEDULE_TYPES,
    getNextOccurrence
} = require('./scheduleRecurrence');

const DISABLED_NEXT_RUN_AT = '2099-12-31T23:59:59.999Z';

const RETRY_SETTINGS = Object.freeze({
    INTERVAL_MINUTES: 'schedules.retry_interval_minutes',
    MAX_ATTEMPTS: 'schedules.max_retry_attempts'
});

const RETRY_DEFAULTS = Object.freeze({
    retryIntervalMinutes: 5,
    maxRetryAttempts: 3
});

const RETRY_LIMITS = Object.freeze({
    retryIntervalMinutes: Object.freeze({ min: 1, max: 1440 }),
    maxRetryAttempts: Object.freeze({ min: 0, max: 20 })
});

function parseInteger(value) {
    const normalized = typeof value === 'number' ? String(value) : String(value == null ? '' : value).trim();
    if (!/^\d+$/.test(normalized)) return null;
    const parsed = Number(normalized);
    return Number.isSafeInteger(parsed) ? parsed : null;
}

function getSettingDefinition(key) {
    if (key === RETRY_SETTINGS.INTERVAL_MINUTES) {
        return {
            property: 'retryIntervalMinutes',
            label: 'Intervalo entre retentativas',
            ...RETRY_LIMITS.retryIntervalMinutes
        };
    }
    if (key === RETRY_SETTINGS.MAX_ATTEMPTS) {
        return {
            property: 'maxRetryAttempts',
            label: 'Máximo de retentativas',
            ...RETRY_LIMITS.maxRetryAttempts
        };
    }
    throw new Error('Configuração de retentativa desconhecida.');
}

function validateRetrySetting(key, value) {
    const definition = getSettingDefinition(key);
    const parsed = parseInteger(value);
    if (parsed == null || parsed < definition.min || parsed > definition.max) {
        throw new Error(`${definition.label} deve ser um número inteiro entre ${definition.min} e ${definition.max}.`);
    }
    return String(parsed);
}

function normalizeStoredValue(key, value, warn) {
    const definition = getSettingDefinition(key);
    const parsed = parseInteger(value);
    if (parsed != null && parsed >= definition.min && parsed <= definition.max) return parsed;

    if (typeof warn === 'function') {
        warn(`Configuração ${key} inválida; usando o valor padrão.`);
    }
    return RETRY_DEFAULTS[definition.property];
}

function normalizeRetryPolicy(settings = {}, options = {}) {
    const scheduleSettings = settings.schedules || {};
    const intervalValue = settings[RETRY_SETTINGS.INTERVAL_MINUTES] ?? scheduleSettings.retry_interval_minutes;
    const maxAttemptsValue = settings[RETRY_SETTINGS.MAX_ATTEMPTS] ?? scheduleSettings.max_retry_attempts;

    return {
        retryIntervalMinutes: normalizeStoredValue(RETRY_SETTINGS.INTERVAL_MINUTES, intervalValue, options.warn),
        maxRetryAttempts: normalizeStoredValue(RETRY_SETTINGS.MAX_ATTEMPTS, maxAttemptsValue, options.warn)
    };
}

async function loadScheduleRetryPolicy() {
    const Settings = require('../models/Settings');
    const settings = await Settings.getAll();
    return normalizeRetryPolicy(settings, { warn: (message) => console.warn(message) });
}

function buildRetryDecision(currentRetryAttemptCount, policy, failedAt = new Date()) {
    const currentCount = Number.isInteger(Number(currentRetryAttemptCount)) && Number(currentRetryAttemptCount) >= 0
        ? Number(currentRetryAttemptCount)
        : 0;

    if (currentCount >= policy.maxRetryAttempts) {
        return {
            retryScheduled: false,
            retryExhausted: true,
            retryAttemptCount: 0,
            nextRunAt: null
        };
    }

    const failedAtDate = failedAt instanceof Date ? failedAt : new Date(failedAt);
    if (Number.isNaN(failedAtDate.getTime())) throw new Error('Data da falha inválida.');

    return {
        retryScheduled: true,
        retryExhausted: false,
        retryAttemptCount: currentCount + 1,
        nextRunAt: new Date(failedAtDate.getTime() + policy.retryIntervalMinutes * 60 * 1000).toISOString()
    };
}

function buildScheduleFailureState(schedule, policy, failedAt = new Date()) {
    const failedAtDate = failedAt instanceof Date ? failedAt : new Date(failedAt);
    const retryDecision = buildRetryDecision(schedule.retry_attempt_count, policy, failedAtDate);
    if (retryDecision.retryScheduled) {
        return {
            ...retryDecision,
            enabled: !!schedule.enabled,
            nextDestination: 'retry'
        };
    }

    if (schedule.schedule_type === SCHEDULE_TYPES.CRON) {
        return {
            ...retryDecision,
            nextRunAt: getNextOccurrence(schedule.cron_expression, {
                after: failedAtDate,
                timezone: schedule.schedule_timezone
            }),
            enabled: true,
            nextDestination: 'next_cron_occurrence'
        };
    }

    return {
        ...retryDecision,
        nextRunAt: DISABLED_NEXT_RUN_AT,
        enabled: false,
        nextDestination: 'disabled_once'
    };
}

module.exports = {
    DISABLED_NEXT_RUN_AT,
    RETRY_SETTINGS,
    RETRY_DEFAULTS,
    RETRY_LIMITS,
    validateRetrySetting,
    normalizeRetryPolicy,
    loadScheduleRetryPolicy,
    buildRetryDecision,
    buildScheduleFailureState
};
