const Settings = require('../models/Settings');
const {
    getDailySummaryStatus,
    sendDailySummaryNow
} = require('../services/dailySummaryEmailService');

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

    normalized['email.smtp_secure'] = getBodyValue(body, 'email.smtp_secure') ? '1' : '0';
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
            res.render('settings', {
                settings,
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
                'email.smtp_host',
                'email.smtp_port',
                'email.smtp_user',
                'email.smtp_pass',
                'email.smtp_secure',
                'email.from_address',
                'email.daily_summary_recipient',
                'email.daily_summary_enabled'
            ];
            const updates = normalizeSettingsBody(req.body, allowedSettings);

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

            if (updates['email.smtp_port']) {
                const smtpPort = parseInt(updates['email.smtp_port'], 10);
                if (isNaN(smtpPort) || smtpPort < 1 || smtpPort > 65535) {
                    throw new Error('Porta SMTP inválida');
                }
                updates['email.smtp_port'] = String(smtpPort);
            }

            if (updates['email.smtp_secure'] === '1' && updates['email.smtp_port'] === '587') {
                throw new Error('Para a porta 587, deixe SSL/TLS direto desmarcado. O STARTTLS será negociado automaticamente quando suportado pelo servidor.');
            }

            if (!isValidEmail(updates['email.from_address'])) {
                throw new Error('Email remetente inválido');
            }

            if (!isValidEmail(updates['email.daily_summary_recipient'])) {
                throw new Error('Email destinatário do resumo inválido');
            }

            if (updates['email.smtp_pass'] === '') {
                delete updates['email.smtp_pass'];
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
