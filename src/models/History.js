const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const dbPath = path.join(process.cwd(), 'data', 'history.db');

// Ensure the database directory exists
const fs = require('fs');
const dbDir = path.dirname(dbPath);
if (!fs.existsSync(dbDir)) {
    fs.mkdirSync(dbDir, { recursive: true });
}

const db = new sqlite3.Database(dbPath);

// Create history table if it doesn't exist
db.serialize(() => {
    db.run(`CREATE TABLE IF NOT EXISTS script_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_name TEXT NOT NULL,
        parameters TEXT,
        username TEXT NOT NULL,
        start_time DATETIME DEFAULT CURRENT_TIMESTAMP,
        end_time DATETIME,
        output TEXT,
        status TEXT CHECK(status IN ('success', 'error', 'running')) DEFAULT 'running',
        error_message TEXT
    )`);
});

class History {
    static async addEntry(scriptName, parameters, username) {
        return new Promise((resolve, reject) => {
            const stmt = db.prepare('INSERT INTO script_history (script_name, parameters, username) VALUES (?, ?, ?)');
            stmt.run([scriptName, parameters, username], function(err) {
                if (err) reject(err);
                resolve(this.lastID);
            });
            stmt.finalize();
        });
    }

    static async updateEntry(id, output, status, errorMessage = null, endTime = new Date().toISOString()) {
        return new Promise((resolve, reject) => {
            const stmt = db.prepare(
                'UPDATE script_history SET output = ?, status = ?, error_message = ?, end_time = ? WHERE id = ?'
            );
            stmt.run([output, status, errorMessage, endTime, id], function(err) {
                if (err) reject(err);
                resolve(this.changes);
            });
            stmt.finalize();
        });
    }

    static async getHistory(limit = 100, offset = 0) {
        return new Promise((resolve, reject) => {
            db.all(
                `SELECT * FROM script_history 
                ORDER BY start_time DESC 
                LIMIT ? OFFSET ?`,
                [limit, offset],
                (err, rows) => {
                    if (err) reject(err);
                    resolve(rows);
                }
            );
        });
    }

    static async getEntryById(id) {
        return new Promise((resolve, reject) => {
            db.get('SELECT * FROM script_history WHERE id = ?', [id], (err, row) => {
                if (err) reject(err);
                resolve(row);
            });
        });
    }

    static async searchHistory(query, limit = 100, offset = 0) {
        return new Promise((resolve, reject) => {
            const searchTerm = `%${query}%`;
            db.all(
                `SELECT * FROM script_history 
                WHERE script_name LIKE ? 
                OR parameters LIKE ? 
                OR username LIKE ? 
                ORDER BY start_time DESC 
                LIMIT ? OFFSET ?`,
                [searchTerm, searchTerm, searchTerm, limit, offset],
                (err, rows) => {
                    if (err) reject(err);
                    resolve(rows);
                }
            );
        });
    }
}

module.exports = History; 