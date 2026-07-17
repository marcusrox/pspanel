const fs = require('fs');
const os = require('os');
const path = require('path');
const Settings = require('../models/Settings');
const release = require('../config/release');
const packageManifest = require('../../package.json');

const PROJECT_ROOT = path.resolve(__dirname, '..', '..');
const NODE_MODULES_ROOT = path.join(PROJECT_ROOT, 'node_modules');
const PUBLIC_ENV_KEYS = new Set(['PORT', 'NODE_ENV']);
const ENV_ALLOWLIST = [
    'PORT',
    'NODE_ENV',
    'SESSION_SECRET',
    'ADMIN_USER',
    'ADMIN_PASSWORD',
    'ADMIN_PASSWORD_HASH',
    'LDAP_URL',
    'LDAP_BIND_DN',
    'LDAP_BIND_PASSWORD',
    'LDAP_SEARCH_BASE',
    'LDAP_SEARCH_FILTER'
];
const SENSITIVE_ENV_PATTERN = /(PASSWORD|TOKEN|SECRET|HASH|KEY|COOKIE|SESSION|AUTH|LDAP|ADMIN_USER)/i;

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

    const decimals = unitIndex === 0 ? 0 : 1;
    return `${amount.toFixed(decimals)} ${units[unitIndex]}`;
}

function formatDuration(totalSeconds) {
    const seconds = Number(totalSeconds);
    if (!Number.isFinite(seconds) || seconds < 0) return 'Indisponivel';

    const totalMinutes = Math.floor(seconds / 60);
    const days = Math.floor(totalMinutes / 1440);
    const hours = Math.floor((totalMinutes % 1440) / 60);
    const minutes = totalMinutes % 60;
    const parts = [];

    if (days) parts.push(`${days}d`);
    if (hours || days) parts.push(`${hours}h`);
    parts.push(`${minutes}min`);
    return parts.join(' ');
}

function normalizePublicEnvironmentValue(key, value) {
    if (key === 'PORT') {
        const port = Number(value);
        return Number.isInteger(port) && port >= 1 && port <= 65535 ? String(port) : 'Valor invalido';
    }

    if (key === 'NODE_ENV') {
        const normalized = String(value || '').trim().toLowerCase();
        return ['development', 'test', 'production'].includes(normalized) ? normalized : 'Outro ambiente';
    }

    return null;
}

function collectEnvironmentVariables(environment = process.env) {
    return ENV_ALLOWLIST.map((name) => {
        const configured = Object.prototype.hasOwnProperty.call(environment, name)
            && String(environment[name] || '').trim() !== '';

        if (!configured) return { name, status: 'Nao configurada', value: null };
        if (SENSITIVE_ENV_PATTERN.test(name) || !PUBLIC_ENV_KEYS.has(name)) {
            return { name, status: 'Mascarado', value: null };
        }

        return {
            name,
            status: 'Configurada',
            value: normalizePublicEnvironmentValue(name, environment[name])
        };
    });
}

function getDependencyGroups(nodeEnvironment = process.env.NODE_ENV) {
    const groups = [
        { type: 'Runtime', dependencies: packageManifest.dependencies || {} },
        { type: 'Opcional', dependencies: packageManifest.optionalDependencies || {} }
    ];

    if (nodeEnvironment === 'development') {
        groups.push({ type: 'Desenvolvimento', dependencies: packageManifest.devDependencies || {} });
    }

    return groups;
}

function readResolvedDependencyVersion(name) {
    require.resolve(name, { paths: [PROJECT_ROOT] });

    const segments = name.startsWith('@') ? name.split('/') : [name];
    const manifestPath = path.join(NODE_MODULES_ROOT, ...segments, 'package.json');
    const relativePath = path.relative(NODE_MODULES_ROOT, manifestPath);
    if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
        throw new Error('Caminho de dependencia invalido.');
    }

    const resolvedManifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    return typeof resolvedManifest.version === 'string' ? resolvedManifest.version : null;
}

function collectDependencies(nodeEnvironment = process.env.NODE_ENV) {
    return getDependencyGroups(nodeEnvironment)
        .flatMap(({ type, dependencies }) => Object.entries(dependencies).map(([name, declaredVersion]) => {
            try {
                const resolvedVersion = readResolvedDependencyVersion(name);
                return {
                    name,
                    type,
                    declaredVersion,
                    resolvedVersion: resolvedVersion || 'Indisponivel',
                    status: resolvedVersion ? 'Resolvido' : 'Nao resolvido'
                };
            } catch (error) {
                return {
                    name,
                    type,
                    declaredVersion,
                    resolvedVersion: 'Indisponivel',
                    status: type === 'Opcional' ? 'Opcional ausente' : 'Nao resolvido'
                };
            }
        }))
        .sort((left, right) => left.name.localeCompare(right.name, 'pt-BR'));
}

function getExternalPackageName(modulePath) {
    const normalized = modulePath.replace(/\\/g, '/');
    const marker = '/node_modules/';
    const markerIndex = normalized.lastIndexOf(marker);
    if (markerIndex === -1) return null;

    const segments = normalized.slice(markerIndex + marker.length).split('/').filter(Boolean);
    const packageName = segments[0] && segments[0].startsWith('@')
        ? `${segments[0]}/${segments[1] || ''}`
        : segments[0];
    return /^(@[a-z0-9._-]+\/)?[a-z0-9._-]+$/i.test(packageName || '') ? packageName : null;
}

function getInternalModuleName(modulePath) {
    const relativePath = path.relative(PROJECT_ROOT, modulePath);
    if (!relativePath || relativePath.startsWith('..') || path.isAbsolute(relativePath)) return null;
    if (relativePath.split(path.sep).includes('node_modules')) return null;
    return relativePath.replace(/\\/g, '/');
}

function collectLoadedModules(moduleCache = require.cache) {
    const internalModules = new Set();
    const externalPackages = new Set();

    Object.keys(moduleCache || {}).forEach((modulePath) => {
        const externalName = getExternalPackageName(modulePath);
        if (externalName) {
            externalPackages.add(externalName);
            return;
        }

        const internalName = getInternalModuleName(modulePath);
        if (internalName) internalModules.add(internalName);
    });

    return {
        internal: Array.from(internalModules).sort((left, right) => left.localeCompare(right, 'pt-BR')),
        external: Array.from(externalPackages).sort((left, right) => left.localeCompare(right, 'pt-BR'))
    };
}

function normalizeStoredDate(value) {
    if (!value) return 'Sem registro';
    const candidate = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(value)
        ? `${value.replace(' ', 'T')}Z`
        : value;
    const date = new Date(candidate);
    return Number.isNaN(date.getTime()) ? 'Indisponivel' : date.toISOString();
}

async function collectSafeSettings() {
    const settings = await Settings.getAll();
    const scripts = settings.scripts || {};
    const ui = settings.ui || {};
    const email = settings.email || {};
    const maxExecutionTime = Number.parseInt(scripts.max_execution_time, 10);
    const fontScale = ['85', '90', '100', '110'].includes(ui.font_scale) ? ui.font_scale : '100';

    return [
        {
            name: 'Tempo maximo de execucao',
            value: Number.isInteger(maxExecutionTime) && maxExecutionTime > 0
                ? `${maxExecutionTime} segundos`
                : 'Indisponivel'
        },
        { name: 'Escala de fonte', value: `${fontScale}%` },
        { name: 'Resumo diario por email', value: email.daily_summary_enabled === '1' ? 'Habilitado' : 'Desabilitado' },
        { name: 'Destinatario do resumo', value: String(email.daily_summary_recipient || '').trim() ? 'Configurado' : 'Nao configurado' },
        { name: 'Ultimo envio do resumo', value: normalizeStoredDate(email.daily_summary_last_sent_at) },
        { name: 'Persistencia', value: 'SQLite local' },
        { name: 'Diretorio de scripts', value: 'scripts-ps/' },
        { name: 'Diretorio de logs', value: 'log/' }
    ];
}

function collectOperatingSystem() {
    return [
        { name: 'Plataforma', value: os.platform() },
        { name: 'Tipo', value: os.type() },
        { name: 'Release', value: os.release() },
        { name: 'Arquitetura', value: os.arch() },
        { name: 'CPUs disponiveis', value: String(os.cpus().length) },
        { name: 'Memoria total', value: formatBytes(os.totalmem()) },
        { name: 'Memoria livre', value: formatBytes(os.freemem()) }
    ];
}

function collectProcess() {
    const memory = process.memoryUsage();
    const versionKeys = ['node', 'v8', 'uv', 'openssl', 'modules', 'napi'];

    return {
        details: [
            { name: 'Versao do Node.js', value: process.version },
            { name: 'Plataforma', value: process.platform },
            { name: 'Arquitetura', value: process.arch },
            { name: 'PID', value: String(process.pid) },
            { name: 'Tempo de atividade', value: formatDuration(process.uptime()) },
            { name: 'Memoria RSS', value: formatBytes(memory.rss) },
            { name: 'Heap utilizado', value: formatBytes(memory.heapUsed) },
            { name: 'Heap total', value: formatBytes(memory.heapTotal) }
        ],
        versions: versionKeys
            .filter((key) => process.versions[key])
            .map((key) => ({ name: key, value: process.versions[key] }))
    };
}

async function collectRuntimeEnvironment() {
    const collectedAt = new Date().toISOString();
    const processInfo = collectProcess();
    let safeSettings;

    try {
        safeSettings = await collectSafeSettings();
    } catch (error) {
        safeSettings = [{ name: 'Configuracoes persistidas', value: 'Indisponivel' }];
    }

    return {
        collectedAt,
        summary: [
            { label: 'Release', value: release.label || 'Nao informado', icon: 'fas fa-tag' },
            { label: 'Node.js', value: process.version, icon: 'fa-brands fa-node-js' },
            { label: 'Sistema', value: `${os.type()} ${os.release()}`, icon: 'fas fa-desktop' },
            { label: 'Arquitetura', value: process.arch, icon: 'fas fa-microchip' },
            { label: 'Tempo ativo', value: formatDuration(process.uptime()), icon: 'fas fa-stopwatch' }
        ],
        application: [
            { name: 'Pacote', value: packageManifest.name || 'pspanel' },
            { name: 'Versao', value: packageManifest.version || 'Nao informada' },
            { name: 'Release', value: release.label || 'Nao informado' },
            { name: 'Ambiente', value: normalizePublicEnvironmentValue('NODE_ENV', process.env.NODE_ENV) || 'Nao configurado' },
            { name: 'Coletado em', value: collectedAt }
        ],
        operatingSystem: collectOperatingSystem(),
        process: processInfo,
        dependencies: collectDependencies(),
        loadedModules: collectLoadedModules(),
        environmentVariables: collectEnvironmentVariables(),
        settings: safeSettings
    };
}

module.exports = {
    collectDependencies,
    collectEnvironmentVariables,
    collectLoadedModules,
    collectRuntimeEnvironment,
    formatBytes,
    formatDuration
};
