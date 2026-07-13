function normalizeDateTimeValue(value) {
    if (!value) return '';

    const text = String(value).trim();
    if (!text) return '';

    if (/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(text)) {
        return `${text.replace(' ', 'T')}Z`;
    }

    return text;
}

function parseDateTime(value) {
    const normalized = normalizeDateTimeValue(value);
    if (!normalized) return null;

    const date = new Date(normalized);
    return Number.isNaN(date.getTime()) ? null : date;
}

function formatDateTimePtBr(value, fallback = '—') {
    const date = parseDateTime(value);
    if (!date) return value ? String(value) : fallback;

    return date.toLocaleString('pt-BR');
}

module.exports = {
    formatDateTimePtBr,
    normalizeDateTimeValue,
    parseDateTime
};
