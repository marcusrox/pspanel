const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const ejs = require('ejs');

const projectRoot = path.join(__dirname, '..');

function buildFormLocals(overrides = {}) {
    return {
        mode: 'new',
        schedule: null,
        scripts: [{ name: 'Example.ps1', parameters: { parameters: [] } }],
        parameterValues: {},
        additionalParameters: '',
        next_run_local: '2026-07-17T08:00',
        recurrenceForm: {
            days: ['0', '1', '2', '3', '4', '5', '6'],
            cadence: 'fixed_time',
            time: '08:00',
            interval: '1'
        },
        recurrenceOptions: {
            timezone: 'America/Sao_Paulo',
            minuteIntervals: [1, 5],
            hourIntervals: [1, 2]
        },
        messages: { error: [], success: [], info: [] },
        user: { username: 'test', displayName: 'Test', email: '' },
        release: { label: 'Test' },
        ui: { fontScale: '100' },
        ...overrides
    };
}

for (const relativePath of ['views/schedule-form.ejs', 'views/schedules.ejs']) {
    test(`compila ${relativePath}`, () => {
        const filename = path.join(projectRoot, relativePath);
        const template = fs.readFileSync(filename, 'utf8');
        assert.doesNotThrow(() => ejs.compile(template, { filename }));
    });
}

test('renderiza formulário e valida a sintaxe do JavaScript inline', async () => {
    const filename = path.join(projectRoot, 'views/schedule-form.ejs');
    const html = await ejs.renderFile(filename, buildFormLocals());
    const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((match) => match[1]);
    assert.equal(scripts.length, 1);
    assert.doesNotThrow(() => new Function(scripts[0]));
    assert.equal((html.match(/<h1/g) || []).length, 1);
    assert.ok(html.includes('class="schedule-layout"'));
    assert.ok(html.indexOf('class="form-card script-card"') < html.indexOf('class="form-card timing-card"'));
    assert.equal(html.includes('repeat_interval_minutes'), false);
});

test('renderiza edição recorrente preservando a composição e os valores', async () => {
    const filename = path.join(projectRoot, 'views/schedule-form.ejs');
    const schedule = {
        id: 7,
        script_name: 'Example.ps1',
        schedule_type: 'cron',
        enabled: 1
    };
    const html = await ejs.renderFile(filename, buildFormLocals({
        mode: 'edit',
        schedule,
        recurrenceForm: {
            days: ['1'],
            cadence: 'minutes',
            time: '08:00',
            interval: '5'
        }
    }));

    assert.ok(html.includes('action="/schedules/7"'));
    assert.match(html, /name="schedule_type" value="cron" checked/);
    assert.match(html, /name="recurrence_days" value="1" checked/);
    assert.match(html, /value="minutes" selected/);
    assert.match(html, /value="5" selected>5 min/);
});

test('identifica próxima execução como retentativa sem ocultar a recorrência', async () => {
    const filename = path.join(projectRoot, 'views/schedules.ejs');
    const html = await ejs.renderFile(filename, {
        schedules: [{
            id: 7,
            script_name: 'Example.ps1',
            parameters: '',
            enabled: 1,
            next_run_at: '2026-08-17T13:10:00.000Z',
            schedule_type: 'cron',
            cron_expression: '0 8 * * *',
            schedule_timezone: 'America/Sao_Paulo',
            recurrence_description: 'Todos os dias às 08:00',
            retry_attempt_count: 2,
            retry_max_attempts: 3,
            last_run_at: '2026-08-17T13:00:00.000Z',
            last_run_exit_code: 1,
            last_run_output: 'Falha controlada'
        }],
        messages: { error: [], success: [], info: [] },
        user: { username: 'test', displayName: 'Test', email: '' },
        release: { label: 'Test' },
        ui: { fontScale: '100' }
    });

    assert.match(html, /Retentativa\s+2\s+de\s+3/);
    assert.ok(html.includes('Todos os dias às 08:00'));
    assert.ok(html.includes('schedule-status-icon-active'));
});
