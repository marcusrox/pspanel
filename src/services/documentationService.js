const fs = require('fs').promises;
const path = require('path');
const MarkdownIt = require('markdown-it');

const FIXED_DOCUMENTS = [
    {
        id: 'readme',
        section: 'operations',
        title: 'Visão geral',
        fileName: 'README.md',
        relativePath: 'README.md',
        description: 'Visão geral do PS Panel, suas funcionalidades, tecnologias e configuração básica.'
    },
    {
        id: 'install',
        section: 'operations',
        title: 'Instalação',
        fileName: 'INSTALL.md',
        relativePath: 'INSTALL.md',
        description: 'Procedimento homologado para instalar e preparar o PS Panel em produção.'
    },
    {
        id: 'update',
        section: 'operations',
        title: 'Atualização',
        fileName: 'UPDATE.md',
        relativePath: 'UPDATE.md',
        description: 'Runbook enxuto para publicar releases, atualizar o ambiente e executar rollback.'
    },
    {
        id: 'architecture',
        section: 'development',
        title: 'Arquitetura',
        fileName: 'architecture.md',
        relativePath: path.join('docs', 'architecture.md'),
        description: 'Arquitetura, fluxos, persistência e decisões técnicas do PS Panel.'
    },
    {
        id: 'patterns',
        section: 'development',
        title: 'Padrões do projeto',
        fileName: 'patterns.md',
        relativePath: path.join('docs', 'patterns.md'),
        description: 'Padrões de implementação, segurança e validação adotados no projeto.'
    }
];

const TASK_FILE_PATTERN = /^TASK-(\d+)-[A-Za-z0-9][A-Za-z0-9-]*\.md$/;
const DOCUMENT_ID_PATTERN = /^[a-z0-9][a-z0-9-]*$/;

class DocumentationError extends Error {
    constructor(code, message) {
        super(message);
        this.name = 'DocumentationError';
        this.code = code;
    }
}

function getProjectRoot() {
    return process.cwd();
}

function getTasksDirectory() {
    return path.resolve(getProjectRoot(), 'docs', 'tasks');
}

function isPathInside(baseDirectory, candidatePath) {
    const relativePath = path.relative(baseDirectory, candidatePath);
    return relativePath !== ''
        && !relativePath.startsWith(`..${path.sep}`)
        && relativePath !== '..'
        && !path.isAbsolute(relativePath);
}

function toPlainText(value) {
    return String(value || '')
        .replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
        .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
        .replace(/[`*_~]/g, '')
        .replace(/\s+/g, ' ')
        .trim();
}

function extractSectionParagraph(content, sectionName) {
    const lines = String(content || '').split(/\r?\n/);
    const headingPattern = new RegExp(`^##\\s+${sectionName}\\s*$`, 'i');
    const startIndex = lines.findIndex((line) => headingPattern.test(line.trim()));

    if (startIndex === -1) return '';

    const paragraph = [];
    let started = false;
    for (let index = startIndex + 1; index < lines.length; index += 1) {
        const line = lines[index].trim();
        if (/^#{1,6}\s+/.test(line)) break;
        if (!line) {
            if (started) break;
            continue;
        }
        if (/^(```|~~~)/.test(line)) break;
        started = true;
        paragraph.push(line.replace(/^[-*+]\s+/, ''));
    }

    return toPlainText(paragraph.join(' '));
}

function titleFromFileName(fileName) {
    return path.basename(fileName, '.md')
        .replace(/-/g, ' ')
        .replace(/\btask\b/i, 'TASK');
}

function parseDocumentMetadata(content, fileName) {
    const titleMatch = String(content || '').match(/^#\s+(.+)$/m);
    const title = toPlainText(titleMatch ? titleMatch[1] : titleFromFileName(fileName));
    const description = extractSectionParagraph(content, 'Objetivo')
        || extractSectionParagraph(content, 'Contexto')
        || 'Documento de planejamento e acompanhamento técnico do PS Panel.';

    return { title, description };
}

function createFixedDocument(definition) {
    return {
        ...definition,
        absolutePath: path.resolve(getProjectRoot(), definition.relativePath)
    };
}

async function listTaskDocuments() {
    const tasksDirectory = getTasksDirectory();
    let entries;

    try {
        entries = await fs.readdir(tasksDirectory, { withFileTypes: true });
    } catch (error) {
        if (error.code === 'ENOENT' || error.code === 'ENOTDIR' || error.code === 'EACCES') {
            return { tasks: [], unavailable: true };
        }
        throw error;
    }

    const taskEntries = entries.filter((entry) => entry.isFile() && TASK_FILE_PATTERN.test(entry.name));
    const tasks = await Promise.all(taskEntries.map(async (entry) => {
        const match = entry.name.match(TASK_FILE_PATTERN);
        const absolutePath = path.resolve(tasksDirectory, entry.name);
        if (!isPathInside(tasksDirectory, absolutePath)) return null;

        let metadata;
        try {
            const content = await fs.readFile(absolutePath, 'utf8');
            metadata = parseDocumentMetadata(content, entry.name);
        } catch (error) {
            metadata = {
                title: titleFromFileName(entry.name),
                description: 'Não foi possível carregar a descrição desta task.'
            };
        }

        return {
            id: path.basename(entry.name, '.md').toLowerCase(),
            section: 'tasks',
            fileName: entry.name,
            relativePath: path.join('docs', 'tasks', entry.name),
            absolutePath,
            number: Number.parseInt(match[1], 10),
            ...metadata
        };
    }));

    return {
        tasks: tasks.filter(Boolean).sort((left, right) => right.number - left.number),
        unavailable: false
    };
}

async function listDocumentationCatalog() {
    const fixedDocuments = FIXED_DOCUMENTS.map(createFixedDocument);
    const taskResult = await listTaskDocuments();

    return {
        operations: fixedDocuments.filter((document) => document.section === 'operations'),
        development: fixedDocuments.filter((document) => document.section === 'development'),
        tasks: taskResult.tasks,
        tasksUnavailable: taskResult.unavailable
    };
}

async function getCatalogDocuments() {
    const catalog = await listDocumentationCatalog();
    return [...catalog.operations, ...catalog.development, ...catalog.tasks];
}

async function findDocumentById(documentId) {
    if (typeof documentId !== 'string' || !DOCUMENT_ID_PATTERN.test(documentId)) {
        return null;
    }

    const documents = await getCatalogDocuments();
    return documents.find((document) => document.id === documentId) || null;
}

function normalizeComparablePath(filePath) {
    const normalized = path.normalize(filePath);
    return process.platform === 'win32' ? normalized.toLowerCase() : normalized;
}

function resolveKnownDocumentLink(href, currentDocument, documents) {
    if (!href || href.startsWith('#')) return null;

    const [pathPart, hashPart] = href.split('#', 2);
    if (!pathPart || pathPart.includes('?')) return null;

    let decodedPath;
    try {
        decodedPath = decodeURIComponent(pathPart);
    } catch (error) {
        return null;
    }

    const resolvedPath = normalizeComparablePath(path.resolve(path.dirname(currentDocument.absolutePath), decodedPath));
    const target = documents.find((document) => normalizeComparablePath(document.absolutePath) === resolvedPath);
    if (!target) return null;

    let hash = '';
    if (hashPart) {
        try {
            hash = `#${encodeURIComponent(decodeURIComponent(hashPart))}`;
        } catch (error) {
            return null;
        }
    }
    return `/documentation/view/${encodeURIComponent(target.id)}${hash}`;
}

function slugifyHeading(value) {
    return String(value || '')
        .trim()
        .toLocaleLowerCase('pt-BR')
        .replace(/[^\p{L}\p{N}\s-]/gu, '')
        .replace(/\s+/g, '-')
        .replace(/-+/g, '-');
}

function createMarkdownRenderer(currentDocument, documents) {
    const markdown = new MarkdownIt({
        html: false,
        linkify: true,
        typographer: false
    });

    markdown.renderer.rules.heading_open = (tokens, index, options, env, renderer) => {
        const titleToken = tokens[index + 1];
        const baseSlug = slugifyHeading(titleToken && titleToken.content) || 'secao';
        env.headingSlugs = env.headingSlugs || new Map();
        const count = env.headingSlugs.get(baseSlug) || 0;
        env.headingSlugs.set(baseSlug, count + 1);
        tokens[index].attrSet('id', count ? `${baseSlug}-${count}` : baseSlug);
        return renderer.renderToken(tokens, index, options);
    };

    markdown.renderer.rules.link_open = (tokens, index, options, env, renderer) => {
        const href = tokens[index].attrGet('href') || '';
        env.linkTags = env.linkTags || [];

        if (href.startsWith('#')) {
            env.linkTags.push('a');
            return renderer.renderToken(tokens, index, options);
        }

        if (/^(https?:|mailto:)/i.test(href) && markdown.validateLink(href)) {
            env.linkTags.push('a');
            return renderer.renderToken(tokens, index, options);
        }

        const knownTarget = resolveKnownDocumentLink(href, currentDocument, documents);
        if (knownTarget) {
            tokens[index].attrSet('href', knownTarget);
            env.linkTags.push('a');
            return renderer.renderToken(tokens, index, options);
        }

        env.linkTags.push('span');
        return '<span class="markdown-disabled-link" title="Documento local não disponível neste visualizador">';
    };

    markdown.renderer.rules.link_close = (tokens, index, options, env) => {
        const tagName = env.linkTags && env.linkTags.pop();
        return tagName === 'span' ? '</span>' : '</a>';
    };

    return markdown;
}

async function renderDocument(documentId) {
    const document = await findDocumentById(documentId);
    if (!document) return null;

    let content;
    try {
        content = await fs.readFile(document.absolutePath, 'utf8');
    } catch (error) {
        if (error.code === 'ENOENT' || error.code === 'ENOTDIR') return null;
        throw new DocumentationError('READ_ERROR', 'Não foi possível ler o documento solicitado.');
    }

    const documents = await getCatalogDocuments();
    const metadata = parseDocumentMetadata(content, document.fileName);
    const markdown = createMarkdownRenderer(document, documents);

    return {
        ...document,
        title: metadata.title,
        html: markdown.render(content, {})
    };
}

module.exports = {
    DocumentationError,
    extractSectionParagraph,
    findDocumentById,
    listDocumentationCatalog,
    parseDocumentMetadata,
    renderDocument
};
