const History = require('../models/History');
const Settings = require('../models/Settings');
const { loadEmailConfig } = require('./emailConfigService');
const {
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

function formatReportDatePtBr(reportDate) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(reportDate);
    return match ? `${match[3]}/${match[2]}/${match[1]}` : reportDate;
}

function formatLocalDateTime(date) {
    return date.toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit',
        hour12: false
    });
}

function getStatusText(status) {
    const statusLabels = {
        success: 'Sucesso',
        error: 'Erro',
        running: 'Em execução'
    };
    return statusLabels[status] || status || '-';
}

function buildDailySummaryMessage(reportDate, runs) {
    const generatedAt = new Date();
    const reportDateText = formatReportDatePtBr(reportDate);
    const generatedAtText = formatLocalDateTime(generatedAt);
    const routineName = 'Resumo diário de agendamentos';
    const subject = `[PS Panel] Resumo diário de agendamentos - ${reportDateText}`;
    const total = runs.length;
    const textFooter = [
        '---',
        `Enviado em: ${generatedAtText}`,
        'Sistema: PS Panel',
        `Rotina: ${routineName}`
    ].join('\n');
    const htmlFooter = `
        <div style="margin-top:24px;padding-top:12px;border-top:1px solid #e2e8f0;color:#718096;font-size:12px;line-height:1.5;">
            Enviado em: <strong>${escapeHtml(generatedAtText)}</strong><br>
            Sistema: <strong>PS Panel</strong><br>
            Rotina: <strong>${escapeHtml(routineName)}</strong>
        </div>
    `;

    if (!total) {
        const text = `${routineName} - ${reportDateText}\n\nNenhum agendamento foi executado em ${reportDateText}.\n\n${textFooter}`;
        const html = `
            <!DOCTYPE html>
            <html>
                <head><meta charset="utf-8"></head>
                <body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">
                    <h1 style="color:#1a365d;font-size:22px;">${routineName}</h1>
                    <p>Data do resumo: <strong>${escapeHtml(reportDateText)}</strong><br>Total de execuções: <strong>0</strong></p>
                    <p style="padding:12px;background:#f7fafc;border:1px solid #e2e8f0;">Nenhum agendamento foi executado nesta data.</p>
                    ${htmlFooter}
                </body>
            </html>
        `;
        return { subject, text, html };
    }

    const textRows = runs.map((run, index) => [
        `${index + 1}. ${run.script_name}`,
        `Início: ${formatDateTimePtBr(run.start_time, '-')}`,
        `Fim: ${formatDateTimePtBr(run.end_time, '-')}`,
        `Duração: ${getDurationText(run)}`,
        `Status: ${getStatusText(run.status)}`,
        `Resultado: ${summarizeOutput(run)}`
    ].join('\n')).join('\n\n');

    const htmlRows = runs.map((run) => `
        <tr>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;">${escapeHtml(run.script_name)}</td>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;white-space:nowrap;">${escapeHtml(formatDateTimePtBr(run.start_time, '-'))}</td>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;white-space:nowrap;">${escapeHtml(formatDateTimePtBr(run.end_time, '-'))}</td>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;white-space:nowrap;">${escapeHtml(getDurationText(run))}</td>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;white-space:nowrap;">${escapeHtml(getStatusText(run.status))}</td>
            <td style="padding:4px 6px;border:1px solid #e2e8f0;vertical-align:top;word-break:break-word;">${escapeHtml(summarizeOutput(run))}</td>
        </tr>
    `).join('');

    return {
        subject,
        text: `${routineName} - ${reportDateText}\nTotal de execuções: ${total}\n\n${textRows}\n\n${textFooter}`,
        html: `
            <!DOCTYPE html>
            <html>
                <head><meta charset="utf-8"></head>
                <body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">
                    <h1 style="color:#1a365d;font-size:22px;">${routineName}</h1>
                    <p>Data do resumo: <strong>${escapeHtml(reportDateText)}</strong><br>Total de execuções: <strong>${total}</strong></p>
                    <table style="border-collapse:collapse;width:100%;max-width:1050px;border:1px solid #ccc;font-size:12px;line-height:1.2;">
                        <thead>
                            <tr style="background:#1a365d;color:#fff;text-align:left;">
                                <th style="padding:5px 6px;border:1px solid #2c5282;">Script</th>
                                <th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">Início</th>
                                <th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">Fim</th>
                                <th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">Duração</th>
                                <th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">Status</th>
                                <th style="padding:5px 6px;border:1px solid #2c5282;">Resultado</th>
                            </tr>
                        </thead>
                        <tbody>${htmlRows}</tbody>
                    </table>
                    ${htmlFooter}
                </body>
            </html>
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
    const emailSettings = settings.email || {};
    const emailConfig = await loadEmailConfig({ allowMissing: true });
    const smtpConfig = emailConfig ? emailConfig.smtp : null;
    const recipient = emailSettings.daily_summary_recipient || '';
    const reportDate = getYesterdayLocalDateString();

    if (requireEnabled && emailSettings.daily_summary_enabled !== '1') {
        return { sent: false, skipped: true, reason: 'disabled', reportDate };
    }

    if (!force && settings.email && settings.email.daily_summary_last_sent_date === reportDate) {
        return { sent: false, skipped: true, reason: 'already_sent', reportDate };
    }

    const missingConfig = getMissingEmailConfig(smtpConfig || {}, recipient);
    if (missingConfig.length) {
        return { sent: false, skipped: true, reason: 'missing_config', missingConfig, reportDate };
    }

    const runs = await History.findScheduledRunsByDate(reportDate);
    const message = buildDailySummaryMessage(reportDate, runs);
    await sendMail(smtpConfig, { ...message, to: recipient });

    const sentAt = new Date().toISOString();
    await Settings.set('email.daily_summary_last_sent_date', reportDate);
    await Settings.set('email.daily_summary_last_sent_at', sentAt);

    return {
        sent: true,
        reportDate,
        recipient,
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
