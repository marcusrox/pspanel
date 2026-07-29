function getPowerShellExecutable() {
    return 'pwsh.exe';
}

function buildPowerShellCommandArgs(scriptPath, argList, options = {}) {
    const args = ['-NoProfile'];

    if (options.executionPolicy) {
        args.push('-ExecutionPolicy', options.executionPolicy);
    }

    args.push('-File', scriptPath, ...(argList || []));
    return args;
}

function isPowerShellExecutionSuccessful(code, stderr) {
    return code === 0 && !String(stderr || '').trim();
}

module.exports = {
    getPowerShellExecutable,
    buildPowerShellCommandArgs,
    isPowerShellExecutionSuccessful
};
