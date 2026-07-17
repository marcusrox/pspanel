const http = require('http');
const { spawn } = require('child_process');

const port = process.env.PORT || 3000;
const baseUrl = `http://localhost:${port}`;
const readinessUrl = `${baseUrl}/login`;
const devLoginUrl = `${baseUrl}/dev-login`;
const nodemonPath = require.resolve('nodemon/bin/nodemon.js');

const nodemon = spawn(process.execPath, [nodemonPath, 'app.js'], {
    env: {
        ...process.env,
        NODE_ENV: 'development',
        DEV_AUTO_LOGIN_LOCAL: 'true'
    },
    stdio: 'inherit'
});

let browserOpened = false;
let attempts = 0;
const maxAttempts = 120;

function openBrowser() {
    let command;
    let args;

    if (process.platform === 'win32') {
        command = 'cmd.exe';
        args = ['/c', 'start', '', devLoginUrl];
    } else if (process.platform === 'darwin') {
        command = 'open';
        args = [devLoginUrl];
    } else {
        command = 'xdg-open';
        args = [devLoginUrl];
    }

    const browser = spawn(command, args, {
        detached: true,
        stdio: 'ignore'
    });

    browser.on('error', (error) => {
        console.error(`Nao foi possivel abrir o navegador automaticamente: ${error.message}`);
        console.log(`Acesse manualmente: ${devLoginUrl}`);
    });

    browser.unref();
}

function waitForServer() {
    if (browserOpened || attempts >= maxAttempts) {
        if (!browserOpened) {
            console.log(`O navegador nao foi aberto porque o servidor nao respondeu. Acesse manualmente: ${devLoginUrl}`);
        }
        return;
    }

    attempts += 1;

    const request = http.get(readinessUrl, (response) => {
        response.resume();
        browserOpened = true;
        openBrowser();
    });

    request.setTimeout(500);
    request.on('timeout', () => request.destroy());
    request.on('error', () => {
        setTimeout(waitForServer, 500);
    });
}

nodemon.on('error', (error) => {
    console.error(`Erro ao iniciar o ambiente de desenvolvimento: ${error.message}`);
    process.exitCode = 1;
});

nodemon.on('exit', (code) => {
    process.exitCode = code ?? 1;
});

waitForServer();
