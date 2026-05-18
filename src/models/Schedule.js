const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
const History = require('./History');
const { buildPowerShellCommandArgs } = require('../services/powerShellRunner');

const dbPath = path.join(__dirname, '../../database/schedules.sqlite');
const dbDir = path.dirname(dbPath);
if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
}

const db = new sqlite3.Database(dbPath);

const SCHEDULE_RUN_USERNAME = 'Agendamento (worker)';
const LOCK_MS = 30 * 60 * 1000;
const STALE_LOCK_MS = 2 * 60 * 60 * 1000;
const RETRY_AFTER_FAIL_MIN = 5;
const OUTPUT_MAX = 8000;

function nowIso() {
    return new Date().toISOString();
}

function runPowerShell(scriptPath, argList) {
    return new Promise((resolve, reject) => {
        const ps = spawn('powershell.exe', buildPowerShellCommandArgs(scriptPath, argList, { executionPolicy: 'Bypass' }));
        let stdout = '';
        let stderr = '';
        ps.stdout.on('data', (d) => { stdout += d.toString(); });
        ps.stderr.on('data', (d) => { stderr += d.toString(); });
        ps.on('error', reject);
        ps.on('close', (code) => {
            resolve({ code, stdout, stderr });
        });
    });
}

class Schedule {
    static async initialize() {
        return new Promise((resolve, reject) => {
            db.serialize(() => {
                db.run(`CREATE TABLE IF NOT EXISTS schedules (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    script_name TEXT NOT NULL,
                    parameters TEXT,
                    enabled INTEGER NOT NULL DEFAULT 1,
                    next_run_at TEXT NOT NULL,
                    repeat_interval_minutes INTEGER,
                    worker_lock_until TEXT,
                    last_run_at TEXT,
                    last_run_exit_code INTEGER,
                    last_run_output TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    created_by TEXT
                )`, (e1) => {
                    if (e1) return reject(e1);
                    db.run(`CREATE TABLE IF NOT EXISTS schedule_audit (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        schedule_id INTEGER,
                        action TEXT NOT NULL,
                        username TEXT,
                        details TEXT,
                        created_at TEXT NOT NULL
                    )`, (e2) => {
                        if (e2) return reject(e2);
                        db.run(`CREATE INDEX IF NOT EXISTS idx_schedules_due ON schedules (enabled, next_run_at)`, (e3) => {
                            if (e3) return reject(e3);
                            db.run(`CREATE INDEX IF NOT EXISTS idx_schedule_audit_created ON schedule_audit (created_at)`, (e4) => {
                                if (e4) return reject(e4);
                                resolve();
                            });
                        });
                    });
                });
            });
        });
    }

    static async appendAudit(scheduleId, action, username, detailsObj) {
        const details = detailsObj == null ? null : JSON.stringify(detailsObj);
        return new Promise((resolve, reject) => {
            db.run(
                `INSERT INTO schedule_audit (schedule_id, action, username, details, created_at) VALUES (?, ?, ?, ?, ?)`,
                [scheduleId, action, username || null, details, nowIso()],
                (err) => (err ? reject(err) : resolve())
            );
        });
    }

    static async findAll() {
        return new Promise((resolve, reject) => {
            db.all(
                `SELECT * FROM schedules ORDER BY enabled DESC, next_run_at ASC`,
                [],
                (err, rows) => (err ? reject(err) : resolve(rows || []))
            );
        });
    }

    static async findById(id) {
        return new Promise((resolve, reject) => {
            db.get(`SELECT * FROM schedules WHERE id = ?`, [id], (err, row) => (err ? reject(err) : resolve(row)));
        });
    }

    static async listAudit(limit = 200) {
        return new Promise((resolve, reject) => {
            db.all(
                `SELECT * FROM schedule_audit ORDER BY datetime(created_at) DESC LIMIT ?`,
                [limit],
                (err, rows) => (err ? reject(err) : resolve(rows || []))
            );
        });
    }

    static async create({ script_name, parameters, enabled, next_run_at, repeat_interval_minutes, created_by }) {
        const ts = nowIso();
        const en = enabled ? 1 : 0;
        const repeat = repeat_interval_minutes == null || repeat_interval_minutes === '' ? null : Number(repeat_interval_minutes);
        return new Promise((resolve, reject) => {
            db.run(
                `INSERT INTO schedules (script_name, parameters, enabled, next_run_at, repeat_interval_minutes, created_at, updated_at, created_by)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
                [script_name, parameters || null, en, next_run_at, repeat, ts, ts, created_by || null],
                function (err) {
                    if (err) return reject(err);
                    const id = this.lastID;
                    Schedule.appendAudit(id, 'CREATE', created_by, { script_name, next_run_at, repeat_interval_minutes: repeat })
                        .then(() => resolve(id))
                        .catch(reject);
                }
            );
        });
    }

    static async update(id, { script_name, parameters, enabled, next_run_at, repeat_interval_minutes }, username) {
        const ts = nowIso();
        const en = enabled ? 1 : 0;
        const repeat = repeat_interval_minutes == null || repeat_interval_minutes === '' ? null : Number(repeat_interval_minutes);
        return new Promise((resolve, reject) => {
            db.run(
                `UPDATE schedules SET script_name = ?, parameters = ?, enabled = ?, next_run_at = ?, repeat_interval_minutes = ?, updated_at = ?
                 WHERE id = ?`,
                [script_name, parameters || null, en, next_run_at, repeat, ts, id],
                async function (err) {
                    if (err) return reject(err);
                    try {
                        await Schedule.appendAudit(id, 'UPDATE', username, { script_name, next_run_at, repeat_interval_minutes: repeat, enabled: !!en });
                        resolve(this.changes);
                    } catch (e) {
                        reject(e);
                    }
                }
            );
        });
    }

    static async delete(id, username) {
        const row = await Schedule.findById(id);
        return new Promise((resolve, reject) => {
            db.run(`DELETE FROM schedules WHERE id = ?`, [id], async function (err) {
                if (err) return reject(err);
                try {
                    await Schedule.appendAudit(null, 'DELETE', username, { deleted_schedule_id: id, snapshot: row });
                    resolve(this.changes);
                } catch (e) {
                    reject(e);
                }
            });
        });
    }

    static async clearStaleLocks() {
        const threshold = new Date(Date.now() - STALE_LOCK_MS).toISOString();
        return new Promise((resolve, reject) => {
            db.run(
                `UPDATE schedules SET worker_lock_until = NULL WHERE worker_lock_until IS NOT NULL AND worker_lock_until < ?`,
                [threshold],
                (err) => (err ? reject(err) : resolve())
            );
        });
    }

    static async findDueCandidates() {
        return new Promise((resolve, reject) => {
            db.all(`SELECT * FROM schedules WHERE enabled = 1`, [], (err, rows) => {
                if (err) return reject(err);
                const now = Date.now();
                const due = (rows || []).filter((r) => {
                    if (r.worker_lock_until && new Date(r.worker_lock_until).getTime() > now) return false;
                    return new Date(r.next_run_at).getTime() <= now;
                });
                resolve(due);
            });
        });
    }

    static async setLock(id, untilIso) {
        return new Promise((resolve, reject) => {
            db.run(`UPDATE schedules SET worker_lock_until = ?, updated_at = ? WHERE id = ?`, [untilIso, nowIso(), id], (err) => (err ? reject(err) : resolve()));
        });
    }

    static async clearLock(id) {
        return new Promise((resolve, reject) => {
            db.run(`UPDATE schedules SET worker_lock_until = NULL, updated_at = ? WHERE id = ?`, [nowIso(), id], (err) => (err ? reject(err) : resolve()));
        });
    }

    static async recordRunResult(id, { last_run_at, last_run_exit_code, last_run_output, next_run_at, enabled }) {
        const out = last_run_output == null ? null : String(last_run_output).slice(0, OUTPUT_MAX);
        return new Promise((resolve, reject) => {
            db.run(
                `UPDATE schedules SET last_run_at = ?, last_run_exit_code = ?, last_run_output = ?, next_run_at = ?, enabled = ?, worker_lock_until = NULL, updated_at = ?
                 WHERE id = ?`,
                [last_run_at, last_run_exit_code, out, next_run_at, enabled ? 1 : 0, nowIso(), id],
                (err) => (err ? reject(err) : resolve())
            );
        });
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
            await Schedule.appendAudit(row.id, 'EXECUTE_START', SCHEDULE_RUN_USERNAME, { script_name: row.script_name });

            const scriptPath = path.join(scriptsDir, row.script_name);
            if (!fs.existsSync(scriptPath) || !row.script_name.endsWith('.ps1') || row.script_name.includes('..')) {
                await Schedule.appendAudit(row.id, 'EXECUTE_ERROR', SCHEDULE_RUN_USERNAME, { error: 'Script inválido ou inexistente' });
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

            const args = row.parameters ? String(row.parameters).split(/\s+/) : [];
            const filteredArgs = args.filter((a) => a.length > 0);

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
                if (row.repeat_interval_minutes != null && Number(row.repeat_interval_minutes) > 0) {
                    nextRun = new Date(Date.now() + Number(row.repeat_interval_minutes) * 60 * 1000).toISOString();
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
                next_run_at: nextRun,
                enabled
            });

            results.push({ id: row.id, ok, exitCode: proc.code });
        }

        return results;
    }
}

module.exports = Schedule;
