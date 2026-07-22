const database = require('./connection');
const replaceScheduleIntervalWithCron = require('./migrations/replaceScheduleIntervalWithCron');

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
    },
    {
        id: '003_replace_schedule_interval_with_cron',
        up: replaceScheduleIntervalWithCron
    },
    {
        id: '004_add_users_and_audit_trails',
        up: async () => {
            await database.run(`CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT NOT NULL,
                normalized_username TEXT NOT NULL,
                display_name TEXT,
                email TEXT,
                auth_type TEXT NOT NULL CHECK(auth_type IN ('local', 'ldap')),
                first_login_at TEXT NOT NULL,
                last_login_at TEXT NOT NULL,
                last_login_ip TEXT,
                last_user_agent TEXT,
                login_count INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE(auth_type, normalized_username)
            )`);

            await database.run(`CREATE TABLE IF NOT EXISTS access_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER,
                username TEXT,
                auth_type TEXT CHECK(auth_type IN ('local', 'ldap')),
                action TEXT NOT NULL,
                success INTEGER NOT NULL CHECK(success IN (0, 1)),
                reason_code TEXT,
                ip_address TEXT,
                user_agent TEXT,
                details TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE SET NULL
            )`);

            const historyColumns = await database.all('PRAGMA table_info(script_history)');
            const historyColumnNames = new Set(historyColumns.map((column) => column.name));
            if (!historyColumnNames.has('user_id')) {
                await database.run('ALTER TABLE script_history ADD COLUMN user_id INTEGER REFERENCES users(id)');
            }
            if (!historyColumnNames.has('auth_type')) {
                await database.run('ALTER TABLE script_history ADD COLUMN auth_type TEXT');
            }
            if (!historyColumnNames.has('client_ip')) {
                await database.run('ALTER TABLE script_history ADD COLUMN client_ip TEXT');
            }
            if (!historyColumnNames.has('execution_source')) {
                await database.run('ALTER TABLE script_history ADD COLUMN execution_source TEXT');
            }

            const scheduleAuditColumns = await database.all('PRAGMA table_info(schedule_audit)');
            const scheduleAuditColumnNames = new Set(scheduleAuditColumns.map((column) => column.name));
            if (!scheduleAuditColumnNames.has('user_id')) {
                await database.run('ALTER TABLE schedule_audit ADD COLUMN user_id INTEGER REFERENCES users(id)');
            }
            if (!scheduleAuditColumnNames.has('auth_type')) {
                await database.run('ALTER TABLE schedule_audit ADD COLUMN auth_type TEXT');
            }
            if (!scheduleAuditColumnNames.has('client_ip')) {
                await database.run('ALTER TABLE schedule_audit ADD COLUMN client_ip TEXT');
            }

            await database.run('CREATE INDEX IF NOT EXISTS idx_users_last_login ON users (last_login_at)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_users_auth_type ON users (auth_type)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_users_normalized_username ON users (normalized_username)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_access_audit_user_created ON access_audit (user_id, created_at)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_access_audit_created ON access_audit (created_at)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_access_audit_action ON access_audit (action)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_access_audit_username ON access_audit (username)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_script_history_user_created ON script_history (user_id, start_time)');
            await database.run('CREATE INDEX IF NOT EXISTS idx_schedule_audit_user_created ON schedule_audit (user_id, created_at)');
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
        await migration.up(database);
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
