function normalizeUsername(value) {
    return String(value || '').trim().toLowerCase();
}

function isLocalAdministrator(user) {
    const configuredAdmin = normalizeUsername(process.env.ADMIN_USER);
    return !!user
        && user.type === 'local'
        && !!configuredAdmin
        && normalizeUsername(user.username) === configuredAdmin;
}

function isLocalAdmin(req, res, next) {
    if (isLocalAdministrator(req.session && req.session.user)) {
        return next();
    }

    return res.status(403).render('error', {
        message: 'Acesso restrito ao administrador local.',
        error: null
    });
}

module.exports = {
    isLocalAdmin,
    isLocalAdministrator
};
