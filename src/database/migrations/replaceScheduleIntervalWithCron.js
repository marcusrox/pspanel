async function replaceScheduleIntervalWithCron(db) {
    await db.run('UPDATE schedule_audit SET schedule_id = NULL WHERE schedule_id IS NOT NULL');
    await db.run(`CREATE TABLE schedules_cron_migration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_name TEXT NOT NULL,
        parameters TEXT,
        enabled INTEGER NOT NULL DEFAULT 1,
        next_run_at TEXT NOT NULL,
        schedule_type TEXT NOT NULL CHECK(schedule_type IN ('once', 'cron')),
        cron_expression TEXT,
        schedule_timezone TEXT NOT NULL CHECK(length(trim(schedule_timezone)) > 0),
        worker_lock_until TEXT,
        last_run_at TEXT,
        last_run_exit_code INTEGER,
        last_run_output TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        created_by TEXT,
        CHECK(
            (schedule_type = 'once' AND cron_expression IS NULL)
            OR (schedule_type = 'cron' AND cron_expression IS NOT NULL)
        )
    )`);
    await db.run('DROP TABLE schedules');
    await db.run('ALTER TABLE schedules_cron_migration RENAME TO schedules');
    await db.run('CREATE INDEX idx_schedules_due ON schedules (enabled, next_run_at)');
}

module.exports = replaceScheduleIntervalWithCron;
