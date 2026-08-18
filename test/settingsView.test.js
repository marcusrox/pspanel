const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const ejs = require('ejs');

const projectRoot = path.join(__dirname, '..');

test('compila e renderiza configurações de retentativa com limites', async () => {
    const filename = path.join(projectRoot, 'views/settings.ejs');
    const template = fs.readFileSync(filename, 'utf8');
    assert.doesNotThrow(() => ejs.compile(template, { filename }));

    const html = await ejs.renderFile(filename, {
        settings: {
            scripts: { max_execution_time: '3600' },
            schedules: { retry_interval_minutes: '15', max_retry_attempts: '4' },
            ui: { font_scale: '100' },
            auth: { allowed_ad_group_dn: '' },
            email: { daily_summary_enabled: '0', daily_summary_recipient: '' }
        },
        smtpConfig: null,
        dailySummaryStatus: { displayText: 'Nunca enviado' },
        messages: { error: [], success: [], info: [] },
        user: { username: 'test', displayName: 'Test', email: '' },
        release: { label: 'Test' },
        ui: { fontScale: '100' }
    });

    assert.match(html, /name="schedules\.retry_interval_minutes"[\s\S]*value="15"[\s\S]*min="1"[\s\S]*max="1440"/);
    assert.match(html, /name="schedules\.max_retry_attempts"[\s\S]*value="4"[\s\S]*min="0"[\s\S]*max="20"/);
    assert.ok(html.includes('scheduleRetries: false'));
});
