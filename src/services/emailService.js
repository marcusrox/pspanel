const nodemailer = require('nodemailer');

function normalize(value) {
    return value == null ? '' : String(value).trim();
}

function isValidEmail(value) {
    return /^[^\s@<>"]+@[^\s@<>"]+\.[^\s@<>"]+$/.test(normalize(value));
}

function isValidMailbox(value) {
    const mailbox = normalize(value);
    if (isValidEmail(mailbox)) return true;

    const match = mailbox.match(/^(?:"(?:[^"\\\r\n]|\\.)+"|[^<>"\r\n]+)\s*<([^<>\r\n]+)>$/);
    return Boolean(match && isValidEmail(match[1]));
}

function getMissingEmailConfig(config, recipient) {
    const missing = [];
    if (!config.host) missing.push('host SMTP');
    if (![587, 465].includes(config.port)) missing.push('porta SMTP');
    if (!config.username) missing.push('usuário SMTP');
    if (!config.password) missing.push('senha SMTP');
    if (!config.fromAddress || !isValidMailbox(config.fromAddress)) missing.push('email remetente');
    if (!recipient || !isValidEmail(recipient)) missing.push('email destinatário');
    return missing;
}

async function sendMail(config, message) {
    const transporter = nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.port === 465,
        requireTLS: config.port === 587,
        auth: {
            user: config.username,
            pass: config.password
        },
        connectionTimeout: 30000,
        greetingTimeout: 30000,
        socketTimeout: 60000,
        tls: {
            minVersion: 'TLSv1.2'
        }
    });

    return transporter.sendMail({
        from: config.fromAddress,
        to: message.to,
        subject: message.subject,
        text: message.text,
        html: message.html
    });
}

module.exports = {
    getMissingEmailConfig,
    sendMail
};
