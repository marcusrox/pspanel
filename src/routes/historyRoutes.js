const express = require('express');
const router = express.Router();
const History = require('../models/History');
const { formatDateTimePtBr } = require('../services/dateTimeFormatter');

const HISTORY_PAGE_LIMIT = 20;

// Middleware to check if user is authenticated
const isAuthenticated = (req, res, next) => {
    if (req.session.user) {
        next();
    } else {
        res.redirect('/login');
    }
};

const buildPaginationPages = (currentPage, totalPages) => {
    if (totalPages <= 1) {
        return [];
    }

    const pages = new Set([1, totalPages]);
    const windowSize = 2;

    for (let page = currentPage - windowSize; page <= currentPage + windowSize; page++) {
        if (page > 1 && page < totalPages) {
            pages.add(page);
        }
    }

    return Array.from(pages)
        .sort((a, b) => a - b)
        .reduce((items, page, index, sortedPages) => {
            if (index > 0 && page - sortedPages[index - 1] > 1) {
                items.push('ellipsis');
            }

            items.push(page);
            return items;
        }, []);
};

function formatHistoryEntryDates(entry) {
    return {
        ...entry,
        formatted_start_time: formatDateTimePtBr(entry.start_time),
        formatted_end_time: entry.end_time ? formatDateTimePtBr(entry.end_time) : 'Em execução'
    };
}

// Get history page
router.get('/', isAuthenticated, async (req, res) => {
    try {
        const requestedPage = parseInt(req.query.page, 10);
        const page = Number.isInteger(requestedPage) && requestedPage > 0 ? requestedPage : 1;
        const limit = HISTORY_PAGE_LIMIT;
        const search = (req.query.search || '').trim();
        const totalItems = search
            ? await History.countSearchHistory(search)
            : await History.countHistory();
        const totalPages = Math.ceil(totalItems / limit);
        const currentPage = totalPages > 0 ? Math.min(page, totalPages) : 1;
        const offset = (currentPage - 1) * limit;

        let history;
        if (search) {
            history = await History.searchHistory(search, limit, offset);
        } else {
            history = await History.getHistory(limit, offset);
        }

        res.render('history', {
            user: req.session.user,
            history: history.map(formatHistoryEntryDates),
            currentPage: currentPage,
            totalItems: totalItems,
            totalPages: totalPages,
            limit: limit,
            paginationPages: buildPaginationPages(currentPage, totalPages),
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
        res.json(formatHistoryEntryDates(entry));
    } catch (error) {
        console.error('Error fetching history entry:', error);
        res.status(500).json({ error: 'Erro ao carregar detalhes do registro' });
    }
});

module.exports = router;
