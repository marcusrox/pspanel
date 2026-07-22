const Settings = require('../models/Settings');
const {
    getPublicEmailConfig,
    loadEmailConfig,
    saveEmailConfig
} = require('../services/emailConfigService');
const {
    getDailySummaryStatus,
    sendDailySummaryNow
} = require('../services/dailySummaryEmailService');
const { validateAllowedAdGroupDn } = require('../services/adAccessService');

function isValidEmail(value) {
    if (!value) return true;
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

function getBodyValue(body, dottedKey) {
    if (Object.prototype.hasOwnProperty.call(body, dottedKey)) {
        return body[dottedKey];
    }

    const [category, name] = dottedKey.split('.');
    if (body[category] && Object.prototype.hasOwnProperty.call(body[category], name)) {
        return body[category][name];
    }

    return undefined;
}

function normalizeSettingsBody(body, allowedSettings) {
    const normalized = {};

    for (const key of allowedSettings) {
        const value = getBodyValue(body, key);
        if (value !== undefined) {
            normalized[key] = value;
        }
    }

    normalized['email.daily_summary_enabled'] = getBodyValue(body, 'email.daily_summary_enabled') ? '1' : '0';

    return normalized;
}

function isWrongTlsVersionError(error) {
    const message = String(error && (error.message || error));
    return message.includes('wrong version number') || message.includes('tls_validate_record_header');
}

class SettingsController {
    static async showSettings(req, res) {
        try {
            const settings = await Settings.getAll();
            let smtpConfig = null;
            try {
                smtpConfig = await loadEmailConfig({ allowMissing: true });
            } catch (emailConfigError) {
                console.error('Erro ao carregar configuração SMTP:', emailConfigError.message || emailConfigError);
            }
            res.render('settings', {
                settings,
                smtpConfig: getPublicEmailConfig(smtpConfig),
                dailySummaryStatus: getDailySummaryStatus(settings),
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            console.error('Erro ao carregar configurações:', error);
            req.flash('error', 'Erro ao carregar configurações');
            res.redirect('/');
        }
    }

    static async updateSettings(req, res) {
        try {
            const allowedSettings = [
                'scripts.max_execution_time',
                'ui.font_scale',
                'auth.allowed_ad_group_dn',
                'email.daily_summary_recipient',
                'email.daily_summary_enabled'
            ];
            const updates = normalizeSettingsBody(req.body, allowedSettings);

            if (updates['auth.allowed_ad_group_dn'] !== undefined) {
                updates['auth.allowed_ad_group_dn'] = validateAllowedAdGroupDn(
                    updates['auth.allowed_ad_group_dn']
                );
            }

            // Validar tempo máximo de execução
            if (updates['scripts.max_execution_time']) {
                const maxTime = parseInt(updates['scripts.max_execution_time']);
                if (isNaN(maxTime) || maxTime < 1) {
                    throw new Error('Tempo máximo de execução deve ser maior que 0');
                }
            }

            if (updates['ui.font_scale']) {
                const allowedFontScales = ['85', '90', '100', '110'];
                if (!allowedFontScales.includes(updates['ui.font_scale'])) {
                    throw new Error('Tamanho da fonte inválido');
                }
            }

            if (!isValidEmail(updates['email.daily_summary_recipient'])) {
                throw new Error('Email destinatário do resumo inválido');
            }

            const smtpPort = parseInt(getBodyValue(req.body, 'smtp.port'), 10);
            const smtpInput = {
                host: getBodyValue(req.body, 'smtp.host'),
                port: smtpPort,
                security: smtpPort === 465 ? 'tls' : 'starttls',
                username: getBodyValue(req.body, 'smtp.username'),
                password: getBodyValue(req.body, 'smtp.password'),
                fromAddress: getBodyValue(req.body, 'smtp.fromAddress')
            };
            const currentSmtpConfig = await loadEmailConfig({ allowMissing: true }).catch(() => null);
            const hasSmtpInput = [
                smtpInput.host,
                smtpInput.username,
                smtpInput.password,
                smtpInput.fromAddress
            ].some((value) => String(value || '').trim());

            if (hasSmtpInput || currentSmtpConfig) {
                await saveEmailConfig({ version: 1, smtp: smtpInput });
            }

            // Atualizar cada configuração
            for (const [key, value] of Object.entries(updates)) {
                await Settings.set(key, value);
            }
            
            req.flash('success', 'Configurações atualizadas com sucesso');
            res.redirect('/settings');
        } catch (error) {
            console.error('Erro ao atualizar configurações:', error);
            req.flash('error', error.message || 'Erro ao atualizar configurações');
            res.redirect('/settings');
        }
    }

    static async sendDailySummaryNow(req, res) {
        try {
            const result = await sendDailySummaryNow();

            if (!result.sent && result.reason === 'missing_config') {
                req.flash('error', `Resumo diário não enviado: configuração incompleta (${result.missingConfig.join(', ')}).`);
                return res.redirect('/settings');
            }

            req.flash(
                'success',
                `Resumo diário de ${result.reportDate} enviado para ${result.recipient}. Total de execuções: ${result.runsCount}.`
            );
            return res.redirect('/settings');
        } catch (error) {
            console.error('Erro ao enviar resumo diário manual:', error.message || error);
            if (isWrongTlsVersionError(error)) {
                req.flash('error', 'Erro de TLS no SMTP. Se estiver usando a porta 587, desmarque SSL/TLS direto; use SSL/TLS direto apenas para porta 465.');
            } else {
                req.flash('error', 'Erro ao enviar resumo diário. Verifique as configurações SMTP.');
            }
            return res.redirect('/settings');
        }
    }
}

module.exports = SettingsController; 
