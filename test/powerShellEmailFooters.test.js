const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const scriptsRoot = path.join(__dirname, '..', 'scripts-ps');

function listPowerShellFiles(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
        const fullPath = path.join(directory, entry.name);
        if (entry.isDirectory()) return listPowerShellFiles(fullPath);
        return entry.isFile() && entry.name.toLowerCase().endsWith('.ps1') ? [fullPath] : [];
    });
}

test('todo script que envia email identifica o servidor no rodapé HTML', () => {
    const emailScripts = listPowerShellFiles(scriptsRoot).filter((filePath) => (
        fs.readFileSync(filePath, 'utf8').includes('Send-PSPanelEmail')
    ));

    assert.ok(emailScripts.length > 0);

    for (const filePath of emailScripts) {
        const content = fs.readFileSync(filePath, 'utf8');
        assert.match(content, /Servidor:\s*(?:<strong>)?\$\([^\r\n]*\[System\.Environment\]::MachineName/);
    }
});
