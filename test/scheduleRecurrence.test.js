const test = require('node:test');
const assert = require('node:assert/strict');
const {
    buildCronExpression,
    parseCronExpression,
    getNextOccurrence,
    getNextOccurrences,
    describeCronExpression,
    zonedDateTimeToIso,
    isoToDatetimeLocal
} = require('../src/services/scheduleRecurrence');

test('gera e decompõe os três exemplos obrigatórios', () => {
    const examples = [
        [{ days: [1, 5], cadence: 'fixed_time', time: '08:00' }, '0 8 * * 1,5'],
        [{ days: [0, 1, 2, 3, 4, 5, 6], cadence: 'hours', interval: 1 }, '0 * * * *'],
        [{ days: [1], cadence: 'minutes', interval: 5 }, '*/5 * * * 1']
    ];

    examples.forEach(([form, expected]) => {
        const expression = buildCronExpression(form);
        assert.equal(expression, expected);
        assert.deepEqual(parseCronExpression(expression).days, [...new Set(form.days)].sort());
    });
});

test('normaliza dias, descreve a recorrência e rejeita entradas inválidas', () => {
    assert.equal(
        buildCronExpression({ days: ['5', '1', '5'], cadence: 'fixed_time', time: '08:00' }),
        '0 8 * * 1,5'
    );
    assert.equal(describeCronExpression('*/5 * * * 1'), 'segunda-feira, a cada 5 minutos');
    assert.throws(() => buildCronExpression({ days: [], cadence: 'minutes', interval: 5 }), /dia da semana/);
    assert.throws(() => buildCronExpression({ days: [1], cadence: 'minutes', interval: 45 }), /minutos válido/);
    assert.throws(() => parseCronExpression('0 0 8 * * 1'), /formatos suportados/);
    assert.throws(() => parseCronExpression('@daily'), /formatos suportados/);
});

test('calcula próximas ocorrências estritamente futuras no fuso do agendamento', () => {
    assert.equal(
        getNextOccurrence('0 8 * * 1,5', { after: new Date('2026-07-17T12:00:00Z') }),
        '2026-07-20T11:00:00.000Z'
    );
    assert.equal(
        getNextOccurrence('0 * * * *', { after: new Date('2026-07-17T13:15:00Z') }),
        '2026-07-17T14:00:00.000Z'
    );
    assert.deepEqual(
        getNextOccurrences('*/5 * * * 1', {
            after: new Date('2026-07-20T13:01:00Z'),
            count: 3
        }),
        [
            '2026-07-20T13:05:00.000Z',
            '2026-07-20T13:10:00.000Z',
            '2026-07-20T13:15:00.000Z'
        ]
    );
});

test('converte datetime-local sem depender do fuso do processo', () => {
    assert.equal(zonedDateTimeToIso('2026-07-17T08:00'), '2026-07-17T11:00:00.000Z');
    assert.equal(isoToDatetimeLocal('2026-07-17T11:00:00.000Z'), '2026-07-17T08:00');
});

test('ignora horário local inexistente durante transição de DST', () => {
    assert.equal(
        getNextOccurrence('30 2 * * 0', {
            after: new Date('2026-03-08T05:00:00Z'),
            timezone: 'America/New_York'
        }),
        '2026-03-15T06:30:00.000Z'
    );
});
