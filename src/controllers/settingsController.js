const Settings = require('../models/Settings');

class SettingsController {
    static async showSettings(req, res) {
        try {
            const settings = await Settings.getAll();
            res.render('settings', {
                settings,
                user: req.session.user,
                success: req.flash('success'),
                error: req.flash('error')
            });
        } catch (error) {
            console.error('Erro ao carregar configurações:', error);
            req.flash('error', 'Erro ao carregar configurações');
            res.redirect('/');
        }
    }

    static async updateSettings(req, res) {
        try {
            const allowedSettings = [
                'scripts.max_execution_time',
                'ui.font_scale'
            ];
            const updates = Object.fromEntries(
                Object.entries(req.body).filter(([key]) => allowedSettings.includes(key))
            );

            // Validar tempo máximo de execução
            if (updates['scripts.max_execution_time']) {
                const maxTime = parseInt(updates['scripts.max_execution_time']);
                if (isNaN(maxTime) || maxTime < 1) {
                    throw new Error('Tempo máximo de execução deve ser maior que 0');
                }
            }

            if (updates['ui.font_scale']) {
                const allowedFontScales = ['85', '90', '100', '110'];
                if (!allowedFontScales.includes(updates['ui.font_scale'])) {
                    throw new Error('Tamanho da fonte inválido');
                }
            }

            // Atualizar cada configuração
            for (const [key, value] of Object.entries(updates)) {
                await Settings.set(key, value);
            }
            
            req.flash('success', 'Configurações atualizadas com sucesso');
            res.redirect('/settings');
        } catch (error) {
            console.error('Erro ao atualizar configurações:', error);
            req.flash('error', error.message || 'Erro ao atualizar configurações');
            res.redirect('/settings');
        }
    }
}

module.exports = SettingsController; 
