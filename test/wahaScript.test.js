const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const path = require('node:path');
const { spawn } = require('node:child_process');
const {
    getPowerShellExecutable,
    buildPowerShellCommandArgs
} = require('../src/services/powerShellRunner');

function sendJson(response, statusCode, body) {
    response.writeHead(statusCode, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify(body));
}

function listenOnValidationPort(server, port = 3100) {
    return new Promise((resolve, reject) => {
        const handleError = (error) => {
            server.off('listening', handleListening);
            if (error.code === 'EADDRINUSE' && port < 3199) {
                resolve(listenOnValidationPort(server, port + 1));
                return;
            }
            reject(error);
        };
        const handleListening = () => {
            server.off('error', handleError);
            resolve(port);
        };

        server.once('error', handleError);
        server.once('listening', handleListening);
        server.listen(port, '127.0.0.1');
    });
}

function closeServer(server) {
    return new Promise((resolve, reject) => {
        server.close((error) => (error ? reject(error) : resolve()));
    });
}

function runWahaScript(baseUrl, destination, message) {
    const scriptPath = path.resolve(__dirname, '..', 'scripts-ps', 'Test-WahaWhatsApp.ps1');
    const scriptArgs = [
        '-ApiKey', 'chave-de-teste',
        '-Destino', destination,
        '-Mensagem', message,
        '-Session', 'default',
        '-WahaUrl', baseUrl,
        '-TimeoutSeconds', '5'
    ];

    return new Promise((resolve, reject) => {
        const process = spawn(
            getPowerShellExecutable(),
            buildPowerShellCommandArgs(scriptPath, scriptArgs),
            { windowsHide: true }
        );
        let stdout = '';
        let stderr = '';

        process.stdout.on('data', (data) => { stdout += data.toString('utf8'); });
        process.stderr.on('data', (data) => { stderr += data.toString('utf8'); });
        process.on('error', reject);
        process.on('close', (code) => resolve({ code, stdout, stderr }));
    });
}

test('valida sessão, resolve chatId e apresenta o detalhe de erros do WAHA', async () => {
    const requests = [];
    const server = http.createServer((request, response) => {
        const url = new URL(request.url, 'http://127.0.0.1');
        requests.push({ method: request.method, url });

        if (request.method === 'GET' && url.pathname === '/api/sessions/default') {
            sendJson(response, 200, { name: 'default', status: 'WORKING' });
            return;
        }

        if (request.method === 'GET' && url.pathname === '/api/contacts/check-exists') {
            sendJson(response, 200, {
                numberExists: true,
                chatId: '5511999999998@c.us'
            });
            return;
        }

        if (request.method === 'POST' && url.pathname === '/api/sendText') {
            let requestBody = '';
            request.on('data', (chunk) => { requestBody += chunk.toString('utf8'); });
            request.on('end', () => {
                const body = JSON.parse(requestBody);
                requests[requests.length - 1].body = body;
                if (body.text === 'Forçar HTTP 422') {
                    sendJson(response, 422, {
                        error: 'Session status is not as expected',
                        status: 'FAILED',
                        expected: ['WORKING']
                    });
                    return;
                }
                sendJson(response, 200, { id: { _serialized: 'message-id-test' } });
            });
            return;
        }

        sendJson(response, 404, { error: 'Not found' });
    });

    const port = await listenOnValidationPort(server);
    const baseUrl = `http://127.0.0.1:${port}`;

    try {
        const success = await runWahaScript(baseUrl, '5511999999999', 'Olá, amigo.');
        assert.equal(success.code, 0);
        assert.equal(success.stderr, '');
        assert.match(success.stdout, /message-id-test/);

        const sentRequest = requests.find((request) =>
            request.method === 'POST' && request.body && request.body.text === 'Olá, amigo.'
        );
        assert.ok(sentRequest);
        assert.equal(sentRequest.body.session, 'default');
        assert.equal(sentRequest.body.chatId, '5511999999998@c.us');

        const failure = await runWahaScript(baseUrl, '5511999999998@c.us', 'Forçar HTTP 422');
        assert.equal(failure.code, 1);
        assert.match(failure.stderr, /HTTP 422/);
        assert.match(failure.stderr, /Session status is not as expected/);
        assert.doesNotMatch(failure.stderr, /chave-de-teste/);
    }
    finally {
        await closeServer(server);
    }
});
