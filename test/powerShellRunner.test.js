const test = require('node:test');
const assert = require('node:assert/strict');
const {
    getPowerShellExecutable,
    buildPowerShellCommandArgs,
    isPowerShellExecutionSuccessful
} = require('../src/services/powerShellRunner');

test('executa scripts com -File e preserva argumentos com espaços e acentos', () => {
    const args = buildPowerShellCommandArgs(
        'C:\\Projects\\PSPanel\\scripts-ps\\Teste.ps1',
        ['-Mensagem', 'Olá, amigo.', '-TimeoutSeconds', '30']
    );

    assert.equal(getPowerShellExecutable(), 'pwsh.exe');
    assert.deepEqual(args, [
        '-NoProfile',
        '-File',
        'C:\\Projects\\PSPanel\\scripts-ps\\Teste.ps1',
        '-Mensagem',
        'Olá, amigo.',
        '-TimeoutSeconds',
        '30'
    ]);
});

test('mantém ExecutionPolicy antes de -File para execuções agendadas', () => {
    const args = buildPowerShellCommandArgs(
        'C:\\Projects\\PSPanel\\scripts-ps\\Teste.ps1',
        ['-Name', 'PS Panel'],
        { executionPolicy: 'Bypass' }
    );

    assert.deepEqual(args, [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        'C:\\Projects\\PSPanel\\scripts-ps\\Teste.ps1',
        '-Name',
        'PS Panel'
    ]);
});

test('considera stderr como falha mesmo quando o processo retorna código zero', () => {
    assert.equal(isPowerShellExecutionSuccessful(0, ''), true);
    assert.equal(isPowerShellExecutionSuccessful(0, 'Write-Error: falha'), false);
    assert.equal(isPowerShellExecutionSuccessful(1, ''), false);
});
