const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const scriptPath = path.join(
    __dirname,
    '..',
    'scripts-ps',
    'Relatorio-IndicesFullText-SQLServer.ps1'
);
const script = fs.readFileSync(scriptPath, 'utf8');

test('relatorio Full-Text possui ajuda e valores operacionais padrao', () => {
    assert.match(script, /^#requires -Version 5\.1/m);
    for (const section of ['.SYNOPSIS', '.DESCRIPTION', '.PARAMETER SqlServer', '.PARAMETER MailTo', '.EXAMPLE', '.INPUTS', '.OUTPUTS', '.NOTES']) {
        assert.ok(script.includes(section), `secao ausente: ${section}`);
    }
    assert.match(script, /\[string\]\$SqlServer\s*=\s*'SERV01D'/);
    assert.match(script, /dba@desenbahia\.ba\.gov\.br/);
});

test('relatorio Full-Text usa conexao integrada, criptografada e somente leitura', () => {
    assert.match(script, /\['Data Source'\]\s*=\s*\$Server/);
    assert.match(script, /\['Initial Catalog'\]\s*=\s*\$Database/);
    assert.match(script, /\['Integrated Security'\]\s*=\s*\$true/);
    assert.match(script, /\['Encrypt'\]\s*=\s*\$true/);
    assert.match(script, /\['TrustServerCertificate'\]\s*=\s*\$true/);
    assert.doesNotMatch(script, /\.DataSource\s*=/);
    assert.match(script, /VIEW ANY DATABASE/);
    assert.match(script, /FULLTEXTSERVICEPROPERTY\('IsFullTextInstalled'\)/);
    assert.match(script, /HAS_DBACCESS\(name\)/);
    assert.match(script, /sys\.fulltext_indexes/);
    assert.match(script, /sys\.fulltext_index_columns/);
    assert.match(script, /Write-Output -NoEnumerate \$table/);
    assert.doesNotMatch(script, /sp_MSforeachdb/i);
    assert.doesNotMatch(script, /Send-MailMessage|System\.Net\.Mail\.SmtpClient/);
    assert.doesNotMatch(script, /\b(?:INSERT|UPDATE|DELETE|MERGE|DROP|ALTER|CREATE)\b\s+(?:TABLE|INDEX|FULLTEXT|DATABASE)/i);
});

test('relatorio Full-Text envia email apenas depois de encontrar indices', () => {
    const emptyResultCheck = script.indexOf("if ($indexes.Count -eq 0)");
    const moduleImport = script.indexOf('Import-Module $emailModulePath');
    const sendEmail = script.indexOf('Send-PSPanelEmail -To $MailTo');

    assert.ok(emptyResultCheck >= 0);
    assert.ok(moduleImport > emptyResultCheck);
    assert.ok(sendEmail > moduleImport);
    assert.match(script, /Email enviado: nao/);
    assert.match(script, /Email enviado: sim/);
});
