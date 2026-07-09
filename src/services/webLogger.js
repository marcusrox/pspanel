const fs = require('fs');
const path = require('path');
const util = require('util');

const SENSITIVE_NAME_PATTERN = /(password|senha|token|secret|key)/i;
const SENSITIVE_ARG_PATTERN = /((?:--?|\/)?(?:password|senha|token|secret|key)[\w-]*\s+)(?:"[^"]*"|'[^']*'|\S+)/gi;
const SENSITIVE_ASSIGNMENT_PATTERN = /((?:password|senha|token|secret|key)[\w-]*\s*[=:]\s*)(?:"[^"]*"|'[^']*'|[^\s,;]+)/gi;

let installed = false;

function getLogFileName(date = new Date()) {
    const day = date.toISOString().slice(0, 10);
    return `web-${day}.log`;
}

function redactString(value) {
    return String(value)
        .replace(SENSITIVE_ARG_PATTERN, '$1[REDACTED]')
        .replace(SENSITIVE_ASSIGNMENT_PATTERN, '$1[REDACTED]');
}

function sanitizeValue(value, seen = new WeakSet()) {
    if (value instanceof Error) {
        return redactString(value.stack || value.message);
    }

    if (typeof value === 'string') {
        return redactString(value);
    }

    if (!value || typeof value !== 'object') {
        return value;
    }

    if (seen.has(value)) {
        return '[Circular]';
    }
    seen.add(value);

    if (Array.isArray(value)) {
        return value.map((item) => sanitizeValue(item, seen));
    }

    const sanitized = {};
    for (const [key, item] of Object.entries(value)) {
        sanitized[key] = SENSITIVE_NAME_PATTERN.test(key)
            ? '[REDACTED]'
            : sanitizeValue(item, seen);
    }
    return sanitized;
}

function formatArg(arg) {
    const sanitized = sanitizeValue(arg);
    if (typeof sanitized === 'string') {
        return sanitized;
    }
    return util.inspect(sanitized, {
        depth: 8,
        breakLength: Infinity,
        compact: true
    });
}

function formatLogLine(level, args) {
    const timestamp = new Date().toISOString();
    const message = args.map(formatArg).join(' ');
    return message
        .split(/\r?\n/)
        .map((line) => `${timestamp} ${level} ${line}`)
        .join('\n') + '\n';
}

function installConsoleFileLogger(options = {}) {
    if (installed) return;
    installed = true;

    const originalConsole = {
        log: console.log.bind(console),
        info: console.info.bind(console),
        warn: console.warn.bind(console),
        error: console.error.bind(console)
    };

    const logDir = options.logDir || path.join(process.cwd(), 'log');
    let stream = null;
    let currentLogFileName = null;

    function ensureStream() {
        const nextLogFileName = getLogFileName();
        if (stream && !stream.destroyed && currentLogFileName === nextLogFileName) {
            return stream;
        }

        try {
            fs.mkdirSync(logDir, { recursive: true });
            if (stream && !stream.destroyed) {
                stream.end();
            }

            currentLogFileName = nextLogFileName;
            const logFile = path.join(logDir, currentLogFileName);
            stream = fs.createWriteStream(logFile, { flags: 'a' });
            stream.on('error', (error) => {
                originalConsole.error('Erro ao escrever arquivo de log web:', error.message);
            });
            return stream;
        } catch (error) {
            originalConsole.error('Erro ao inicializar arquivo de log web:', error.message);
            stream = null;
            currentLogFileName = null;
            return null;
        }
    }

    function mirror(level, originalMethod, args) {
        originalMethod(...args);

        const activeStream = ensureStream();
        if (!activeStream || activeStream.destroyed) {
            return;
        }

        try {
            activeStream.write(formatLogLine(level, args));
        } catch (error) {
            originalConsole.error('Erro ao registrar mensagem no log web:', error.message);
        }
    }

    console.log = (...args) => mirror('INFO', originalConsole.log, args);
    console.info = (...args) => mirror('INFO', originalConsole.info, args);
    console.warn = (...args) => mirror('WARN', originalConsole.warn, args);
    console.error = (...args) => mirror('ERROR', originalConsole.error, args);
}

module.exports = {
    installConsoleFileLogger
};
