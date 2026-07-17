const http = require('http');
const { spawn } = require('child_process');

const port = process.env.PORT || 3000;
const url = `http://localhost:${port}/`;
const nodemonPath = require.resolve('nodemon/bin/nodemon.js');

const nodemon = spawn(process.execPath, [nodemonPath, 'app.js'], {
    env: {
        ...process.env,
        NODE_ENV: 'development'
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
        args = ['/c', 'start', '', url];
    } else if (process.platform === 'darwin') {
        command = 'open';
        args = [url];
    } else {
        command = 'xdg-open';
        args = [url];
    }

    const browser = spawn(command, args, {
        detached: true,
        stdio: 'ignore'
    });

    browser.on('error', (error) => {
        console.error(`Nao foi possivel abrir o navegador automaticamente: ${error.message}`);
        console.log(`Acesse manualmente: ${url}`);
    });

    browser.unref();
}

function waitForServer() {
    if (browserOpened || attempts >= maxAttempts) {
        if (!browserOpened) {
            console.log(`O navegador nao foi aberto porque o servidor nao respondeu. Acesse manualmente: ${url}`);
        }
        return;
    }

    attempts += 1;

    const request = http.get(url, (response) => {
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
