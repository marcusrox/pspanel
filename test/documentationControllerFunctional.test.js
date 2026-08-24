const test = require('node:test');
const assert = require('node:assert/strict');
const {
    createRequest,
    createResponse,
    freshRequire,
    getRouteHandler,
    installModuleMock,
    projectPath
} = require('../test-support/testUtils');

function loadRouter(t, service) {
    const restoreService = installModuleMock(
        projectPath('src', 'services', 'documentationService.js'),
        service
    );

    t.after(() => {
        delete require.cache[require.resolve('../src/routes/documentationRoutes')];
        delete require.cache[require.resolve('../src/controllers/documentationController')];
        restoreService();
    });

    return freshRequire(projectPath('src', 'routes', 'documentationRoutes.js'));
}

function createService(overrides = {}) {
    class DocumentationError extends Error {}
    return {
        DocumentationError,
        listDocumentationCatalog: async () => ({ operations: [], development: [], tasks: [], tasksUnavailable: false }),
        renderDocument: async () => ({ id: 'readme', title: 'PS Panel', fileName: 'README.md', html: '<h1>PS Panel</h1>' }),
        ...overrides
    };
}

test('página de documentação normaliza aba e envia catálogo para a view', async (t) => {
    const catalog = { operations: [{ id: 'readme' }], development: [], tasks: [], tasksUnavailable: false };
    const router = loadRouter(t, createService({ listDocumentationCatalog: async () => catalog }));
    const response = createResponse();

    await getRouteHandler(router, 'get', '/')(createRequest({ query: { view: 'development' } }), response);

    assert.equal(response.view, 'documentation');
    assert.equal(response.body.catalog, catalog);
    assert.equal(response.body.activeView, 'development');
    assert.equal(response.headers['cache-control'], 'no-store');
});

test('visualizador renderiza documento conhecido sem cache', async (t) => {
    const document = { id: 'readme', title: 'PS Panel', fileName: 'README.md', html: '<h1>PS Panel</h1>' };
    const router = loadRouter(t, createService({ renderDocument: async () => document }));
    const response = createResponse();

    await getRouteHandler(router, 'get', '/view/:documentId')(
        createRequest({ params: { documentId: 'readme' } }),
        response
    );

    assert.equal(response.statusCode, 200);
    assert.equal(response.view, 'markdown-viewer');
    assert.equal(response.body.document, document);
    assert.equal(response.headers['cache-control'], 'no-store');
});

test('visualizador responde 404 para identificador desconhecido', async (t) => {
    const router = loadRouter(t, createService({ renderDocument: async () => null }));
    const response = createResponse();

    await getRouteHandler(router, 'get', '/view/:documentId')(
        createRequest({ params: { documentId: '../segredo' } }),
        response
    );

    assert.equal(response.statusCode, 404);
    assert.equal(response.view, 'markdown-viewer');
    assert.equal(response.body.document, null);
    assert.doesNotMatch(response.body.errorMessage, /[A-Z]:\\|docs[\\/]/);
});

test('visualizador responde erro amigável quando leitura falha', async (t) => {
    const originalConsoleError = console.error;
    console.error = () => {};
    t.after(() => { console.error = originalConsoleError; });
    const router = loadRouter(t, createService({
        renderDocument: async () => { throw new Error('C:\\caminho\\interno'); }
    }));
    const response = createResponse();

    await getRouteHandler(router, 'get', '/view/:documentId')(
        createRequest({ params: { documentId: 'readme' } }),
        response
    );

    assert.equal(response.statusCode, 500);
    assert.equal(response.view, 'markdown-viewer');
    assert.equal(response.body.errorMessage.includes('caminho'), false);
});
