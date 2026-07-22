const MAX_IP_LENGTH = 64;
const MAX_USER_AGENT_LENGTH = 512;

function limitText(value, maxLength) {
    if (value == null) return null;
    const text = String(value).trim();
    return text ? text.slice(0, maxLength) : null;
}

function getClientIp(req) {
    const rawIp = req && (req.ip || (req.socket && req.socket.remoteAddress));
    const normalizedIp = limitText(rawIp, MAX_IP_LENGTH);
    if (!normalizedIp) return null;
    return normalizedIp.startsWith('::ffff:') ? normalizedIp.slice(7) : normalizedIp;
}

function getUserAgent(req) {
    const userAgent = req && typeof req.get === 'function' ? req.get('user-agent') : null;
    return limitText(userAgent, MAX_USER_AGENT_LENGTH);
}

function getRequestAuditContext(req) {
    return {
        clientIp: getClientIp(req),
        userAgent: getUserAgent(req)
    };
}

module.exports = {
    getClientIp,
    getUserAgent,
    getRequestAuditContext
};
