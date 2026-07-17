const { collectRuntimeEnvironment } = require('../services/runtimeEnvironmentService');

class RuntimeEnvironmentController {
    static async show(req, res) {
        res.set('Cache-Control', 'no-store');

        try {
            const runtimeEnvironment = await collectRuntimeEnvironment();
            res.render('runtime-environment', {
                runtimeEnvironment,
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            console.error('Erro ao carregar o ambiente de execucao:', error.message || error);
            req.flash('error', 'Nao foi possivel carregar o ambiente de execucao.');
            res.redirect('/');
        }
    }
}

module.exports = RuntimeEnvironmentController;
