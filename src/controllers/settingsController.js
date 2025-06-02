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
            const updates = req.body;
            
            // Validar diretórios
            if (updates['scripts.directory']) {
                if (!updates['scripts.directory'].trim()) {
                    throw new Error('O diretório de scripts não pode estar vazio');
                }
            }

            if (updates['scripts.log_directory']) {
                if (!updates['scripts.log_directory'].trim()) {
                    throw new Error('O diretório de logs não pode estar vazio');
                }
            }

            // Validar tempo máximo de execução
            if (updates['scripts.max_execution_time']) {
                const maxTime = parseInt(updates['scripts.max_execution_time']);
                if (isNaN(maxTime) || maxTime < 1) {
                    throw new Error('Tempo máximo de execução deve ser maior que 0');
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