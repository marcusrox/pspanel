const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const databaseDir = path.join(__dirname, '../../database');
const databasePath = path.join(databaseDir, 'pspanel.sqlite');

if (!fs.existsSync(databaseDir)) {
    fs.mkdirSync(databaseDir, { recursive: true });
}

const db = new sqlite3.Database(databasePath);

function run(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.run(sql, params, function (err) {
            if (err) return reject(err);
            resolve({ lastID: this.lastID, changes: this.changes });
        });
    });
}

function get(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.get(sql, params, (err, row) => (err ? reject(err) : resolve(row)));
    });
}

function all(sql, params = []) {
    return new Promise((resolve, reject) => {
        db.all(sql, params, (err, rows) => (err ? reject(err) : resolve(rows || [])));
    });
}

function exec(sql) {
    return new Promise((resolve, reject) => {
        db.exec(sql, (err) => (err ? reject(err) : resolve()));
    });
}

async function configure() {
    await exec(`
        PRAGMA foreign_keys = ON;
        PRAGMA busy_timeout = 5000;
        PRAGMA journal_mode = WAL;
    `);
}

module.exports = {
    db,
    databaseDir,
    databasePath,
    configure,
    run,
    get,
    all,
    exec
};
