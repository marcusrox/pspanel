const test = require('node:test');
const assert = require('node:assert/strict');
const {
    createRequest,
    createResponse,
    freshRequire,
    installModuleMock,
    patchObject,
    projectPath
} = require('../test-support/testUtils');

const RETRY_SETTINGS = {
    INTERVAL_MINUTES: 'schedules.retry_interval_minutes',
    MAX_ATTEMPTS: 'schedules.max_retry_attempts'
};

function loadSettingsController(t, settings) {
    const restores = [
        installModuleMock(projectPath('src', 'models', 'Settings.js'), settings),
        installModuleMock(projectPath('src', 'services', 'emailConfigService.js'), {
            getPublicEmailConfig: () => ({ configured: false }),
            loadEmailConfig: async () => null,
            saveEmailConfig: async () => {}
        }),
        installModuleMock(projectPath('src', 'services', 'dailySummaryEmailService.js'), {
            getDailySummaryStatus: () => ({ enabled: false }),
            sendDailySummaryNow: async () => ({ sent: false, reason: 'missing_config', missingConfig: [] })
        }),
        installModuleMock(projectPath('src', 'services', 'adAccessService.js'), {
            validateAllowedAdGroupDn: (value) => String(value || '').trim()
        }),
        installModuleMock(projectPath('src', 'services', 'scheduleRetryPolicy.js'), {
            RETRY_SETTINGS,
            validateRetrySetting: (key, value) => {
                const number = Number(value);
                if (!Number.isInteger(number) || number < 0) throw new Error(`Valor inválido para ${key}`);
                return String(number);
            }
        })
    ];
    t.after(() => {
        delete require.cache[require.resolve('../src/controllers/settingsController')];
        restores.reverse().forEach((restore) => restore());
    });
    return freshRequire(projectPath('src', 'controllers', 'settingsController.js'));
}

test('configuracoes carregam dados simulados para a tela', async (t) => {
    const values = { ui: { font_scale: '100' }, scripts: { max_execution_time: '3600' } };
    const controller = loadSettingsController(t, { getAll: async () => values });
    const response = createResponse();

    await controller.showSettings(createRequest(), response);

    assert.equal(response.view, 'settings');
    assert.deepEqual(response.body.settings, values);
    assert.deepEqual(response.body.smtpConfig, { configured: false });
});

test('configuracoes persistem somente allowlist com valores normalizados', async (t) => {
    const saved = [];
    const controller = loadSettingsController(t, {
        set: async (key, value) => { saved.push([key, value]); }
    });
    const request = createRequest({
        body: {
            'scripts.max_execution_time': '120',
            'schedules.retry_interval_minutes': '10',
            'schedules.max_retry_attempts': '2',
            'ui.font_scale': '110',
            'auth.allowed_ad_group_dn': '',
            'settings.chave_arbitraria': 'nao salvar'
        }
    });
    const response = createResponse();

    await controller.updateSettings(request, response);

    assert.equal(response.redirectedTo, '/settings');
    assert.deepEqual(saved, [
        ['scripts.max_execution_time', '120'],
        ['schedules.retry_interval_minutes', '10'],
        ['schedules.max_retry_attempts', '2'],
        ['ui.font_scale', '110'],
        ['auth.allowed_ad_group_dn', ''],
        ['email.daily_summary_enabled', '0']
    ]);
    assert.equal(saved.some(([key]) => key === 'settings.chave_arbitraria'), false);
    assert.deepEqual(request.flashes.at(-1), {
        type: 'success',
        message: 'Configurações atualizadas com sucesso'
    });
});

test('configuracoes invalidas nao causam persistencia parcial', async (t) => {
    const saved = [];
    const restoreConsole = patchObject(console, { error: () => {} });
    t.after(restoreConsole);
    const controller = loadSettingsController(t, {
        set: async (...args) => { saved.push(args); }
    });
    const request = createRequest({
        body: {
            'scripts.max_execution_time': '120',
            'ui.font_scale': '999'
        }
    });
    const response = createResponse();

    await controller.updateSettings(request, response);

    assert.equal(response.redirectedTo, '/settings');
    assert.deepEqual(saved, []);
    assert.deepEqual(request.flashes.at(-1), {
        type: 'error',
        message: 'Tamanho da fonte inválido'
    });
});
