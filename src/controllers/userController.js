const User = require('../models/User');
const AccessAudit = require('../models/AccessAudit');
const History = require('../models/History');
const Schedule = require('../models/Schedule');
const { formatDateTimePtBr } = require('../services/dateTimeFormatter');

const USER_PAGE_LIMIT = 20;
const AUDIT_PAGE_LIMIT = 50;
const USER_TRAIL_LIMIT = 50;

function positiveInteger(value, fallback = 1) {
    const parsed = Number.parseInt(value, 10);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function pageState(requestedPage, totalItems, limit) {
    const totalPages = Math.ceil(totalItems / limit);
    const currentPage = totalPages > 0 ? Math.min(positiveInteger(requestedPage), totalPages) : 1;
    return {
        currentPage,
        totalPages,
        totalItems,
        offset: (currentPage - 1) * limit
    };
}

function formatRows(rows, dateField) {
    return rows.map((row) => ({
        ...row,
        formatted_date: formatDateTimePtBr(row[dateField])
    }));
}

function normalizeUserFilters(query) {
    return {
        search: typeof query.search === 'string' ? query.search.trim().slice(0, 255) : '',
        authType: ['local', 'ldap'].includes(query.auth_type) ? query.auth_type : ''
    };
}

function normalizeAuditFilters(query) {
    return {
        search: typeof query.search === 'string' ? query.search.trim().slice(0, 255) : '',
        authType: ['local', 'ldap'].includes(query.auth_type) ? query.auth_type : '',
        category: ['access', 'execution', 'schedule'].includes(query.category) ? query.category : '',
        action: typeof query.action === 'string' ? query.action.trim().slice(0, 64) : '',
        dateFrom: /^\d{4}-\d{2}-\d{2}$/.test(query.date_from || '') ? query.date_from : '',
        dateTo: /^\d{4}-\d{2}-\d{2}$/.test(query.date_to || '') ? query.date_to : ''
    };
}

exports.list = async (req, res) => {
    const filters = normalizeUserFilters(req.query);

    try {
        const totalItems = await User.count(filters);
        const pagination = pageState(req.query.page, totalItems, USER_PAGE_LIMIT);
        const users = await User.list(filters, USER_PAGE_LIMIT, pagination.offset);

        res.render('users', {
            user: req.session.user,
            users: users.map((entry) => ({
                ...entry,
                formatted_first_login: formatDateTimePtBr(entry.first_login_at),
                formatted_last_login: formatDateTimePtBr(entry.last_login_at)
            })),
            filters,
            pagination,
            messages: res.locals.messages
        });
    } catch (error) {
        console.error('Erro ao carregar usuarios:', error);
        res.status(500).render('error', { message: 'Erro ao carregar usuarios.', error });
    }
};

exports.detail = async (req, res) => {
    const userId = positiveInteger(req.params.id, 0);
    if (!userId) {
        return res.status(404).render('error', { message: 'Usuario nao encontrado.', error: null });
    }

    try {
        const selectedUser = await User.findById(userId);
        if (!selectedUser) {
            return res.status(404).render('error', { message: 'Usuario nao encontrado.', error: null });
        }

        const [accessEntries, executionEntries, scheduleEntries] = await Promise.all([
            AccessAudit.listByUser(userId, USER_TRAIL_LIMIT),
            History.findByUser(userId, USER_TRAIL_LIMIT),
            Schedule.listAuditByUser(userId, USER_TRAIL_LIMIT)
        ]);

        return res.render('user-detail', {
            user: req.session.user,
            selectedUser: {
                ...selectedUser,
                formatted_first_login: formatDateTimePtBr(selectedUser.first_login_at),
                formatted_last_login: formatDateTimePtBr(selectedUser.last_login_at)
            },
            accessEntries: formatRows(accessEntries, 'created_at'),
            executionEntries: formatRows(executionEntries, 'start_time'),
            scheduleEntries: formatRows(scheduleEntries, 'created_at'),
            trailLimit: USER_TRAIL_LIMIT,
            messages: res.locals.messages
        });
    } catch (error) {
        console.error('Erro ao carregar detalhe do usuario:', error);
        return res.status(500).render('error', { message: 'Erro ao carregar detalhe do usuario.', error });
    }
};

exports.audit = async (req, res) => {
    const filters = normalizeAuditFilters(req.query);

    try {
        const totalItems = await AccessAudit.countConsolidated(filters);
        const pagination = pageState(req.query.page, totalItems, AUDIT_PAGE_LIMIT);
        const entries = await AccessAudit.listConsolidated(filters, AUDIT_PAGE_LIMIT, pagination.offset);

        res.render('user-audit', {
            user: req.session.user,
            entries: formatRows(entries, 'created_at'),
            filters,
            pagination,
            messages: res.locals.messages
        });
    } catch (error) {
        console.error('Erro ao carregar auditoria consolidada:', error);
        res.status(500).render('error', { message: 'Erro ao carregar auditoria consolidada.', error });
    }
};
