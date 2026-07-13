const History = require('../models/History');
const Settings = require('../models/Settings');
const {
    buildEmailConfig,
    getMissingEmailConfig,
    sendMail
} = require('./emailService');
const {
    formatDateTimePtBr,
    parseDateTime
} = require('./dateTimeFormatter');

const OUTPUT_SUMMARY_MAX = 1200;

function padDatePart(value) {
    return String(value).padStart(2, '0');
}

function getYesterdayLocalDateString() {
    const date = new Date();
    date.setHours(12, 0, 0, 0);
    date.setDate(date.getDate() - 1);
    return `${date.getFullYear()}-${padDatePart(date.getMonth() + 1)}-${padDatePart(date.getDate())}`;
}

function getDurationText(run) {
    if (!run.start_time || !run.end_time) return '-';
    const start = parseDateTime(run.start_time);
    const end = parseDateTime(run.end_time);
    if (!start || !end) return '-';
    const seconds = Math.max(0, Math.round((end.getTime() - start.getTime()) / 1000));
    if (seconds < 60) return `${seconds}s`;
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes}min ${remainingSeconds}s`;
}

function summarizeOutput(run) {
    const text = run.error_message || run.output || '';
    if (!text.trim()) return '-';
    const singleLine = text.replace(/\r/g, '').split('\n').map((line) => line.trim()).filter(Boolean).join(' | ');
    return singleLine.length > OUTPUT_SUMMARY_MAX
        ? `${singleLine.slice(0, OUTPUT_SUMMARY_MAX)}...`
        : singleLine;
}

function escapeHtml(value) {
    return String(value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function buildDailySummaryMessage(reportDate, runs) {
    const subject = `PS Panel - Resumo de agendamentos - ${reportDate}`;
    const total = runs.length;

    if (!total) {
        const text = `Resumo diario de agendamentos - ${reportDate}\n\nNenhum agendamento executado em ${reportDate}.`;
        const html = `<p>Resumo diario de agendamentos - ${escapeHtml(reportDate)}</p><p>Nenhum agendamento executado em ${escapeHtml(reportDate)}.</p>`;
        return { subject, text, html };
    }

    const textRows = runs.map((run, index) => [
        `${index + 1}. ${run.script_name}`,
        `Inicio: ${formatDateTimePtBr(run.start_time, '-')}`,
        `Fim: ${formatDateTimePtBr(run.end_time, '-')}`,
        `Duracao: ${getDurationText(run)}`,
        `Status: ${run.status}`,
        `Resultado: ${summarizeOutput(run)}`
    ].join('\n')).join('\n\n');

    const htmlRows = runs.map((run) => `
        <tr>
            <td>${escapeHtml(run.script_name)}</td>
            <td>${escapeHtml(formatDateTimePtBr(run.start_time, '-'))}</td>
            <td>${escapeHtml(formatDateTimePtBr(run.end_time, '-'))}</td>
            <td>${escapeHtml(getDurationText(run))}</td>
            <td>${escapeHtml(run.status)}</td>
            <td>${escapeHtml(summarizeOutput(run))}</td>
        </tr>
    `).join('');

    return {
        subject,
        text: `Resumo diario de agendamentos - ${reportDate}\nTotal de execucoes: ${total}\n\n${textRows}`,
        html: `
            <h2>Resumo diario de agendamentos - ${escapeHtml(reportDate)}</h2>
            <p>Total de execucoes: ${total}</p>
            <table border="1" cellpadding="6" cellspacing="0">
                <thead>
                    <tr>
                        <th>Script</th>
                        <th>Inicio</th>
                        <th>Fim</th>
                        <th>Duracao</th>
                        <th>Status</th>
                        <th>Resultado</th>
                    </tr>
                </thead>
                <tbody>${htmlRows}</tbody>
            </table>
        `
    };
}

function getDailySummaryStatus(settings) {
    const email = settings && settings.email ? settings.email : {};
    const lastSentAt = email.daily_summary_last_sent_at || '';
    const lastSentDate = email.daily_summary_last_sent_date || '';

    if (lastSentAt) {
        return {
            lastSentAt,
            lastSentDate,
            displayText: formatDateTimePtBr(lastSentAt, '-')
        };
    }

    return {
        lastSentAt,
        lastSentDate,
        displayText: lastSentDate || 'Nunca enviado'
    };
}

async function sendDailySummary({ force = false, requireEnabled = false } = {}) {
    const settings = await Settings.getAll();
    const config = buildEmailConfig(settings);
    const reportDate = getYesterdayLocalDateString();

    if (requireEnabled && !config.enabled) {
        return { sent: false, skipped: true, reason: 'disabled', reportDate };
    }

    if (!force && settings.email && settings.email.daily_summary_last_sent_date === reportDate) {
        return { sent: false, skipped: true, reason: 'already_sent', reportDate };
    }

    const missingConfig = getMissingEmailConfig(config);
    if (missingConfig.length) {
        return { sent: false, skipped: true, reason: 'missing_config', missingConfig, reportDate };
    }

    const runs = await History.findScheduledRunsByDate(reportDate);
    const message = buildDailySummaryMessage(reportDate, runs);
    await sendMail(config, message);

    const sentAt = new Date().toISOString();
    await Settings.set('email.daily_summary_last_sent_date', reportDate);
    await Settings.set('email.daily_summary_last_sent_at', sentAt);

    return {
        sent: true,
        reportDate,
        recipient: config.recipient,
        runsCount: runs.length,
        sentAt
    };
}

async function sendPendingDailySummary() {
    return sendDailySummary({ force: false, requireEnabled: true });
}

async function sendDailySummaryNow() {
    return sendDailySummary({ force: true, requireEnabled: false });
}

module.exports = {
    getDailySummaryStatus,
    sendDailySummaryNow,
    sendPendingDailySummary
};
