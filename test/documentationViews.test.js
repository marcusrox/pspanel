const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');
const ejs = require('ejs');

const projectRoot = path.join(__dirname, '..');

function extractInlineScripts(html) {
    return Array.from(html.matchAll(/<script>([\s\S]*?)<\/script>/g), (match) => match[1]);
}

test('compila e renderiza página de documentação com abas, busca e links na mesma aba', async () => {
    const filename = path.join(projectRoot, 'views', 'documentation.ejs');
    const template = fs.readFileSync(filename, 'utf8');
    assert.doesNotThrow(() => ejs.compile(template, { filename }));

    const baseDocument = {
        title: 'Documento',
        fileName: 'DOCUMENTO.md',
        description: 'Descrição segura.',
        id: 'documento'
    };
    const html = await ejs.renderFile(filename, {
        catalog: {
            operations: [{ ...baseDocument, id: 'readme', fileName: 'README.md' }],
            development: [{ ...baseDocument, id: 'architecture', fileName: 'architecture.md' }],
            tasks: [{
                ...baseDocument,
                id: 'task-063-exemplo',
                fileName: 'TASK-063-exemplo.md',
                number: 63,
                title: 'TASK-063 - Exemplo'
            }],
            tasksUnavailable: false
        },
        activeView: 'development',
        messages: { error: [], success: [], info: [] },
        user: { username: 'test', displayName: 'Test', email: '' },
        ui: { fontScale: '100' }
    });

    assert.match(html, /aria-selected="true"[\s\S]*data-documentation-tab="development"/);
    assert.match(html, /id="taskSearch"/);
    assert.match(html, /href="\/documentation\/view\/task-063-exemplo"/);
    assert.doesNotMatch(html, /target="_blank"/);
    extractInlineScripts(html).forEach((script) => {
        assert.doesNotThrow(() => new Function(script));
    });
});

test('compila visualizador e mantém HTML Markdown renderizado', async () => {
    const filename = path.join(projectRoot, 'views', 'markdown-viewer.ejs');
    const template = fs.readFileSync(filename, 'utf8');
    assert.doesNotThrow(() => ejs.compile(template, { filename }));

    const html = await ejs.renderFile(filename, {
        document: {
            title: 'Documento',
            fileName: 'README.md',
            section: 'operations',
            html: '<h1 id="documento">Documento</h1>'
        },
        statusCode: 200,
        errorMessage: null,
        user: { username: 'test', displayName: 'Test', email: '' },
        messages: { error: [], success: [], info: [] },
        release: { version: 'v2026.08.24-001' },
        ui: { fontScale: '100' }
    });

    assert.match(html, /<article class="markdown-body"><h1 id="documento">Documento<\/h1><\/article>/);
    assert.match(html, /id="backToPreviousPage"/);
    assert.match(html, /Visualização do arquivo README\.md\./);
    assert.match(html, /PSPanel foi feito com/);
    extractInlineScripts(html).forEach((script) => {
        assert.doesNotThrow(() => new Function(script));
    });
});
