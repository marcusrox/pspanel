const database = require('../database/connection');
const schema = require('../database/schema');

const SCHEDULE_RUN_USERNAME = 'Agendamento (worker)';

class History {
    static async initialize() {
        await schema.initialize();
    }

    static async addEntry(scriptName, parameters, username, options = {}) {
        await History.initialize();
        const normalizedOptions = typeof options === 'string' ? { startTime: options } : (options || {});
        const startTime = normalizedOptions.startTime || new Date().toISOString();
        const result = await database.run(
            `INSERT INTO script_history (
                script_name, parameters, username, start_time,
                user_id, auth_type, client_ip, execution_source
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
            [
                scriptName,
                parameters,
                username,
                startTime,
                Number.isInteger(Number(normalizedOptions.userId)) && Number(normalizedOptions.userId) > 0
                    ? Number(normalizedOptions.userId)
                    : null,
                normalizedOptions.authType || null,
                normalizedOptions.clientIp || null,
                normalizedOptions.executionSource || null
            ]
        );
        return result.lastID;
    }

    static async updateEntry(id, output, status, errorMessage = null, endTime = new Date().toISOString()) {
        await History.initialize();
        const result = await database.run(
            'UPDATE script_history SET output = ?, status = ?, error_message = ?, end_time = ? WHERE id = ?',
            [output, status, errorMessage, endTime, id]
        );
        return result.changes;
    }

    static async getHistory(limit = 100, offset = 0) {
        await History.initialize();
        return database.all(
            `SELECT * FROM script_history 
            ORDER BY start_time DESC 
            LIMIT ? OFFSET ?`,
            [limit, offset]
        );
    }

    static async countHistory() {
        await History.initialize();
        const row = await database.get('SELECT COUNT(*) AS total FROM script_history');
        return row.total;
    }

    static async getEntryById(id) {
        await History.initialize();
        return database.get('SELECT * FROM script_history WHERE id = ?', [id]);
    }

    static async searchHistory(query, limit = 100, offset = 0) {
        await History.initialize();
        const searchTerm = `%${query}%`;
        return database.all(
            `SELECT * FROM script_history 
            WHERE script_name LIKE ? 
            OR parameters LIKE ? 
            OR username LIKE ? 
            ORDER BY start_time DESC 
            LIMIT ? OFFSET ?`,
            [searchTerm, searchTerm, searchTerm, limit, offset]
        );
    }

    static async countSearchHistory(query) {
        await History.initialize();
        const searchTerm = `%${query}%`;
        const row = await database.get(
            `SELECT COUNT(*) AS total FROM script_history
            WHERE script_name LIKE ?
            OR parameters LIKE ?
            OR username LIKE ?`,
            [searchTerm, searchTerm, searchTerm]
        );
        return row.total;
    }

    static async findScheduledRunsByDate(date) {
        await History.initialize();
        return database.all(
            `SELECT id, script_name, parameters, username, start_time, end_time, output, status, error_message
             FROM script_history
             WHERE username = ?
             AND date(start_time, 'localtime') = ?
             ORDER BY datetime(start_time) ASC, id ASC`,
            [SCHEDULE_RUN_USERNAME, date]
        );
    }

    static async findByUser(userId, limit = 50) {
        await History.initialize();
        return database.all(
            `SELECT * FROM script_history
             WHERE user_id = ?
             ORDER BY start_time DESC, id DESC
             LIMIT ?`,
            [userId, limit]
        );
    }
}

module.exports = History; 
