const database = require('./connection');

const migrations = [
    {
        id: '001_create_core_tables',
        up: async () => {
            await database.run(`CREATE TABLE IF NOT EXISTS script_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                script_name TEXT NOT NULL,
                parameters TEXT,
                username TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT,
                output TEXT,
                status TEXT CHECK(status IN ('success', 'error', 'running')) DEFAULT 'running',
                error_message TEXT
            )`);

            await database.run(`CREATE TABLE IF NOT EXISTS settings (
                key TEXT PRIMARY KEY,
                value TEXT,
                description TEXT
            )`);

            await database.run(`CREATE TABLE IF NOT EXISTS schedules (
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

            await database.run(`CREATE TABLE IF NOT EXISTS schedule_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                schedule_id INTEGER,
                script_name TEXT,
                action TEXT NOT NULL,
                username TEXT,
                details TEXT,
                created_at TEXT NOT NULL
            )`);

            await database.run(`CREATE INDEX IF NOT EXISTS idx_schedules_due ON schedules (enabled, next_run_at)`);
            await database.run(`CREATE INDEX IF NOT EXISTS idx_schedule_audit_created ON schedule_audit (created_at)`);
        }
    },
    {
        id: '002_add_script_name_to_schedule_audit',
        up: async () => {
            const columns = await database.all('PRAGMA table_info(schedule_audit)');
            const hasScriptName = columns.some((column) => column.name === 'script_name');

            if (!hasScriptName) {
                await database.run('ALTER TABLE schedule_audit ADD COLUMN script_name TEXT');
            }

            await database.run('CREATE INDEX IF NOT EXISTS idx_schedule_audit_script_name ON schedule_audit (script_name)');
        }
    }
];

let initialized = false;
let initializing = null;

async function hasMigration(id) {
    const row = await database.get('SELECT id FROM schema_migrations WHERE id = ?', [id]);
    return !!row;
}

async function applyMigration(migration) {
    await database.run('BEGIN IMMEDIATE');
    try {
        await migration.up();
        await database.run(
            'INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)',
            [migration.id, new Date().toISOString()]
        );
        await database.run('COMMIT');
    } catch (err) {
        await database.run('ROLLBACK').catch(() => {});
        throw err;
    }
}

async function initialize() {
    if (initialized) return;
    if (initializing) return initializing;

    initializing = (async () => {
        await database.configure();
        await database.run(`CREATE TABLE IF NOT EXISTS schema_migrations (
            id TEXT PRIMARY KEY,
            applied_at TEXT NOT NULL
        )`);

        for (const migration of migrations) {
            if (!(await hasMigration(migration.id))) {
                await applyMigration(migration);
            }
        }

        initialized = true;
    })();

    return initializing;
}

module.exports = {
    initialize
};
