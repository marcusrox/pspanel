const test = require('node:test');
const assert = require('node:assert/strict');
const nativeFs = require('fs');
const {
    freshRequire,
    patchObject,
    projectPath
} = require('../test-support/testUtils');

function createFileEntry(name) {
    return { name, isFile: () => true };
}

function loadService(t, overrides = {}) {
    const restorePromises = patchObject(nativeFs.promises, {
        readdir: overrides.readdir || nativeFs.promises.readdir,
        readFile: overrides.readFile || nativeFs.promises.readFile
    });

    t.after(() => {
        delete require.cache[require.resolve('../src/services/documentationService')];
        restorePromises();
    });

    return freshRequire(projectPath('src', 'services', 'documentationService.js'));
}

test('catálogo lista documentos fixos e ordena tasks pelo número decrescente', async (t) => {
    const contents = {
        'TASK-002-segunda.md': '# TASK-002 - Segunda\n\n## Objetivo\n\nObjetivo da segunda task.',
        'TASK-010-decima.md': '# TASK-010 - Décima\n\n## Objetivo\n\nObjetivo da décima task.'
    };
    const service = loadService(t, {
        readdir: async () => [
            createFileEntry('anotacoes.txt'),
            createFileEntry('TASK-002-segunda.md'),
            createFileEntry('TASK-010-decima.md')
        ],
        readFile: async (filePath) => contents[filePath.split(/[\\/]/).pop()]
    });

    const catalog = await service.listDocumentationCatalog();

    assert.deepEqual(catalog.operations.map((document) => document.id), ['readme', 'install', 'update']);
    assert.deepEqual(catalog.development.map((document) => document.id), ['architecture', 'patterns']);
    assert.deepEqual(catalog.tasks.map((document) => document.number), [10, 2]);
    assert.equal(catalog.tasks[0].description, 'Objetivo da décima task.');
    assert.equal(catalog.tasksUnavailable, false);
});

test('metadados usam Contexto e descrição genérica como fallback', (t) => {
    const service = loadService(t);
    const withContext = service.parseDocumentMetadata(
        '# TASK-001 - Exemplo\n\n## Contexto\n\nContexto usado como resumo.\n\n## Escopo\n',
        'TASK-001-exemplo.md'
    );
    const withoutSections = service.parseDocumentMetadata('', 'TASK-099-sem-metadados.md');

    assert.equal(withContext.title, 'TASK-001 - Exemplo');
    assert.equal(withContext.description, 'Contexto usado como resumo.');
    assert.equal(withoutSections.description, 'Documento de planejamento e acompanhamento técnico do PS Panel.');
});

test('catálogo mantém documentos fixos quando diretório de tasks está indisponível', async (t) => {
    const service = loadService(t, {
        readdir: async () => {
            const error = new Error('Indisponível');
            error.code = 'EACCES';
            throw error;
        }
    });

    const catalog = await service.listDocumentationCatalog();

    assert.equal(catalog.operations.length, 3);
    assert.deepEqual(catalog.tasks, []);
    assert.equal(catalog.tasksUnavailable, true);
});

test('resolução aceita apenas identificadores presentes no catálogo', async (t) => {
    const service = loadService(t, { readdir: async () => [] });

    assert.equal((await service.findDocumentById('readme')).fileName, 'README.md');
    assert.equal(await service.findDocumentById('../readme'), null);
    assert.equal(await service.findDocumentById('docs/architecture'), null);
    assert.equal(await service.findDocumentById('readme.md'), null);
    assert.equal(await service.findDocumentById('documento-inexistente'), null);
});

test('renderização escapa HTML, bloqueia links perigosos e reescreve documentos conhecidos', async (t) => {
    const markdown = [
        '# Documento',
        '',
        '<script>alert("x")</script>',
        '',
        '[Perigoso](javascript:alert(1))',
        '',
        '[Instalação](INSTALL.md)',
        '',
        '| Coluna | Valor |',
        '| --- | --- |',
        '| Um | `código` |'
    ].join('\n');
    const service = loadService(t, {
        readdir: async () => [],
        readFile: async (filePath) => {
            if (filePath.endsWith('README.md')) return markdown;
            throw Object.assign(new Error('Não encontrado'), { code: 'ENOENT' });
        }
    });

    const rendered = await service.renderDocument('readme');

    assert.match(rendered.html, /&lt;script&gt;alert\(&quot;x&quot;\)&lt;\/script&gt;/);
    assert.doesNotMatch(rendered.html, /<script>/);
    assert.doesNotMatch(rendered.html, /href="javascript:/i);
    assert.match(rendered.html, /href="\/documentation\/view\/install"/);
    assert.doesNotMatch(rendered.html, /target="_blank"/);
    assert.match(rendered.html, /<table>/);
    assert.match(rendered.html, /<code>código<\/code>/);
});

test('renderização retorna nulo quando arquivo conhecido foi removido', async (t) => {
    const service = loadService(t, {
        readdir: async () => [],
        readFile: async () => {
            throw Object.assign(new Error('Não encontrado'), { code: 'ENOENT' });
        }
    });

    assert.equal(await service.renderDocument('readme'), null);
});
