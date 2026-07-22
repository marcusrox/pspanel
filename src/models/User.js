const database = require('../database/connection');
const schema = require('../database/schema');

const AUTH_TYPES = new Set(['local', 'ldap']);
const MAX_USERNAME_LENGTH = 255;

function normalizeUsername(username) {
    return String(username || '').trim().toLowerCase().slice(0, MAX_USERNAME_LENGTH);
}

function normalizeAuthType(authType) {
    const normalized = String(authType || '').trim().toLowerCase();
    return AUTH_TYPES.has(normalized) ? normalized : null;
}

function optionalText(value, maxLength) {
    if (value == null) return null;
    const text = String(value).trim();
    return text ? text.slice(0, maxLength) : null;
}

class User {
    static async initialize() {
        await schema.initialize();
    }

    static async recordSuccessfulLogin(profile, requestContext = {}) {
        await User.initialize();
        const username = optionalText(profile && profile.username, MAX_USERNAME_LENGTH);
        const normalizedUsername = normalizeUsername(username);
        const authType = normalizeAuthType(profile && (profile.type || profile.authType));

        if (!username || !normalizedUsername || !authType) {
            throw new Error('Perfil autenticado invalido para cadastro de usuario.');
        }

        const now = new Date().toISOString();
        const displayName = optionalText(profile.displayName, 255);
        const email = optionalText(profile.email, 320);
        const clientIp = optionalText(requestContext.clientIp, 64);
        const userAgent = optionalText(requestContext.userAgent, 512);

        await database.run(
            `INSERT INTO users (
                username, normalized_username, display_name, email, auth_type,
                first_login_at, last_login_at, last_login_ip, last_user_agent,
                login_count, created_at, updated_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
             ON CONFLICT(auth_type, normalized_username) DO UPDATE SET
                username = excluded.username,
                display_name = COALESCE(excluded.display_name, users.display_name),
                email = COALESCE(excluded.email, users.email),
                last_login_at = excluded.last_login_at,
                last_login_ip = excluded.last_login_ip,
                last_user_agent = excluded.last_user_agent,
                login_count = users.login_count + 1,
                updated_at = excluded.updated_at`,
            [
                username,
                normalizedUsername,
                displayName,
                email,
                authType,
                now,
                now,
                clientIp,
                userAgent,
                now,
                now
            ]
        );

        return User.findByIdentity(authType, normalizedUsername);
    }

    static async findByIdentity(authType, username) {
        await User.initialize();
        const normalizedAuthType = normalizeAuthType(authType);
        const normalizedUsername = normalizeUsername(username);
        if (!normalizedAuthType || !normalizedUsername) return null;

        return database.get(
            'SELECT * FROM users WHERE auth_type = ? AND normalized_username = ?',
            [normalizedAuthType, normalizedUsername]
        );
    }

    static async findById(id) {
        await User.initialize();
        return database.get('SELECT * FROM users WHERE id = ?', [id]);
    }

    static buildListWhere(filters = {}) {
        const where = [];
        const params = [];
        const search = optionalText(filters.search, 255);
        const authType = normalizeAuthType(filters.authType);

        if (search) {
            const term = `%${search}%`;
            where.push('(username LIKE ? OR display_name LIKE ? OR email LIKE ?)');
            params.push(term, term, term);
        }
        if (authType) {
            where.push('auth_type = ?');
            params.push(authType);
        }

        return { where, params };
    }

    static async list(filters = {}, limit = 20, offset = 0) {
        await User.initialize();
        const { where, params } = User.buildListWhere(filters);
        return database.all(
            `SELECT * FROM users
             ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
             ORDER BY last_login_at DESC, id DESC
             LIMIT ? OFFSET ?`,
            [...params, limit, offset]
        );
    }

    static async count(filters = {}) {
        await User.initialize();
        const { where, params } = User.buildListWhere(filters);
        const row = await database.get(
            `SELECT COUNT(*) AS total FROM users
             ${where.length ? `WHERE ${where.join(' AND ')}` : ''}`,
            params
        );
        return row ? row.total : 0;
    }
}

module.exports = User;
