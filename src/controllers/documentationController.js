const {
    DocumentationError,
    listDocumentationCatalog,
    renderDocument
} = require('../services/documentationService');

function setNoStore(res) {
    res.set('Cache-Control', 'no-store');
}

class DocumentationController {
    static async show(req, res) {
        setNoStore(res);

        try {
            const catalog = await listDocumentationCatalog();
            const activeView = req.query.view === 'development' ? 'development' : 'operations';
            return res.render('documentation', {
                catalog,
                activeView,
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            console.error('Erro ao carregar o catálogo de documentação:', error);
            req.flash('error', 'Não foi possível carregar a documentação.');
            return res.redirect('/');
        }
    }

    static async view(req, res) {
        setNoStore(res);

        try {
            const document = await renderDocument(req.params.documentId);
            if (!document) {
                return res.status(404).render('markdown-viewer', {
                    document: null,
                    statusCode: 404,
                    errorMessage: 'O documento solicitado não existe ou não está mais disponível.',
                    user: req.session.user,
                    messages: res.locals.messages
                });
            }

            return res.render('markdown-viewer', {
                document,
                statusCode: 200,
                errorMessage: null,
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            if (!(error instanceof DocumentationError)) {
                console.error('Erro ao abrir documento Markdown:', error);
            }

            return res.status(500).render('markdown-viewer', {
                document: null,
                statusCode: 500,
                errorMessage: 'Não foi possível abrir o documento. Tente novamente mais tarde.',
                user: req.session.user,
                messages: res.locals.messages
            });
        }
    }
}

module.exports = DocumentationController;
