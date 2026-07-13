const {
    listLogFiles,
    readLogTail,
    selectInitialLogFile,
    OperationalLogError
} = require('../services/operationalLogService');

function setNoStore(res) {
    res.set('Cache-Control', 'no-store');
}

class LogController {
    static async showLogs(req, res) {
        setNoStore(res);

        try {
            const files = await listLogFiles();
            res.render('logs', {
                files,
                selectedFile: selectInitialLogFile(files),
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            console.error('Erro ao listar arquivos de log operacional:', error);
            req.flash('error', 'Erro ao carregar os arquivos de log operacional.');
            res.redirect('/');
        }
    }

    static async getLogContent(req, res) {
        setNoStore(res);

        try {
            const result = await readLogTail(req.query.file, req.query.lines);
            return res.json(result);
        } catch (error) {
            if (error instanceof OperationalLogError) {
                const status = error.code === 'FILE_NOT_FOUND' ? 404 : 400;
                return res.status(status).json({ error: error.message });
            }

            console.error('Erro ao ler arquivo de log operacional:', error);
            return res.status(500).json({ error: 'Erro ao ler o arquivo de log operacional.' });
        }
    }
}

module.exports = LogController;
