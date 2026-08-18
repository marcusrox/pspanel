const test = require('node:test');
const assert = require('node:assert/strict');
const { isAuthenticated } = require('../src/middleware/authMiddleware');
const { isLocalAdmin, isLocalAdministrator } = require('../src/middleware/adminMiddleware');
const { createRequest, createResponse } = require('../test-support/testUtils');

test('middleware nega rota operacional sem sessao e apresenta mensagem', () => {
    const request = createRequest({ session: {} });
    const response = createResponse();
    let nextCalled = false;

    isAuthenticated(request, response, () => { nextCalled = true; });

    assert.equal(nextCalled, false);
    assert.equal(response.redirectedTo, '/login');
    assert.deepEqual(request.flashes, [{
        type: 'error',
        message: 'Por favor, faça login para acessar esta página'
    }]);
});

test('middleware permite rota operacional para usuario autenticado', () => {
    const request = createRequest();
    const response = createResponse();
    let nextCalled = false;

    isAuthenticated(request, response, () => { nextCalled = true; });

    assert.equal(nextCalled, true);
    assert.equal(response.finished, false);
});

test('area administrativa aceita somente o administrador local configurado', (t) => {
    const originalAdmin = process.env.ADMIN_USER;
    process.env.ADMIN_USER = 'Administrador';
    t.after(() => {
        if (originalAdmin === undefined) delete process.env.ADMIN_USER;
        else process.env.ADMIN_USER = originalAdmin;
    });

    assert.equal(isLocalAdministrator({ username: 'administrador', type: 'local' }), true);
    assert.equal(isLocalAdministrator({ username: 'administrador', type: 'ldap' }), false);

    const response = createResponse();
    let nextCalled = false;
    isLocalAdmin(
        createRequest({ session: { user: { username: 'outro', type: 'local' } } }),
        response,
        () => { nextCalled = true; }
    );

    assert.equal(nextCalled, false);
    assert.equal(response.statusCode, 403);
    assert.equal(response.view, 'error');
});
