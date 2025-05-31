const express = require('express');
const router = express.Router();
const History = require('../models/History');

// Middleware to check if user is authenticated
const isAuthenticated = (req, res, next) => {
    if (req.session.user) {
        next();
    } else {
        res.redirect('/login');
    }
};

// Get history page
router.get('/', isAuthenticated, async (req, res) => {
    try {
        const page = parseInt(req.query.page) || 1;
        const limit = 20;
        const offset = (page - 1) * limit;
        const search = req.query.search || '';

        let history;
        if (search) {
            history = await History.searchHistory(search, limit, offset);
        } else {
            history = await History.getHistory(limit, offset);
        }

        res.render('history', {
            user: req.session.user,
            history: history,
            currentPage: page,
            search: search
        });
    } catch (error) {
        console.error('Error fetching history:', error);
        res.status(500).render('error', {
            message: 'Erro ao carregar histórico',
            error: error
        });
    }
});

// Get history entry details
router.get('/entry/:id', isAuthenticated, async (req, res) => {
    try {
        const entry = await History.getEntryById(req.params.id);
        if (!entry) {
            return res.status(404).json({ error: 'Registro não encontrado' });
        }
        res.json(entry);
    } catch (error) {
        console.error('Error fetching history entry:', error);
        res.status(500).json({ error: 'Erro ao carregar detalhes do registro' });
    }
});

module.exports = router; 