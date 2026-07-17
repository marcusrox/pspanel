const fs = require('fs');
const path = require('path');
const database = require('../database/connection');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..');
const MAX_BACKUP_FILES = 500;
const SAFE_IDENTIFIER_PATTERN = /^[A-Za-z_][A-Za-z0-9_]*$/;
const INTERNAL_TABLES = new Set(['sqlite_sequence']);
const FILE_DEFINITIONS = [
    { name: 'pspanel.sqlite', category: 'Banco principal', expected: true },
    { name: 'pspanel.sqlite-wal', category: 'WAL', expected: false },
    { name: 'pspanel.sqlite-shm', category: 'Memoria compartilhada', expected: false },
    { name: 'email-settings.json', category: 'Outro artefato conhecido', expected: false },
    { name: 'email-settings.example.json', category: 'Configuracao de exemplo', expected: false }
];
const DATE_COLUMNS = {
    script_history: ['start_time', 'end_time'],
    schedules: ['created_at', 'updated_at', 'next_run_at', 'last_run_at'],
    schedule_audit: ['created_at'],
    schema_migrations: ['applied_at']
};

function formatBytes(value) {
    const bytes = Number(value);
    if (!Number.isFinite(bytes) || bytes < 0) return 'Indisponivel';

    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    let amount = bytes;
    let unitIndex = 0;
    while (amount >= 1024 && unitIndex < units.length - 1) {
        amount /= 1024;
        unitIndex += 1;
    }

    return `${amount.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

function formatPercent(value) {
    const percent = Number(value);
    return Number.isFinite(percent) ? `${percent.toFixed(1)}%` : 'Indisponivel';
}

function isSafeIdentifier(value) {
    return typeof value === 'string' && SAFE_IDENTIFIER_PATTERN.test(value);
}

function quoteIdentifier(value) {
    if (!isSafeIdentifier(value)) throw new Error('Identificador SQLite invalido.');
    return `"${value}"`;
}

function normalizeDefaultValue(value) {
    if (value === null || value === undefined) return '—';
    const normalized = String(value).trim();
    if (/^(NULL|CURRENT_(TIME|DATE|TIMESTAMP))$/i.test(normalized)) return normalized;
    if (/^-?\d+(\.\d+)?$/.test(normalized)) return normalized;
    return 'Literal definido';
}

async function safeStat(filePath) {
    try {
        const stats = await fs.promises.lstat(filePath);
        if (stats.isSymbolicLink()) return null;
        return stats;
    } catch (error) {
        if (error.code === 'ENOENT') return null;
        throw error;
    }
}

async function collectBackupSummary() {
    const backupsPath = path.join(database.databaseDir, 'backups');
    try {
        const directoryStats = await safeStat(backupsPath);
        if (!directoryStats || !directoryStats.isDirectory()) {
            return { name: 'backups/', category: 'Backup', status: 'Ausente', size: '—', modifiedAt: null, note: 'Diretorio nao encontrado' };
        }

        const entries = await fs.promises.readdir(backupsPath, { withFileTypes: true });
        const directFiles = entries.filter((entry) => entry.isFile() && !entry.isSymbolicLink());
        const inspectedFiles = directFiles.slice(0, MAX_BACKUP_FILES);
        let totalSize = 0;
        let latestModifiedAt = null;

        for (const entry of inspectedFiles) {
            const stats = await safeStat(path.join(backupsPath, entry.name));
            if (!stats || !stats.isFile()) continue;
            totalSize += stats.size;
            if (!latestModifiedAt || stats.mtime > latestModifiedAt) latestModifiedAt = stats.mtime;
        }

        const limited = directFiles.length > inspectedFiles.length;
        return {
            name: 'backups/',
            category: 'Backup',
            status: 'Presente',
            size: limited ? `${formatBytes(totalSize)} (parcial)` : formatBytes(totalSize),
            sizeBytes: totalSize,
            modifiedAt: latestModifiedAt ? latestModifiedAt.toISOString() : directoryStats.mtime.toISOString(),
            note: `${directFiles.length} arquivo(s) direto(s)${limited ? `; primeiros ${MAX_BACKUP_FILES} contabilizados` : ''}`
        };
    } catch (error) {
        return { name: 'backups/', category: 'Backup', status: 'Indisponivel', size: 'Indisponivel', modifiedAt: null, note: 'Falha ao coletar metadados' };
    }
}

async function collectUnknownSqliteFiles() {
    const knownNames = new Set(FILE_DEFINITIONS.map((definition) => definition.name.toLowerCase()));

    try {
        const entries = await fs.promises.readdir(database.databaseDir, { withFileTypes: true });
        const candidates = entries
            .filter((entry) => (
                entry.isFile()
                && !entry.isSymbolicLink()
                && entry.name.toLowerCase().endsWith('.sqlite')
                && !knownNames.has(entry.name.toLowerCase())
            ))
            .sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
        const files = [];

        for (const entry of candidates) {
            const stats = await safeStat(path.join(database.databaseDir, entry.name));
            if (!stats || !stats.isFile()) continue;

            files.push({
                name: entry.name,
                category: 'Desconhecido / possível legado',
                status: 'Presente',
                size: formatBytes(stats.size),
                sizeBytes: stats.size,
                modifiedAt: stats.mtime.toISOString(),
                note: 'Arquivo SQLite não mapeado pela aplicação'
            });
        }

        return files;
    } catch (error) {
        return [{
            name: '*.sqlite',
            category: 'Descoberta automática',
            status: 'Indisponivel',
            size: 'Indisponivel',
            sizeBytes: 0,
            modifiedAt: null,
            note: 'Falha ao enumerar arquivos SQLite adicionais'
        }];
    }
}

async function collectFiles() {
    const files = [];
    let accountedSizeBytes = 0;

    for (const definition of FILE_DEFINITIONS) {
        try {
            const stats = await safeStat(path.join(database.databaseDir, definition.name));
            const present = !!stats && stats.isFile();
            if (present) accountedSizeBytes += stats.size;
            files.push({
                name: definition.name,
                category: definition.category,
                status: present ? 'Presente' : 'Ausente',
                size: present ? formatBytes(stats.size) : '—',
                sizeBytes: present ? stats.size : 0,
                modifiedAt: present ? stats.mtime.toISOString() : null,
                note: definition.expected && !present ? 'Arquivo esperado nao encontrado' : null
            });
        } catch (error) {
            files.push({
                name: definition.name,
                category: definition.category,
                status: 'Indisponivel',
                size: 'Indisponivel',
                sizeBytes: 0,
                modifiedAt: null,
                note: 'Falha ao coletar metadados'
            });
        }
    }

    const unknownSqliteFiles = await collectUnknownSqliteFiles();
    for (const file of unknownSqliteFiles) {
        accountedSizeBytes += Number(file.sizeBytes || 0);
        files.push(file);
    }

    const backupSummary = await collectBackupSummary();
    accountedSizeBytes += Number(backupSummary.sizeBytes || 0);
    files.push(backupSummary);

    return { files, accountedSizeBytes, accountedSize: formatBytes(accountedSizeBytes) };
}

async function getPragmaValue(name) {
    if (!isSafeIdentifier(name)) throw new Error('PRAGMA invalido.');
    const row = await database.get(`PRAGMA ${name}`);
    return row ? Object.values(row)[0] : null;
}

async function collectSQLiteConfiguration() {
    const pragmaNames = ['journal_mode', 'foreign_keys', 'busy_timeout', 'synchronous', 'page_size', 'page_count', 'freelist_count', 'auto_vacuum', 'encoding'];
    const values = {};

    for (const name of pragmaNames) {
        try {
            values[name] = await getPragmaValue(name);
        } catch (error) {
            values[name] = null;
        }
    }

    let attachedDatabases = null;
    try {
        const rows = await database.all('PRAGMA database_list');
        attachedDatabases = rows.length;
    } catch (error) {
        attachedDatabases = null;
    }

    const pageSize = Number(values.page_size);
    const pageCount = Number(values.page_count);
    const freeListCount = Number(values.freelist_count);
    const logicalSizeBytes = Number.isFinite(pageSize) && Number.isFinite(pageCount) ? pageSize * pageCount : null;
    const freeBytes = Number.isFinite(pageSize) && Number.isFinite(freeListCount) ? pageSize * freeListCount : null;
    const freePercent = pageCount > 0 && Number.isFinite(freeListCount) ? (freeListCount / pageCount) * 100 : null;

    const labels = {
        journal_mode: 'Modo de journal',
        foreign_keys: 'Foreign keys',
        busy_timeout: 'Timeout de bloqueio',
        synchronous: 'Sincronizacao',
        page_size: 'Tamanho da pagina',
        page_count: 'Paginas alocadas',
        freelist_count: 'Paginas livres',
        auto_vacuum: 'Auto vacuum',
        encoding: 'Codificacao'
    };

    const formattedValues = {
        foreign_keys: values.foreign_keys === null ? 'Indisponivel' : Number(values.foreign_keys) === 1 ? 'Habilitado' : 'Desabilitado',
        busy_timeout: values.busy_timeout === null ? 'Indisponivel' : `${values.busy_timeout} ms`,
        page_size: values.page_size === null ? 'Indisponivel' : formatBytes(values.page_size)
    };

    return {
        raw: { ...values, attachedDatabases, logicalSizeBytes, freeBytes, freePercent },
        items: [
            ...pragmaNames.map((name) => ({ name: labels[name], value: formattedValues[name] || (values[name] === null ? 'Indisponivel' : String(values[name])) })),
            { name: 'Bancos anexados', value: attachedDatabases === null ? 'Indisponivel' : String(attachedDatabases) },
            { name: 'Tamanho logico aproximado', value: logicalSizeBytes === null ? 'Indisponivel' : formatBytes(logicalSizeBytes) },
            { name: 'Espaco livre interno', value: freeBytes === null ? 'Indisponivel' : formatBytes(freeBytes) },
            { name: 'Percentual de paginas livres', value: freePercent === null ? 'Indisponivel' : formatPercent(freePercent) }
        ]
    };
}

async function collectDbStat() {
    try {
        const rows = await database.all(`
            SELECT name, SUM(pgsize) AS size_bytes
            FROM dbstat
            GROUP BY name
        `);
        return {
            available: true,
            sizes: new Map(rows.filter((row) => isSafeIdentifier(row.name)).map((row) => [row.name, Number(row.size_bytes) || 0]))
        };
    } catch (error) {
        return { available: false, sizes: new Map() };
    }
}

async function collectColumns(tableName) {
    try {
        const rows = await database.all(`PRAGMA table_xinfo(${quoteIdentifier(tableName)})`);
        return rows.map((column) => ({
            name: String(column.name),
            type: String(column.type || 'Sem tipo declarado'),
            nullable: Number(column.notnull) === 1 ? 'Nao' : 'Sim',
            primaryKey: Number(column.pk) > 0 ? `Sim (${column.pk})` : 'Nao',
            defaultValue: normalizeDefaultValue(column.dflt_value),
            generated: Number(column.hidden) > 0 ? 'Sim' : 'Nao'
        }));
    } catch (error) {
        const rows = await database.all(`PRAGMA table_info(${quoteIdentifier(tableName)})`);
        return rows.map((column) => ({
            name: String(column.name),
            type: String(column.type || 'Sem tipo declarado'),
            nullable: Number(column.notnull) === 1 ? 'Nao' : 'Sim',
            primaryKey: Number(column.pk) > 0 ? `Sim (${column.pk})` : 'Nao',
            defaultValue: normalizeDefaultValue(column.dflt_value),
            generated: 'Indisponivel'
        }));
    }
}

async function collectIndexesForTable(tableName) {
    const indexes = [];
    const rows = await database.all(`PRAGMA index_list(${quoteIdentifier(tableName)})`);

    for (const row of rows) {
        if (!isSafeIdentifier(row.name)) continue;
        let columns = [];
        try {
            const columnRows = await database.all(`PRAGMA index_xinfo(${quoteIdentifier(row.name)})`);
            columns = columnRows
                .filter((column) => Number(column.key) === 1 && Number(column.cid) >= 0 && isSafeIdentifier(column.name))
                .sort((left, right) => Number(left.seqno) - Number(right.seqno))
                .map((column) => column.name);
        } catch (error) {
            columns = [];
        }

        const origins = { c: 'CREATE INDEX', u: 'Restricao UNIQUE', pk: 'Chave primaria' };
        indexes.push({
            name: row.name,
            table: tableName,
            columns,
            unique: Number(row.unique) === 1 ? 'Sim' : 'Nao',
            origin: origins[row.origin] || 'Indisponivel',
            partial: Number(row.partial) === 1 ? 'Sim' : 'Nao'
        });
    }

    return indexes;
}

async function collectFreshness(tableName, columns) {
    const allowedColumns = (DATE_COLUMNS[tableName] || []).filter((name) => columns.some((column) => column.name === name));
    if (!allowedColumns.length) return [];

    const freshness = [];
    for (const columnName of allowedColumns) {
        try {
            const row = await database.get(`
                SELECT MIN(${quoteIdentifier(columnName)}) AS oldest, MAX(${quoteIdentifier(columnName)}) AS newest
                FROM ${quoteIdentifier(tableName)}
            `);
            freshness.push({ column: columnName, oldest: row && row.oldest ? String(row.oldest) : null, newest: row && row.newest ? String(row.newest) : null });
        } catch (error) {
            freshness.push({ column: columnName, oldest: null, newest: null, unavailable: true });
        }
    }
    return freshness;
}

async function collectTables() {
    const catalog = await database.all(`
        SELECT name
        FROM sqlite_schema
        WHERE type = 'table'
        ORDER BY name
    `);
    const userTableNames = catalog
        .map((row) => row.name)
        .filter((name) => isSafeIdentifier(name) && !INTERNAL_TABLES.has(name) && !name.startsWith('sqlite_'));
    const dbStat = await collectDbStat();
    const mappedSize = Array.from(dbStat.sizes.values()).reduce((total, value) => total + value, 0);
    const tables = [];
    const indexes = [];

    for (const tableName of userTableNames) {
        let rowCount = null;
        let columns = [];
        let tableIndexes = [];
        let freshness = [];
        try {
            const countRow = await database.get(`SELECT COUNT(*) AS total FROM ${quoteIdentifier(tableName)}`);
            rowCount = Number(countRow.total);
        } catch (error) {
            rowCount = null;
        }
        try {
            columns = await collectColumns(tableName);
        } catch (error) {
            columns = [];
        }
        try {
            tableIndexes = await collectIndexesForTable(tableName);
            indexes.push(...tableIndexes);
        } catch (error) {
            tableIndexes = [];
        }
        freshness = await collectFreshness(tableName, columns);

        const sizeBytes = dbStat.sizes.get(tableName);
        tables.push({
            name: tableName,
            rowCount,
            rowCountLabel: rowCount === null ? 'Indisponivel' : rowCount.toLocaleString('pt-BR'),
            empty: rowCount === null ? 'Indisponivel' : rowCount === 0 ? 'Sim' : 'Nao',
            columnCount: columns.length,
            indexCount: tableIndexes.length,
            size: sizeBytes === undefined ? 'Indisponivel' : formatBytes(sizeBytes),
            share: sizeBytes === undefined || mappedSize <= 0 ? 'Indisponivel' : formatPercent((sizeBytes / mappedSize) * 100),
            columns,
            freshness
        });
    }

    return { tables, indexes, dbStatAvailable: dbStat.available };
}

async function collectRelationships(tables) {
    const foreignKeys = [];
    for (const table of tables) {
        try {
            const rows = await database.all(`PRAGMA foreign_key_list(${quoteIdentifier(table.name)})`);
            rows.forEach((row) => {
                if (!isSafeIdentifier(row.table) || !isSafeIdentifier(row.from) || !isSafeIdentifier(row.to)) return;
                foreignKeys.push({
                    from: `${table.name}.${row.from}`,
                    to: `${row.table}.${row.to}`,
                    onUpdate: String(row.on_update || 'NO ACTION'),
                    onDelete: String(row.on_delete || 'NO ACTION')
                });
            });
        } catch (error) {
            // Falha parcial: outras tabelas continuam sendo avaliadas.
        }
    }

    const tableNames = new Set(tables.map((table) => table.name));
    const logical = [];
    if (tableNames.has('schedules') && tableNames.has('schedule_audit')) {
        logical.push({
            from: 'schedules.id',
            to: 'schedule_audit.schedule_id',
            type: 'Relacao logica nao imposta por foreign key'
        });
    }

    return { foreignKeys, logical };
}

async function collectMigrations(tables) {
    if (!tables.some((table) => table.name === 'schema_migrations')) return [];
    try {
        return await database.all('SELECT id, applied_at FROM schema_migrations ORDER BY applied_at, id');
    } catch (error) {
        return [];
    }
}

async function collectSafeAggregates(tables) {
    const names = new Set(tables.map((table) => table.name));
    const groups = [];

    if (names.has('script_history')) {
        try {
            const statusRows = await database.all('SELECT status, COUNT(*) AS total FROM script_history GROUP BY status ORDER BY status');
            const interval = await database.get('SELECT MIN(start_time) AS oldest, MAX(start_time) AS newest FROM script_history');
            groups.push({
                name: 'Historico de execucoes',
                items: [
                    ...statusRows.map((row) => ({ label: `Status: ${row.status || 'sem status'}`, value: Number(row.total).toLocaleString('pt-BR') })),
                    { label: 'Execucao mais antiga', value: interval.oldest || 'Sem registro' },
                    { label: 'Execucao mais recente', value: interval.newest || 'Sem registro' }
                ]
            });
        } catch (error) {
            groups.push({ name: 'Historico de execucoes', unavailable: true, items: [] });
        }
    }

    if (names.has('schedules')) {
        try {
            const row = await database.get(`
                SELECT
                    SUM(CASE WHEN enabled = 1 THEN 1 ELSE 0 END) AS enabled_count,
                    SUM(CASE WHEN enabled <> 1 THEN 1 ELSE 0 END) AS disabled_count,
                    SUM(CASE WHEN repeat_interval_minutes IS NOT NULL THEN 1 ELSE 0 END) AS recurring_count,
                    SUM(CASE WHEN worker_lock_until IS NOT NULL AND worker_lock_until >= ? THEN 1 ELSE 0 END) AS active_lock_count
                FROM schedules
            `, [new Date().toISOString()]);
            groups.push({
                name: 'Agendamentos',
                items: [
                    { label: 'Habilitados', value: Number(row.enabled_count || 0).toLocaleString('pt-BR') },
                    { label: 'Desabilitados', value: Number(row.disabled_count || 0).toLocaleString('pt-BR') },
                    { label: 'Recorrentes', value: Number(row.recurring_count || 0).toLocaleString('pt-BR') },
                    { label: 'Locks ativos', value: Number(row.active_lock_count || 0).toLocaleString('pt-BR') }
                ]
            });
        } catch (error) {
            groups.push({ name: 'Agendamentos', unavailable: true, items: [] });
        }
    }

    if (names.has('schedule_audit')) {
        try {
            const row = await database.get('SELECT COUNT(*) AS total, MIN(created_at) AS oldest, MAX(created_at) AS newest FROM schedule_audit');
            groups.push({ name: 'Auditoria de agendamentos', items: [
                { label: 'Eventos', value: Number(row.total || 0).toLocaleString('pt-BR') },
                { label: 'Evento mais antigo', value: row.oldest || 'Sem registro' },
                { label: 'Evento mais recente', value: row.newest || 'Sem registro' }
            ] });
        } catch (error) {
            groups.push({ name: 'Auditoria de agendamentos', unavailable: true, items: [] });
        }
    }

    if (names.has('settings')) {
        const settingsTable = tables.find((table) => table.name === 'settings');
        groups.push({ name: 'Configuracoes', items: [{ label: 'Chaves armazenadas', value: settingsTable.rowCountLabel }] });
    }

    if (names.has('schema_migrations')) {
        try {
            const row = await database.get('SELECT COUNT(*) AS total, MAX(applied_at) AS newest FROM schema_migrations');
            groups.push({ name: 'Migracoes', items: [
                { label: 'Aplicadas', value: Number(row.total || 0).toLocaleString('pt-BR') },
                { label: 'Aplicacao mais recente', value: row.newest || 'Sem registro' }
            ] });
        } catch (error) {
            groups.push({ name: 'Migracoes', unavailable: true, items: [] });
        }
    }

    return groups;
}

async function collectHealth(sqliteConfiguration, physicalFiles, dbStatAvailable) {
    let quickCheck = 'Indisponivel';
    let foreignKeyViolations = null;
    const alerts = [];

    try {
        const row = await database.get('PRAGMA quick_check(1)');
        const result = row ? String(Object.values(row)[0]) : '';
        quickCheck = result.toLowerCase() === 'ok' ? 'Integro' : 'Atencao';
    } catch (error) {
        quickCheck = 'Indisponivel';
    }

    try {
        const row = await database.get('SELECT COUNT(*) AS total FROM pragma_foreign_key_check');
        foreignKeyViolations = Number(row.total || 0);
    } catch (error) {
        foreignKeyViolations = null;
    }

    const raw = sqliteConfiguration.raw;
    if (Number(raw.foreign_keys) !== 1) alerts.push('A verificacao de foreign keys esta desabilitada ou indisponivel.');
    if (Number(raw.freePercent) >= 20) alerts.push(`Paginas livres representam aproximadamente ${formatPercent(raw.freePercent)} do banco.`);
    if (!dbStatAvailable) alerts.push('A extensao dbstat nao esta disponivel; tamanhos por tabela foram omitidos.');
    if (quickCheck === 'Atencao') alerts.push('O quick check retornou um estado que requer verificacao operacional.');
    if (foreignKeyViolations > 0) alerts.push(`Foram identificadas ${foreignKeyViolations.toLocaleString('pt-BR')} violacao(oes) de foreign key.`);

    const mainFile = physicalFiles.files.find((file) => file.name === 'pspanel.sqlite');
    const walFile = physicalFiles.files.find((file) => file.name === 'pspanel.sqlite-wal');
    if (mainFile && walFile && mainFile.sizeBytes > 0 && walFile.sizeBytes > mainFile.sizeBytes * 2) {
        alerts.push('O arquivo WAL esta maior que duas vezes o banco principal.');
    }

    return {
        quickCheck,
        foreignKeyViolations: foreignKeyViolations === null ? 'Indisponivel' : foreignKeyViolations.toLocaleString('pt-BR'),
        alerts
    };
}

function readSqliteDriverVersion() {
    try {
        const manifestPath = path.join(PROJECT_ROOT, 'node_modules', 'sqlite3', 'package.json');
        const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
        return typeof manifest.version === 'string' ? manifest.version : 'Indisponivel';
    } catch (error) {
        return 'Indisponivel';
    }
}

async function collectDataEnvironment() {
    const collectedAt = new Date().toISOString();
    const [physicalFiles, sqliteConfiguration] = await Promise.all([
        collectFiles(),
        collectSQLiteConfiguration()
    ]);
    const tableData = await collectTables();
    const relationships = await collectRelationships(tableData.tables);
    const migrations = await collectMigrations(tableData.tables);
    const aggregates = await collectSafeAggregates(tableData.tables);
    const health = await collectHealth(sqliteConfiguration, physicalFiles, tableData.dbStatAvailable);
    const sqliteVersionRow = await database.get('SELECT sqlite_version() AS version').catch(() => null);
    const totalRows = tableData.tables.reduce((total, table) => total + (Number.isFinite(table.rowCount) ? table.rowCount : 0), 0);

    return {
        collectedAt,
        summary: [
            { label: 'Tamanho fisico', value: physicalFiles.accountedSize, icon: 'fas fa-hard-drive' },
            { label: 'Tabelas', value: tableData.tables.length.toLocaleString('pt-BR'), icon: 'fas fa-table' },
            { label: 'Indices', value: tableData.indexes.length.toLocaleString('pt-BR'), icon: 'fas fa-list-ol' },
            { label: 'Registros', value: totalRows.toLocaleString('pt-BR'), icon: 'fas fa-database' },
            { label: 'SQLite', value: sqliteVersionRow ? sqliteVersionRow.version : 'Indisponivel', icon: 'fas fa-layer-group' }
        ],
        technologies: [
            { name: 'Mecanismo', value: 'SQLite' },
            { name: 'Versao do engine', value: sqliteVersionRow ? sqliteVersionRow.version : 'Indisponivel' },
            { name: 'Driver Node.js', value: `sqlite3 ${readSqliteDriverVersion()}` },
            { name: 'Tipo de persistencia', value: 'Banco local baseado em arquivo' },
            { name: 'Conexao central', value: 'src/database/connection.js' },
            { name: 'Schema e migracoes', value: 'src/database/schema.js' },
            { name: 'Models consumidores', value: 'History, Settings e Schedule' },
            { name: 'Coletado em', value: collectedAt }
        ],
        physical: physicalFiles,
        sqlite: sqliteConfiguration,
        tables: tableData.tables,
        indexes: tableData.indexes,
        relationships,
        migrations: migrations.map((migration) => ({ id: String(migration.id), appliedAt: migration.applied_at, status: 'Aplicada' })),
        aggregates,
        health,
        notes: [
            'As contagens representam o instante de cada consulta e podem variar enquanto a aplicacao estiver em uso.',
            'Tamanhos por tabela sao aproximados e dependem da disponibilidade do modulo dbstat.',
            'Arquivos legados e backups sao apenas inventariados; seu conteudo nao e aberto.'
        ]
    };
}

module.exports = {
    collectDataEnvironment,
    formatBytes,
    isSafeIdentifier
};
