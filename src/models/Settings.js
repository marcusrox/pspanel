const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const db = new sqlite3.Database(path.join(__dirname, '../../database/database.sqlite'));

class Settings {
    static async initialize() {
        return new Promise((resolve, reject) => {
            db.run(`
                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value TEXT,
                    description TEXT
                )
            `, async (err) => {
                if (err) {
                    reject(err);
                    return;
                }

                // Configurações padrão
                const defaults = {
                    'scripts.directory': 'C:\\Scripts',
                    'scripts.max_execution_time': '3600',
                    'scripts.log_directory': 'C:\\Scripts\\Logs'
                };

                // Inserir configurações padrão se não existirem
                for (const [key, value] of Object.entries(defaults)) {
                    await this.set(key, value);
                }

                resolve();
            });
        });
    }

    static async get(key) {
        return new Promise((resolve, reject) => {
            db.get('SELECT value FROM settings WHERE key = ?', [key], (err, row) => {
                if (err) {
                    reject(err);
                    return;
                }
                resolve(row ? row.value : null);
            });
        });
    }

    static async set(key, value) {
        return new Promise((resolve, reject) => {
            db.run(`
                INSERT OR REPLACE INTO settings (key, value)
                VALUES (?, ?)
            `, [key, value], (err) => {
                if (err) {
                    reject(err);
                    return;
                }
                resolve();
            });
        });
    }

    static async getAll() {
        return new Promise((resolve, reject) => {
            db.all('SELECT * FROM settings', (err, rows) => {
                if (err) {
                    reject(err);
                    return;
                }
                
                // Converter array em objeto
                const settings = {};
                rows.forEach(row => {
                    const [category, name] = row.key.split('.');
                    if (!settings[category]) {
                        settings[category] = {};
                    }
                    settings[category][name] = row.value;
                });
                
                resolve(settings);
            });
        });
    }
}

module.exports = Settings; 