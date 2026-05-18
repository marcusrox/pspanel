const POWERSHELL_UTF8_COMMAND = [
    '& {',
    'param([string]$scriptPath);',
    '$utf8NoBom = [System.Text.UTF8Encoding]::new($false);',
    '[Console]::OutputEncoding = $utf8NoBom;',
    '$OutputEncoding = $utf8NoBom;',
    '& $scriptPath @args;',
    '}'
].join(' ');

function getPowerShellExecutable() {
    return 'pwsh.exe';
}

function buildPowerShellCommandArgs(scriptPath, argList, options = {}) {
    const args = ['-NoProfile'];

    if (options.executionPolicy) {
        args.push('-ExecutionPolicy', options.executionPolicy);
    }

    args.push('-Command', POWERSHELL_UTF8_COMMAND, scriptPath, ...(argList || []));
    return args;
}

module.exports = {
    getPowerShellExecutable,
    buildPowerShellCommandArgs
};
