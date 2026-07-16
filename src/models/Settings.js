const database = require('../database/connection');
const schema = require('../database/schema');

let initialized = false;

class Settings {
    static async initialize() {
        if (initialized) return;

        await schema.initialize();

        // Configurações padrão
        const defaults = {
            'scripts.max_execution_time': '3600',
            'ui.font_scale': '100',
            'email.daily_summary_recipient': '',
            'email.daily_summary_enabled': '0',
            'email.daily_summary_last_sent_date': '',
            'email.daily_summary_last_sent_at': ''
        };

        // Inserir configurações padrão se não existirem
        for (const [key, value] of Object.entries(defaults)) {
            await this.setDefault(key, value);
        }

        initialized = true;
    }

    static async get(key) {
        await Settings.initialize();
        const row = await database.get('SELECT value FROM settings WHERE key = ?', [key]);
        return row ? row.value : null;
    }

    static async set(key, value) {
        await Settings.initialize();
        await database.run(`
            INSERT OR REPLACE INTO settings (key, value)
            VALUES (?, ?)
        `, [key, value]);
    }

    static async setDefault(key, value) {
        await schema.initialize();
        await database.run(`
            INSERT OR IGNORE INTO settings (key, value)
            VALUES (?, ?)
        `, [key, value]);
    }

    static async getAll() {
        await Settings.initialize();
        const rows = await database.all('SELECT * FROM settings');

        // Converter array em objeto
        const settings = {};
        rows.forEach(row => {
            const [category, name] = row.key.split('.');
            if (!settings[category]) {
                settings[category] = {};
            }
            settings[category][name] = row.value;
        });

        return settings;
    }
}

module.exports = Settings; 
