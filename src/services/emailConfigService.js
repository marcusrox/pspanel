const fs = require('fs');
const path = require('path');
const CONFIG_VERSION = 1;
const PROJECT_ROOT = path.join(__dirname, '..', '..');
const CONFIG_PATH = path.join(PROJECT_ROOT, 'database', 'email-settings.json');

function normalize(value) {
    return value == null ? '' : String(value).trim();
}

function isValidEmailAddress(value) {
    return /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(normalize(value));
}

function isValidMailbox(value) {
    const mailbox = normalize(value);
    if (isValidEmailAddress(mailbox)) return true;

    const match = mailbox.match(/^(?:"(?:[^"\\\r\n]|\\.)+"|[^<>"\r\n]+)\s*<([^<>\r\n]+)>$/);
    return Boolean(match && isValidEmailAddress(match[1]));
}

function getSecurityForPort(port) {
    if (port === 587) return 'starttls';
    if (port === 465) return 'tls';
    return '';
}

function normalizeEmailConfig(input, existingConfig = null) {
    const smtp = input && input.smtp ? input.smtp : {};
    const existingSmtp = existingConfig && existingConfig.smtp ? existingConfig.smtp : {};
    const port = Number(smtp.port);
    const suppliedPassword = smtp.password == null ? '' : String(smtp.password);

    return {
        version: CONFIG_VERSION,
        smtp: {
            host: normalize(smtp.host),
            port,
            security: normalize(smtp.security) || getSecurityForPort(port),
            username: normalize(smtp.username),
            password: suppliedPassword === '' ? String(existingSmtp.password || '') : suppliedPassword,
            fromAddress: normalize(smtp.fromAddress)
        }
    };
}

function validateEmailConfig(config) {
    const errors = [];
    const smtp = config && config.smtp ? config.smtp : {};

    if (!config || config.version !== CONFIG_VERSION) errors.push('versão do arquivo');
    if (!normalize(smtp.host)) errors.push('host SMTP');
    if (![587, 465].includes(smtp.port)) errors.push('porta SMTP (use 587 ou 465)');
    if (smtp.security !== getSecurityForPort(smtp.port)) errors.push('modo de segurança SMTP');
    if (!normalize(smtp.username)) errors.push('usuário SMTP');
    if (!String(smtp.password || '')) errors.push('senha SMTP');
    if (!isValidMailbox(smtp.fromAddress)) errors.push('email remetente');
    if ([smtp.host, smtp.username, smtp.password, smtp.fromAddress].some((value) => /[\r\n]/.test(String(value || '')))) {
        errors.push('quebra de linha não permitida');
    }

    return errors;
}

function createConfigError(message, code) {
    const error = new Error(message);
    error.code = code;
    return error;
}

async function loadEmailConfig({ allowMissing = false } = {}) {
    let raw;
    try {
        raw = await fs.promises.readFile(CONFIG_PATH, 'utf8');
    } catch (error) {
        if (allowMissing && error.code === 'ENOENT') return null;
        if (error.code === 'ENOENT') {
            throw createConfigError('Configuração SMTP ainda não foi salva.', 'EMAIL_CONFIG_MISSING');
        }
        throw createConfigError('Não foi possível ler a configuração SMTP.', 'EMAIL_CONFIG_READ_ERROR');
    }

    let parsed;
    try {
        parsed = JSON.parse(raw);
    } catch (error) {
        throw createConfigError('O arquivo de configuração SMTP contém JSON inválido.', 'EMAIL_CONFIG_INVALID_JSON');
    }

    const normalized = normalizeEmailConfig(parsed);
    const errors = validateEmailConfig(normalized);
    if (errors.length) {
        throw createConfigError(`Configuração SMTP inválida: ${errors.join(', ')}.`, 'EMAIL_CONFIG_INVALID');
    }

    return normalized;
}

async function saveEmailConfig(input) {
    let existingConfig = null;
    try {
        existingConfig = await loadEmailConfig({ allowMissing: true });
    } catch (error) {
        const suppliedPassword = input && input.smtp ? String(input.smtp.password || '') : '';
        if (!suppliedPassword) throw error;
    }
    const normalized = normalizeEmailConfig(input, existingConfig);
    const errors = validateEmailConfig(normalized);
    if (errors.length) {
        throw createConfigError(`Configuração SMTP inválida: ${errors.join(', ')}.`, 'EMAIL_CONFIG_INVALID');
    }

    await fs.promises.mkdir(path.dirname(CONFIG_PATH), { recursive: true });
    const temporaryPath = `${CONFIG_PATH}.${process.pid}.${Date.now()}.tmp`;

    try {
        await fs.promises.writeFile(temporaryPath, `${JSON.stringify(normalized, null, 2)}\n`, {
            encoding: 'utf8',
            flag: 'wx'
        });
        await fs.promises.rename(temporaryPath, CONFIG_PATH);
    } catch (error) {
        await fs.promises.rm(temporaryPath, { force: true }).catch(() => {});
        if (error.code && error.code.startsWith('EMAIL_CONFIG_')) throw error;
        throw createConfigError('Não foi possível salvar a configuração SMTP.', 'EMAIL_CONFIG_WRITE_ERROR');
    }

    return normalized;
}

function getPublicEmailConfig(config) {
    const smtp = config && config.smtp ? config.smtp : {};
    return {
        host: normalize(smtp.host),
        port: [587, 465].includes(smtp.port) ? smtp.port : 587,
        security: normalize(smtp.security) || 'starttls',
        username: normalize(smtp.username),
        fromAddress: normalize(smtp.fromAddress),
        passwordConfigured: Boolean(smtp.password)
    };
}

module.exports = {
    CONFIG_PATH,
    getPublicEmailConfig,
    getSecurityForPort,
    loadEmailConfig,
    saveEmailConfig,
    validateEmailConfig
};
