const nodemailer = require('nodemailer');

function normalize(value) {
    return value == null ? '' : String(value).trim();
}

function isEnabled(value) {
    return value === true || value === '1' || value === 'true' || value === 'on';
}

function isValidEmail(value) {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(normalize(value));
}

function buildEmailConfig(settings) {
    const email = settings && settings.email ? settings.email : {};
    const port = Number(email.smtp_port || 587);

    return {
        enabled: isEnabled(email.daily_summary_enabled),
        host: normalize(email.smtp_host),
        port,
        secure: isEnabled(email.smtp_secure),
        user: normalize(email.smtp_user),
        pass: email.smtp_pass || '',
        from: normalize(email.from_address),
        recipient: normalize(email.daily_summary_recipient)
    };
}

function getMissingEmailConfig(config) {
    const missing = [];
    if (!config.host) missing.push('host SMTP');
    if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) missing.push('porta SMTP');
    if (!config.from || !isValidEmail(config.from)) missing.push('email remetente');
    if (!config.recipient || !isValidEmail(config.recipient)) missing.push('email destinatário');
    return missing;
}

async function sendMail(config, message) {
    const transporter = nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.secure,
        auth: config.user || config.pass ? {
            user: config.user,
            pass: config.pass
        } : undefined
    });

    return transporter.sendMail({
        from: config.from,
        to: config.recipient,
        subject: message.subject,
        text: message.text,
        html: message.html
    });
}

module.exports = {
    buildEmailConfig,
    getMissingEmailConfig,
    sendMail
};
