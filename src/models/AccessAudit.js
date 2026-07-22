const database = require('../database/connection');
const schema = require('../database/schema');

const ACTIONS = new Set(['LOGIN_SUCCESS', 'LOGIN_FAILURE', 'ACCESS_DENIED', 'LOGOUT', 'SESSION_ERROR']);
const AUTH_TYPES = new Set(['local', 'ldap']);

function limitedText(value, maxLength) {
    if (value == null) return null;
    const text = String(value).trim();
    return text ? text.slice(0, maxLength) : null;
}

function normalizeAuthType(value) {
    const authType = limitedText(value, 16);
    return authType && AUTH_TYPES.has(authType.toLowerCase()) ? authType.toLowerCase() : null;
}

class AccessAudit {
    static async initialize() {
        await schema.initialize();
    }

    static async record(event) {
        await AccessAudit.initialize();
        const action = limitedText(event && event.action, 64);
        if (!action || !ACTIONS.has(action)) {
            throw new Error('Acao de auditoria de acesso invalida.');
        }

        const details = event.details == null ? null : JSON.stringify(event.details).slice(0, 2000);
        const result = await database.run(
            `INSERT INTO access_audit (
                user_id, username, auth_type, action, success, reason_code,
                ip_address, user_agent, details, created_at
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                Number.isInteger(Number(event.userId)) && Number(event.userId) > 0 ? Number(event.userId) : null,
                limitedText(event.username, 255),
                normalizeAuthType(event.authType),
                action,
                event.success ? 1 : 0,
                limitedText(event.reasonCode, 64),
                limitedText(event.clientIp, 64),
                limitedText(event.userAgent, 512),
                details,
                event.createdAt || new Date().toISOString()
            ]
        );
        return result.lastID;
    }

    static async listByUser(userId, limit = 50) {
        await AccessAudit.initialize();
        return database.all(
            `SELECT * FROM access_audit
             WHERE user_id = ?
             ORDER BY created_at DESC, id DESC
             LIMIT ?`,
            [userId, limit]
        );
    }

    static buildConsolidatedWhere(filters = {}) {
        const where = [];
        const params = [];
        const category = limitedText(filters.category, 20);
        const authType = normalizeAuthType(filters.authType);
        const action = limitedText(filters.action, 64);
        const search = limitedText(filters.search, 255);
        const dateFrom = limitedText(filters.dateFrom, 10);
        const dateTo = limitedText(filters.dateTo, 10);

        if (Number.isInteger(Number(filters.userId)) && Number(filters.userId) > 0) {
            where.push('user_id = ?');
            params.push(Number(filters.userId));
        }
        if (['access', 'execution', 'schedule'].includes(category)) {
            where.push('category = ?');
            params.push(category);
        }
        if (authType) {
            where.push('auth_type = ?');
            params.push(authType);
        }
        if (action) {
            where.push('(action = ? OR status = ?)');
            params.push(action, action.toLowerCase());
        }
        if (search) {
            const term = `%${search}%`;
            where.push('(username LIKE ? OR subject LIKE ?)');
            params.push(term, term);
        }
        if (/^\d{4}-\d{2}-\d{2}$/.test(dateFrom || '')) {
            where.push('datetime(created_at) >= datetime(?)');
            params.push(`${dateFrom}T00:00:00.000Z`);
        }
        if (/^\d{4}-\d{2}-\d{2}$/.test(dateTo || '')) {
            where.push('datetime(created_at) <= datetime(?)');
            params.push(`${dateTo}T23:59:59.999Z`);
        }

        return { where, params };
    }

    static consolidatedSql() {
        return `
            SELECT 'access' AS category, id AS event_id, user_id, username, auth_type,
                   action, CASE WHEN success = 1 THEN 'success' ELSE 'error' END AS status,
                   reason_code AS subject, ip_address AS client_ip, created_at
            FROM access_audit
            UNION ALL
            SELECT 'execution' AS category, id AS event_id, user_id, username, auth_type,
                   'SCRIPT_EXECUTION' AS action, status, script_name AS subject,
                   client_ip, start_time AS created_at
            FROM script_history
            UNION ALL
            SELECT 'schedule' AS category, id AS event_id, user_id, username, auth_type,
                   action, NULL AS status, script_name AS subject,
                   client_ip, created_at
            FROM schedule_audit`;
    }

    static async listConsolidated(filters = {}, limit = 50, offset = 0) {
        await AccessAudit.initialize();
        const { where, params } = AccessAudit.buildConsolidatedWhere(filters);
        return database.all(
            `SELECT * FROM (${AccessAudit.consolidatedSql()}) audit
             ${where.length ? `WHERE ${where.join(' AND ')}` : ''}
             ORDER BY created_at DESC, event_id DESC
             LIMIT ? OFFSET ?`,
            [...params, limit, offset]
        );
    }

    static async countConsolidated(filters = {}) {
        await AccessAudit.initialize();
        const { where, params } = AccessAudit.buildConsolidatedWhere(filters);
        const row = await database.get(
            `SELECT COUNT(*) AS total FROM (${AccessAudit.consolidatedSql()}) audit
             ${where.length ? `WHERE ${where.join(' AND ')}` : ''}`,
            params
        );
        return row ? row.total : 0;
    }
}

module.exports = AccessAudit;
