const SCHEDULE_TIMEZONE = 'America/Sao_Paulo';
const SCHEDULE_TYPES = Object.freeze({
    ONCE: 'once',
    CRON: 'cron'
});
const CADENCES = Object.freeze({
    FIXED_TIME: 'fixed_time',
    MINUTES: 'minutes',
    HOURS: 'hours'
});
const ALLOWED_MINUTE_INTERVALS = Object.freeze([1, 2, 3, 4, 5, 6, 10, 12, 15, 20, 30]);
const ALLOWED_HOUR_INTERVALS = Object.freeze([1, 2, 3, 4, 6, 8, 12]);
const DAY_NAMES = Object.freeze([
    'domingo',
    'segunda-feira',
    'terça-feira',
    'quarta-feira',
    'quinta-feira',
    'sexta-feira',
    'sábado'
]);
const DAY_INDEX_BY_SHORT_NAME = Object.freeze({
    Sun: 0,
    Mon: 1,
    Tue: 2,
    Wed: 3,
    Thu: 4,
    Fri: 5,
    Sat: 6
});
const FORMATTERS = new Map();

function assertTimezone(timezone) {
    try {
        new Intl.DateTimeFormat('en-US', { timeZone: timezone }).format(new Date());
    } catch (error) {
        throw new Error('Fuso horário do agendamento inválido.');
    }
}

function normalizeDays(rawDays) {
    const input = Array.isArray(rawDays) ? rawDays : rawDays == null ? [] : [rawDays];
    const days = [...new Set(input.map((value) => Number(value)))].sort((a, b) => a - b);

    if (!days.length || days.some((day) => !Number.isInteger(day) || day < 0 || day > 6)) {
        throw new Error('Selecione pelo menos um dia da semana válido.');
    }

    return days;
}

function daysToCron(days) {
    return days.length === 7 ? '*' : days.join(',');
}

function parseDaysField(field) {
    if (field === '*') return [0, 1, 2, 3, 4, 5, 6];
    if (!/^\d(?:,\d)*$/.test(field)) {
        throw new Error('Dias da semana inválidos na recorrência.');
    }
    return normalizeDays(field.split(','));
}

function parseTime(value) {
    const match = typeof value === 'string' ? value.match(/^(\d{2}):(\d{2})$/) : null;
    if (!match) throw new Error('Informe um horário válido.');

    const hour = Number(match[1]);
    const minute = Number(match[2]);
    if (hour > 23 || minute > 59) throw new Error('Informe um horário válido.');
    return { hour, minute };
}

function buildCronExpression({ days: rawDays, cadence, time, interval }) {
    const days = normalizeDays(rawDays);
    const dayField = daysToCron(days);

    if (cadence === CADENCES.FIXED_TIME) {
        const parsedTime = parseTime(time);
        return `${parsedTime.minute} ${parsedTime.hour} * * ${dayField}`;
    }

    const numericInterval = Number(interval);
    if (cadence === CADENCES.MINUTES) {
        if (!ALLOWED_MINUTE_INTERVALS.includes(numericInterval)) {
            throw new Error('Selecione um intervalo de minutos válido.');
        }
        return `*/${numericInterval} * * * ${dayField}`;
    }

    if (cadence === CADENCES.HOURS) {
        if (!ALLOWED_HOUR_INTERVALS.includes(numericInterval)) {
            throw new Error('Selecione um intervalo de horas válido.');
        }
        return numericInterval === 1
            ? `0 * * * ${dayField}`
            : `0 */${numericInterval} * * ${dayField}`;
    }

    throw new Error('Selecione uma frequência de recorrência válida.');
}

function parseCronExpression(expression) {
    if (typeof expression !== 'string') throw new Error('Expressão de recorrência inválida.');
    const normalized = expression.trim().replace(/\s+/g, ' ');
    const minuteMatch = normalized.match(/^\*\/(\d+) \* \* \* ([*\d,]+)$/);
    if (minuteMatch) {
        const interval = Number(minuteMatch[1]);
        if (!ALLOWED_MINUTE_INTERVALS.includes(interval)) {
            throw new Error('Intervalo de minutos não suportado.');
        }
        return {
            expression: normalized,
            cadence: CADENCES.MINUTES,
            interval,
            days: parseDaysField(minuteMatch[2])
        };
    }

    const hourlyMatch = normalized.match(/^0 (\*|\*\/(\d+)) \* \* ([*\d,]+)$/);
    if (hourlyMatch) {
        const interval = hourlyMatch[1] === '*' ? 1 : Number(hourlyMatch[2]);
        if (!ALLOWED_HOUR_INTERVALS.includes(interval)) {
            throw new Error('Intervalo de horas não suportado.');
        }
        return {
            expression: normalized,
            cadence: CADENCES.HOURS,
            interval,
            days: parseDaysField(hourlyMatch[3])
        };
    }

    const fixedMatch = normalized.match(/^(\d{1,2}) (\d{1,2}) \* \* ([*\d,]+)$/);
    if (fixedMatch) {
        const minute = Number(fixedMatch[1]);
        const hour = Number(fixedMatch[2]);
        if (minute > 59 || hour > 23) throw new Error('Horário da recorrência inválido.');
        const days = parseDaysField(fixedMatch[3]);
        const canonicalExpression = `${minute} ${hour} * * ${daysToCron(days)}`;
        if (canonicalExpression !== normalized) {
            throw new Error('Expressão de recorrência não está normalizada.');
        }
        return {
            expression: normalized,
            cadence: CADENCES.FIXED_TIME,
            time: `${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}`,
            hour,
            minute,
            days
        };
    }

    throw new Error('Expressão de recorrência fora dos formatos suportados.');
}

function getZonedParts(date, timezone) {
    let formatter = FORMATTERS.get(timezone);
    if (!formatter) {
        assertTimezone(timezone);
        formatter = new Intl.DateTimeFormat('en-US', {
            timeZone: timezone,
            weekday: 'short',
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit',
            hourCycle: 'h23'
        });
        FORMATTERS.set(timezone, formatter);
    }
    const parts = Object.fromEntries(
        formatter.formatToParts(date)
            .filter((part) => part.type !== 'literal')
            .map((part) => [part.type, part.value])
    );
    return {
        year: Number(parts.year),
        month: Number(parts.month),
        day: Number(parts.day),
        hour: Number(parts.hour),
        minute: Number(parts.minute),
        second: Number(parts.second),
        weekday: DAY_INDEX_BY_SHORT_NAME[parts.weekday]
    };
}

function matchesRecurrence(parsed, parts) {
    if (!parsed.days.includes(parts.weekday)) return false;
    if (parsed.cadence === CADENCES.FIXED_TIME) {
        return parts.hour === parsed.hour && parts.minute === parsed.minute;
    }
    if (parsed.cadence === CADENCES.MINUTES) {
        return parts.minute % parsed.interval === 0;
    }
    return parts.minute === 0 && parts.hour % parsed.interval === 0;
}

function getNextOccurrences(expression, options = {}) {
    const timezone = options.timezone || SCHEDULE_TIMEZONE;
    const count = Number(options.count || 1);
    const after = options.after instanceof Date ? options.after : new Date(options.after || Date.now());
    if (Number.isNaN(after.getTime()) || !Number.isInteger(count) || count < 1 || count > 10) {
        throw new Error('Parâmetros inválidos para calcular a próxima ocorrência.');
    }

    const parsed = parseCronExpression(expression);
    const occurrences = [];
    let cursor = Math.floor(after.getTime() / 60000) * 60000 + 60000;
    const maxIterations = 8 * 24 * 60 * count;

    for (let i = 0; i < maxIterations && occurrences.length < count; i += 1) {
        const candidate = new Date(cursor);
        if (matchesRecurrence(parsed, getZonedParts(candidate, timezone))) {
            occurrences.push(candidate.toISOString());
        }
        cursor += 60000;
    }

    if (occurrences.length !== count) {
        throw new Error('Não foi possível calcular a próxima ocorrência.');
    }
    return occurrences;
}

function getNextOccurrence(expression, options = {}) {
    return getNextOccurrences(expression, { ...options, count: 1 })[0];
}

function joinWords(words) {
    if (words.length <= 1) return words[0] || '';
    return `${words.slice(0, -1).join(', ')} e ${words[words.length - 1]}`;
}

function describeCronExpression(expression) {
    const parsed = parseCronExpression(expression);
    const days = parsed.days.length === 7
        ? 'Todos os dias'
        : joinWords(parsed.days.map((day) => DAY_NAMES[day]));

    if (parsed.cadence === CADENCES.FIXED_TIME) {
        return `${days}, às ${parsed.time}`;
    }
    if (parsed.cadence === CADENCES.MINUTES) {
        return `${days}, a cada ${parsed.interval} ${parsed.interval === 1 ? 'minuto' : 'minutos'}`;
    }
    return `${days}, a cada ${parsed.interval} ${parsed.interval === 1 ? 'hora' : 'horas'}`;
}

function zonedDateTimeToIso(value, timezone = SCHEDULE_TIMEZONE) {
    const match = typeof value === 'string'
        ? value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/)
        : null;
    if (!match) throw new Error('Data/hora de execução inválida.');

    const desired = {
        year: Number(match[1]),
        month: Number(match[2]),
        day: Number(match[3]),
        hour: Number(match[4]),
        minute: Number(match[5])
    };
    const desiredAsUtc = Date.UTC(desired.year, desired.month - 1, desired.day, desired.hour, desired.minute);
    let timestamp = desiredAsUtc;

    for (let i = 0; i < 3; i += 1) {
        const parts = getZonedParts(new Date(timestamp), timezone);
        const representedAsUtc = Date.UTC(parts.year, parts.month - 1, parts.day, parts.hour, parts.minute);
        timestamp += desiredAsUtc - representedAsUtc;
    }

    const result = new Date(timestamp);
    const resultParts = getZonedParts(result, timezone);
    if (
        resultParts.year !== desired.year
        || resultParts.month !== desired.month
        || resultParts.day !== desired.day
        || resultParts.hour !== desired.hour
        || resultParts.minute !== desired.minute
    ) {
        throw new Error('Data/hora inexistente no fuso do agendamento.');
    }
    return result.toISOString();
}

function isoToDatetimeLocal(value, timezone = SCHEDULE_TIMEZONE) {
    if (!value) return '';
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return '';
    const parts = getZonedParts(date, timezone);
    return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}T${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}`;
}

module.exports = {
    SCHEDULE_TIMEZONE,
    SCHEDULE_TYPES,
    CADENCES,
    ALLOWED_MINUTE_INTERVALS,
    ALLOWED_HOUR_INTERVALS,
    normalizeDays,
    buildCronExpression,
    parseCronExpression,
    getNextOccurrence,
    getNextOccurrences,
    describeCronExpression,
    zonedDateTimeToIso,
    isoToDatetimeLocal
};
