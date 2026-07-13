const fs = require('fs');
const path = require('path');

const LOG_FILE_PATTERN = /^web-\d{4}-\d{2}-\d{2}\.log$/;
const DEFAULT_LINE_LIMIT = 500;
const MIN_LINE_LIMIT = 50;
const MAX_LINE_LIMIT = 2000;
const MAX_READ_BYTES = 1024 * 1024;

class OperationalLogError extends Error {
    constructor(message, code) {
        super(message);
        this.name = 'OperationalLogError';
        this.code = code;
    }
}

function getLogDirectory() {
    return path.resolve(process.cwd(), 'log');
}

function validateFileName(fileName) {
    if (
        typeof fileName !== 'string' ||
        !LOG_FILE_PATTERN.test(fileName) ||
        fileName.includes('..') ||
        fileName.includes('/') ||
        fileName.includes('\\') ||
        path.basename(fileName) !== fileName
    ) {
        throw new OperationalLogError('Nome de arquivo de log inválido.', 'INVALID_FILE_NAME');
    }

    return fileName;
}

function normalizeLineLimit(value) {
    if (value === undefined || value === null || value === '') {
        return DEFAULT_LINE_LIMIT;
    }

    const parsed = Number(value);
    if (!Number.isInteger(parsed)) {
        throw new OperationalLogError('Quantidade de linhas inválida.', 'INVALID_LINE_LIMIT');
    }

    return Math.min(Math.max(parsed, MIN_LINE_LIMIT), MAX_LINE_LIMIT);
}

function resolveLogFile(fileName) {
    const validFileName = validateFileName(fileName);
    const logDirectory = getLogDirectory();
    const filePath = path.resolve(logDirectory, validFileName);
    const expectedPrefix = `${logDirectory}${path.sep}`.toLowerCase();

    if (!filePath.toLowerCase().startsWith(expectedPrefix)) {
        throw new OperationalLogError('Nome de arquivo de log inválido.', 'INVALID_FILE_NAME');
    }

    return filePath;
}

async function listLogFiles() {
    const logDirectory = getLogDirectory();

    try {
        const entries = await fs.promises.readdir(logDirectory, { withFileTypes: true });
        return entries
            .filter((entry) => entry.isFile() && LOG_FILE_PATTERN.test(entry.name))
            .map((entry) => entry.name)
            .sort((left, right) => right.localeCompare(left));
    } catch (error) {
        if (error.code === 'ENOENT') {
            return [];
        }
        throw error;
    }
}

function selectInitialLogFile(files, date = new Date()) {
    const todayFileName = `web-${date.toISOString().slice(0, 10)}.log`;
    return files.includes(todayFileName) ? todayFileName : (files[0] || null);
}

async function readLogTail(fileName, lineLimitValue) {
    const validFileName = validateFileName(fileName);
    const lineLimit = normalizeLineLimit(lineLimitValue);
    const filePath = resolveLogFile(validFileName);
    let fileHandle;

    try {
        const pathStats = await fs.promises.lstat(filePath);
        if (!pathStats.isFile()) {
            throw new OperationalLogError('Arquivo de log não encontrado.', 'FILE_NOT_FOUND');
        }

        fileHandle = await fs.promises.open(filePath, 'r');
        const stats = await fileHandle.stat();
        const bytesToRead = Math.min(stats.size, MAX_READ_BYTES);
        const startPosition = Math.max(0, stats.size - bytesToRead);
        const buffer = Buffer.alloc(bytesToRead);

        const readResult = bytesToRead > 0
            ? await fileHandle.read(buffer, 0, bytesToRead, startPosition)
            : { bytesRead: 0 };

        let content = buffer.subarray(0, readResult.bytesRead).toString('utf8');
        if (startPosition > 0) {
            const firstLineBreak = content.indexOf('\n');
            if (firstLineBreak !== -1) {
                content = content.slice(firstLineBreak + 1);
            }
        }

        const availableLines = content === '' ? [] : content.split(/\r?\n/);
        if (availableLines.length && availableLines[availableLines.length - 1] === '') {
            availableLines.pop();
        }

        const selectedLines = availableLines.slice(-lineLimit);

        return {
            file: validFileName,
            content: selectedLines.join('\n'),
            lines: selectedLines.length,
            updatedAt: stats.mtime.toISOString(),
            truncated: startPosition > 0 || availableLines.length > selectedLines.length
        };
    } catch (error) {
        if (error.code === 'ENOENT') {
            throw new OperationalLogError('Arquivo de log não encontrado.', 'FILE_NOT_FOUND');
        }
        throw error;
    } finally {
        if (fileHandle) {
            await fileHandle.close();
        }
    }
}

module.exports = {
    listLogFiles,
    normalizeLineLimit,
    readLogTail,
    selectInitialLogFile,
    OperationalLogError
};
