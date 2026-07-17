const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const replaceScheduleIntervalWithCron = require('../src/database/migrations/replaceScheduleIntervalWithCron');

function createDatabase() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pspanel-cron-migration-'));
    const file = path.join(directory, 'test.sqlite');
    const connection = new sqlite3.Database(file);
    const db = {
        run(sql, params = []) {
            return new Promise((resolve, reject) => {
                connection.run(sql, params, function (error) {
                    if (error) reject(error);
                    else resolve({ lastID: this.lastID, changes: this.changes });
                });
            });
        },
        all(sql, params = []) {
            return new Promise((resolve, reject) => {
                connection.all(sql, params, (error, rows) => error ? reject(error) : resolve(rows));
            });
        },
        get(sql, params = []) {
            return new Promise((resolve, reject) => {
                connection.get(sql, params, (error, row) => error ? reject(error) : resolve(row));
            });
        }
    };

    return {
        db,
        async close() {
            await new Promise((resolve, reject) => connection.close((error) => error ? reject(error) : resolve()));
            fs.rmSync(directory, { recursive: true, force: true });
        }
    };
}

async function createLegacySchema(db) {
    await db.run(`CREATE TABLE schedules (
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
    )`);
    await db.run(`CREATE TABLE schedule_audit (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        schedule_id INTEGER,
        script_name TEXT,
        action TEXT NOT NULL,
        username TEXT,
        details TEXT,
        created_at TEXT NOT NULL
    )`);
    await db.run('CREATE INDEX idx_schedules_due ON schedules (enabled, next_run_at)');
    await db.run(`INSERT INTO schedules (
        script_name, enabled, next_run_at, repeat_interval_minutes, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?)`, [
        'Example.ps1', 1, '2026-07-17T12:00:00.000Z', 5,
        '2026-07-17T10:00:00.000Z', '2026-07-17T10:00:00.000Z'
    ]);
    await db.run(`INSERT INTO schedule_audit (
        schedule_id, script_name, action, created_at
    ) VALUES (?, ?, ?, ?)`, [1, 'Example.ps1', 'CREATE', '2026-07-17T10:00:00.000Z']);
}

test('migration descarta agendamentos, remove intervalo e preserva auditoria desvinculada', async (t) => {
    const fixture = createDatabase();
    t.after(() => fixture.close());
    await createLegacySchema(fixture.db);

    await fixture.db.run('BEGIN IMMEDIATE');
    await replaceScheduleIntervalWithCron(fixture.db);
    await fixture.db.run('COMMIT');

    const columns = await fixture.db.all('PRAGMA table_info(schedules)');
    const names = columns.map((column) => column.name);
    assert.equal(names.includes('repeat_interval_minutes'), false);
    assert.equal(names.includes('schedule_type'), true);
    assert.equal(names.includes('cron_expression'), true);
    assert.equal(names.includes('schedule_timezone'), true);
    assert.equal((await fixture.db.get('SELECT COUNT(*) AS total FROM schedules')).total, 0);
    assert.equal((await fixture.db.get('SELECT schedule_id FROM schedule_audit WHERE id = 1')).schedule_id, null);
    assert.equal((await fixture.db.get("SELECT COUNT(*) AS total FROM sqlite_master WHERE type = 'index' AND name = 'idx_schedules_due'")).total, 1);

    await assert.rejects(
        fixture.db.run(`INSERT INTO schedules (
            script_name, enabled, next_run_at, schedule_type, cron_expression,
            schedule_timezone, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`, [
            'Example.ps1', 1, '2026-07-17T12:00:00.000Z', 'once', '0 * * * *',
            'America/Sao_Paulo', '2026-07-17T10:00:00.000Z', '2026-07-17T10:00:00.000Z'
        ]),
        /CHECK constraint failed/
    );
});

test('transação externa restaura schema e dados se a migration falhar', async (t) => {
    const fixture = createDatabase();
    t.after(() => fixture.close());
    await createLegacySchema(fixture.db);
    const failingDb = {
        ...fixture.db,
        async run(sql, params) {
            if (sql === 'DROP TABLE schedules') throw new Error('falha simulada');
            return fixture.db.run(sql, params);
        }
    };

    await fixture.db.run('BEGIN IMMEDIATE');
    await assert.rejects(replaceScheduleIntervalWithCron(failingDb), /falha simulada/);
    await fixture.db.run('ROLLBACK');

    const columns = await fixture.db.all('PRAGMA table_info(schedules)');
    assert.equal(columns.some((column) => column.name === 'repeat_interval_minutes'), true);
    assert.equal((await fixture.db.get('SELECT COUNT(*) AS total FROM schedules')).total, 1);
    assert.equal((await fixture.db.get('SELECT schedule_id FROM schedule_audit WHERE id = 1')).schedule_id, 1);
});
