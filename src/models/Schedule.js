const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const History = require('./History');
const database = require('../database/connection');
const schema = require('../database/schema');
const { getPowerShellExecutable, buildPowerShellCommandArgs } = require('../services/powerShellRunner');
const {
    SCHEDULE_TYPES,
    getNextOccurrence
} = require('../services/scheduleRecurrence');
const {
    parseScriptParametersFromContent,
    getMissingRequiredParameters,
    parseRawNamedParameters,
    tokenizePowerShellArgs
} = require('../services/powerShellParameters');

const SCHEDULE_RUN_USERNAME = 'Agendamento (worker)';
const LOCK_MS = 30 * 60 * 1000;
const STALE_LOCK_MS = 2 * 60 * 60 * 1000;
const RETRY_AFTER_FAIL_MIN = 5;
const OUTPUT_MAX = 8000;

function nowIso() {
    return new Date().toISOString();
}

function getAuditScriptName(row) {
    if (!row || row.script_name) return row ? row.script_name : null;
    if (!row.details) return null;

    try {
        const details = JSON.parse(row.details);
        if (details && typeof details.script_name === 'string') return details.script_name;
        if (details && details.snapshot && typeof details.snapshot.script_name === 'string') {
            return details.snapshot.script_name;
        }
    } catch (e) {
        return null;
    }

    return null;
}

function runPowerShell(scriptPath, argList) {
    return new Promise((resolve, reject) => {
        const ps = spawn(getPowerShellExecutable(), buildPowerShellCommandArgs(scriptPath, argList, { executionPolicy: 'Bypass' }));
        let stdout = '';
        let stderr = '';
        ps.stdout.on('data', (d) => { stdout += d.toString('utf8'); });
        ps.stderr.on('data', (d) => { stderr += d.toString('utf8'); });
        ps.on('error', reject);
        ps.on('close', (code) => {
            resolve({ code, stdout, stderr });
        });
    });
}

async function recordHistoryFailure(scriptName, parameters, message) {
    try {
        const historyId = await History.addEntry(scriptName, parameters || '', SCHEDULE_RUN_USERNAME);
        await History.updateEntry(historyId, message, 'error', message);
    } catch (e) {
        console.error('History validation failure:', e);
    }
}

class Schedule {
    static async initialize() {
        await schema.initialize();
    }

    static async appendAudit(scheduleId, action, username, detailsObj, scriptName = null) {
        await Schedule.initialize();
        const details = detailsObj == null ? null : JSON.stringify(detailsObj);
        await database.run(
            `INSERT INTO schedule_audit (schedule_id, script_name, action, username, details, created_at)
             VALUES (?, ?, ?, ?, ?, ?)`,
            [scheduleId, scriptName || null, action, username || null, details, nowIso()]
        );
    }

    static async findAll() {
        await Schedule.initialize();
        return database.all(`SELECT * FROM schedules ORDER BY enabled DESC, next_run_at ASC`);
    }

    static async findById(id) {
        await Schedule.initialize();
        return database.get(`SELECT * FROM schedules WHERE id = ?`, [id]);
    }

    static async listAudit(limit = 200, filters = {}) {
        await Schedule.initialize();
        const params = [];
        const where = [];
        const safeLimit = Number.isInteger(Number(limit)) && Number(limit) > 0 ? Number(limit) : 200;
        const scriptName = filters && typeof filters.script_name === 'string' ? filters.script_name.trim() : '';

        if (scriptName) {
            where.push('script_name LIKE ?');
            params.push(`%${scriptName}%`);
        }

        params.push(safeLimit);

        const rows = await database.all(
            `SELECT *
             FROM schedule_audit
             ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
             ORDER BY datetime(created_at) DESC
             LIMIT ?`,
            params
        );

        return rows.map((row) => ({
            ...row,
            script_name: getAuditScriptName(row)
        }));
    }

    static async create({
        script_name,
        parameters,
        enabled,
        next_run_at,
        schedule_type,
        cron_expression,
        schedule_timezone,
        created_by
    }) {
        const ts = nowIso();
        const en = enabled ? 1 : 0;
        await Schedule.initialize();
        const result = await database.run(
            `INSERT INTO schedules (
                script_name, parameters, enabled, next_run_at, schedule_type,
                cron_expression, schedule_timezone, created_at, updated_at, created_by
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                script_name,
                parameters || null,
                en,
                next_run_at,
                schedule_type,
                cron_expression || null,
                schedule_timezone,
                ts,
                ts,
                created_by || null
            ]
        );
        await Schedule.appendAudit(result.lastID, 'CREATE', created_by, {
            script_name,
            schedule_type,
            cron_expression: cron_expression || null,
            schedule_timezone,
            next_run_at,
            enabled: !!en
        }, script_name);
        return result.lastID;
    }

    static async update(id, {
        script_name,
        parameters,
        enabled,
        next_run_at,
        schedule_type,
        cron_expression,
        schedule_timezone
    }, username) {
        const ts = nowIso();
        const en = enabled ? 1 : 0;
        await Schedule.initialize();
        const result = await database.run(
            `UPDATE schedules SET
                script_name = ?, parameters = ?, enabled = ?, next_run_at = ?, schedule_type = ?,
                cron_expression = ?, schedule_timezone = ?, updated_at = ?
             WHERE id = ?`,
            [
                script_name,
                parameters || null,
                en,
                next_run_at,
                schedule_type,
                cron_expression || null,
                schedule_timezone,
                ts,
                id
            ]
        );
        await Schedule.appendAudit(id, 'UPDATE', username, {
            script_name,
            schedule_type,
            cron_expression: cron_expression || null,
            schedule_timezone,
            next_run_at,
            enabled: !!en
        }, script_name);
        return result.changes;
    }

    static async delete(id, username) {
        const row = await Schedule.findById(id);
        const result = await database.run(`DELETE FROM schedules WHERE id = ?`, [id]);
        await Schedule.appendAudit(null, 'DELETE', username, { deleted_schedule_id: id, snapshot: row }, row ? row.script_name : null);
        return result.changes;
    }

    static async clearStaleLocks() {
        const threshold = new Date(Date.now() - STALE_LOCK_MS).toISOString();
        await Schedule.initialize();
        await database.run(
            `UPDATE schedules SET worker_lock_until = NULL WHERE worker_lock_until IS NOT NULL AND worker_lock_until < ?`,
            [threshold]
        );
    }

    static async findDueCandidates() {
        await Schedule.initialize();
        const rows = await database.all(`SELECT * FROM schedules WHERE enabled = 1`);
        const now = Date.now();
        return rows.filter((r) => {
            if (r.worker_lock_until && new Date(r.worker_lock_until).getTime() > now) return false;
            return new Date(r.next_run_at).getTime() <= now;
        });
    }

    static async setLock(id, untilIso) {
        await Schedule.initialize();
        await database.run(`UPDATE schedules SET worker_lock_until = ?, updated_at = ? WHERE id = ?`, [untilIso, nowIso(), id]);
    }

    static async clearLock(id) {
        await Schedule.initialize();
        await database.run(`UPDATE schedules SET worker_lock_until = NULL, updated_at = ? WHERE id = ?`, [nowIso(), id]);
    }

    static async recordRunResult(id, { last_run_at, last_run_exit_code, last_run_output, next_run_at, enabled }) {
        await Schedule.initialize();
        const out = last_run_output == null ? null : String(last_run_output).slice(0, OUTPUT_MAX);
        await database.run(
            `UPDATE schedules SET last_run_at = ?, last_run_exit_code = ?, last_run_output = ?, next_run_at = ?, enabled = ?, worker_lock_until = NULL, updated_at = ?
             WHERE id = ?`,
            [last_run_at, last_run_exit_code, out, next_run_at, enabled ? 1 : 0, nowIso(), id]
        );
    }

    /**
     * Executa todos os agendamentos vencidos (uso pelo worker Node ou tarefa agendada).
     */
    static async executeDueJobs(projectRoot = process.cwd()) {
        await Schedule.clearStaleLocks();
        const due = await Schedule.findDueCandidates();
        const scriptsDir = path.join(projectRoot, 'scripts-ps');
        const results = [];

        for (const row of due) {
            const lockUntil = new Date(Date.now() + LOCK_MS).toISOString();
            await Schedule.setLock(row.id, lockUntil);
            await Schedule.appendAudit(row.id, 'EXECUTE_START', SCHEDULE_RUN_USERNAME, { script_name: row.script_name }, row.script_name);

            const scriptPath = path.join(scriptsDir, row.script_name);
            if (
                !fs.existsSync(scriptPath)
                || !row.script_name.endsWith('.ps1')
                || row.script_name.includes('..')
                || row.script_name.includes('/')
                || row.script_name.includes('\\')
            ) {
                await Schedule.appendAudit(row.id, 'EXECUTE_ERROR', SCHEDULE_RUN_USERNAME, { error: 'Script inválido ou inexistente' }, row.script_name);
                const retryAt = new Date(Date.now() + RETRY_AFTER_FAIL_MIN * 60 * 1000).toISOString();
                await Schedule.recordRunResult(row.id, {
                    last_run_at: nowIso(),
                    last_run_exit_code: -1,
                    last_run_output: 'Arquivo de script não encontrado ou nome inválido.',
                    next_run_at: retryAt,
                    enabled: row.enabled
                });
                results.push({ id: row.id, ok: false, reason: 'bad_script' });
                continue;
            }

            let parameterDefinitions = [];
            try {
                const source = fs.readFileSync(scriptPath, 'utf8');
                const parameterInfo = parseScriptParametersFromContent(source);
                parameterDefinitions = parameterInfo && Array.isArray(parameterInfo.parameters)
                    ? parameterInfo.parameters
                    : [];
            } catch (e) {
                await Schedule.appendAudit(row.id, 'EXECUTE_ERROR', SCHEDULE_RUN_USERNAME, { error: 'Não foi possível validar parâmetros do script' }, row.script_name);
                await recordHistoryFailure(row.script_name, row.parameters || '', 'Não foi possível validar parâmetros do script antes da execução.');
                const retryAt = new Date(Date.now() + RETRY_AFTER_FAIL_MIN * 60 * 1000).toISOString();
                await Schedule.recordRunResult(row.id, {
                    last_run_at: nowIso(),
                    last_run_exit_code: -1,
                    last_run_output: 'Não foi possível validar parâmetros do script antes da execução.',
                    next_run_at: retryAt,
                    enabled: row.enabled
                });
                results.push({ id: row.id, ok: false, reason: 'parameter_validation_error' });
                continue;
            }

            const providedParamValues = parseRawNamedParameters(row.parameters, parameterDefinitions);
            const missingRequiredParameters = getMissingRequiredParameters(parameterDefinitions, providedParamValues);
            if (missingRequiredParameters.length) {
                const message = `Informe os parâmetros obrigatórios: ${missingRequiredParameters.join(', ')}.`;
                await Schedule.appendAudit(row.id, 'EXECUTE_ERROR', SCHEDULE_RUN_USERNAME, { error: message }, row.script_name);
                await recordHistoryFailure(row.script_name, row.parameters || '', message);
                const retryAt = new Date(Date.now() + RETRY_AFTER_FAIL_MIN * 60 * 1000).toISOString();
                await Schedule.recordRunResult(row.id, {
                    last_run_at: nowIso(),
                    last_run_exit_code: -1,
                    last_run_output: message,
                    next_run_at: retryAt,
                    enabled: row.enabled
                });
                results.push({ id: row.id, ok: false, reason: 'missing_required_parameters', missing: missingRequiredParameters });
                continue;
            }

            const filteredArgs = tokenizePowerShellArgs(row.parameters);

            let historyId;
            try {
                historyId = await History.addEntry(row.script_name, row.parameters || '', SCHEDULE_RUN_USERNAME);
            } catch (e) {
                console.error('History addEntry:', e);
            }

            let proc;
            try {
                proc = await runPowerShell(scriptPath, filteredArgs);
            } catch (e) {
                proc = { code: -1, stdout: '', stderr: String(e.message || e) };
            }

            const ok = proc.code === 0;
            const combined = (proc.stdout || '') + (proc.stderr ? `\n${proc.stderr}` : '');
            if (historyId) {
                try {
                    await History.updateEntry(
                        historyId,
                        combined || proc.stderr || '',
                        ok ? 'success' : 'error',
                        ok ? null : proc.stderr || null
                    );
                } catch (e) {
                    console.error('History updateEntry:', e);
                }
            }

            let nextRun;
            let enabled = !!row.enabled;
            if (ok) {
                if (row.schedule_type === SCHEDULE_TYPES.CRON) {
                    nextRun = getNextOccurrence(row.cron_expression, {
                        after: new Date(),
                        timezone: row.schedule_timezone
                    });
                } else {
                    nextRun = '2099-12-31T23:59:59.999Z';
                    enabled = false;
                }
            } else {
                nextRun = new Date(Date.now() + RETRY_AFTER_FAIL_MIN * 60 * 1000).toISOString();
            }

            await Schedule.recordRunResult(row.id, {
                last_run_at: nowIso(),
                last_run_exit_code: proc.code,
                last_run_output: combined,
                next_run_at: nextRun,
                enabled
            });

            await Schedule.appendAudit(row.id, 'EXECUTE_FINISH', SCHEDULE_RUN_USERNAME, {
                exitCode: proc.code,
                success: ok,
                schedule_type: row.schedule_type,
                cron_expression: row.cron_expression,
                schedule_timezone: row.schedule_timezone,
                next_run_at: nextRun,
                enabled
            }, row.script_name);

            results.push({ id: row.id, ok, exitCode: proc.code });
        }

        return results;
    }
}

module.exports = Schedule;
