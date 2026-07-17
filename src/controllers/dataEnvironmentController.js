const { collectDataEnvironment } = require('../services/dataEnvironmentService');

class DataEnvironmentController {
    static async show(req, res) {
        res.set('Cache-Control', 'no-store');

        try {
            const dataEnvironment = await collectDataEnvironment();
            res.render('data-environment', {
                dataEnvironment,
                user: req.session.user,
                messages: res.locals.messages
            });
        } catch (error) {
            console.error('Erro ao carregar o ambiente de dados.');
            req.flash('error', 'Nao foi possivel carregar o ambiente de dados.');
            res.redirect('/runtime-environment');
        }
    }
}

module.exports = DataEnvironmentController;
