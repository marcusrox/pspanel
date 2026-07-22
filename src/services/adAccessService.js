const ldap = require('ldapjs');

const MAX_GROUP_DN_LENGTH = 1024;
const CONTROL_CHARACTERS_PATTERN = /[\u0000-\u001F\u007F]/;

function normalizeAllowedAdGroupDn(value) {
    return String(value || '').trim();
}

function validateAllowedAdGroupDn(value) {
    if (value !== undefined && value !== null && typeof value !== 'string') {
        throw new Error('Grupo permitido do Active Directory inválido');
    }

    const normalizedDn = normalizeAllowedAdGroupDn(value);
    if (!normalizedDn) {
        return '';
    }

    if (normalizedDn.length > MAX_GROUP_DN_LENGTH) {
        throw new Error(`O DN do grupo permitido deve ter no máximo ${MAX_GROUP_DN_LENGTH} caracteres`);
    }

    if (CONTROL_CHARACTERS_PATTERN.test(normalizedDn)) {
        throw new Error('O DN do grupo permitido contém caracteres inválidos');
    }

    try {
        const parsedDn = ldap.parseDN(normalizedDn);
        if (parsedDn.length < 2) {
            throw new Error('DN incompleto');
        }
    } catch (error) {
        throw new Error('Informe o DN completo e válido do grupo do Active Directory');
    }

    return normalizedDn;
}

function isUserInAllowedAdGroup(memberOf, allowedGroupDn) {
    const normalizedAllowedGroupDn = normalizeAllowedAdGroupDn(allowedGroupDn).toLocaleLowerCase('en-US');
    if (!normalizedAllowedGroupDn) {
        return true;
    }

    const groups = Array.isArray(memberOf)
        ? memberOf
        : (typeof memberOf === 'string' ? [memberOf] : []);

    return groups.some((groupDn) => (
        typeof groupDn === 'string'
        && groupDn.trim().toLocaleLowerCase('en-US') === normalizedAllowedGroupDn
    ));
}

module.exports = {
    isUserInAllowedAdGroup,
    normalizeAllowedAdGroupDn,
    validateAllowedAdGroupDn
};
