const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');
const sqlite3 = require('sqlite3').verbose();
const addScheduleRetryAttemptCount = require('../src/database/migrations/addScheduleRetryAttemptCount');

function createDatabase() {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pspanel-retry-migration-'));
    const connection = new sqlite3.Database(path.join(directory, 'test.sqlite'));
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

async function createPreviousSchema(db) {
    await db.run(`CREATE TABLE schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_name TEXT NOT NULL,
        parameters TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        next_run_at TEXT NOT NULL,
        schedule_type TEXT NOT NULL CHECK(schedule_type IN ('once', 'cron')),
        cron_expression TEXT,
        schedule_timezone TEXT NOT NULL,
        worker_lock_until TEXT,
        last_run_at TEXT,
        last_run_exit_code INTEGER,
        last_run_output TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT
    )`);
    await db.run('CREATE INDEX idx_schedules_due ON schedules (enabled, next_run_at)');
    await db.run(`INSERT INTO schedules (
        id, script_name, enabled, next_run_at, schedule_type, cron_expression,
        schedule_timezone, created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`, [
        7, 'Example.ps1', 1, '2026-08-17T13:00:00.000Z', 'cron', '0 8 * * *',
        'America/Sao_Paulo', '2026-08-17T12:00:00.000Z', '2026-08-17T12:00:00.000Z'
    ]);
}

test('migration preserva agendamentos e adiciona contador protegido', async (t) => {
    const fixture = createDatabase();
    t.after(() => fixture.close());
    await createPreviousSchema(fixture.db);

    await fixture.db.run('BEGIN IMMEDIATE');
    await addScheduleRetryAttemptCount(fixture.db);
    await fixture.db.run('COMMIT');

    const row = await fixture.db.get('SELECT id, script_name, retry_attempt_count FROM schedules WHERE id = ?', [7]);
    assert.deepEqual(row, { id: 7, script_name: 'Example.ps1', retry_attempt_count: 0 });
    assert.equal((await fixture.db.get("SELECT COUNT(*) AS total FROM sqlite_master WHERE type = 'index' AND name = 'idx_schedules_due'")).total, 1);
    await assert.rejects(
        fixture.db.run('UPDATE schedules SET retry_attempt_count = ? WHERE id = ?', [-1, 7]),
        /CHECK constraint failed/
    );

    await addScheduleRetryAttemptCount(fixture.db);
    assert.equal((await fixture.db.get('SELECT COUNT(*) AS total FROM schedules')).total, 1);
});

test('transação externa restaura tabela anterior em falha', async (t) => {
    const fixture = createDatabase();
    t.after(() => fixture.close());
    await createPreviousSchema(fixture.db);
    const failingDb = {
        ...fixture.db,
        async run(sql, params) {
            if (sql === 'DROP TABLE schedules') throw new Error('falha simulada');
            return fixture.db.run(sql, params);
        }
    };

    await fixture.db.run('BEGIN IMMEDIATE');
    await assert.rejects(addScheduleRetryAttemptCount(failingDb), /falha simulada/);
    await fixture.db.run('ROLLBACK');

    const columns = await fixture.db.all('PRAGMA table_info(schedules)');
    assert.equal(columns.some((column) => column.name === 'retry_attempt_count'), false);
    assert.equal((await fixture.db.get('SELECT COUNT(*) AS total FROM schedules')).total, 1);
});
