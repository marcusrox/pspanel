const MAX_GROUP_DN_LENGTH = 1024;
const CONTROL_CHARACTERS_PATTERN = /[\u0000-\u001F\u007F]/;
const ATTRIBUTE_TYPE_PATTERN = /^(?:[A-Za-z][A-Za-z0-9-]*|\d+(?:\.\d+)+)$/;
const HEX_PAIR_PATTERN = /^[0-9A-Fa-f]{2}$/;
const ESCAPABLE_VALUE_CHARACTERS = new Set([' ', '"', '#', '+', ',', ';', '<', '=', '>', '\\']);
const UNESCAPED_VALUE_CHARACTERS = new Set(['"', '+', ',', ';', '<', '>', '\\']);

function normalizeAllowedAdGroupDn(value) {
    return String(value || '').trim();
}

function splitUnescaped(value, separator) {
    const parts = [];
    let current = '';

    for (let index = 0; index < value.length; index += 1) {
        const character = value[index];
        if (character === '\\') {
            if (index + 1 >= value.length) {
                throw new Error('Escape incompleto');
            }
            current += character + value[index + 1];
            index += 1;
            continue;
        }

        if (character === separator) {
            parts.push(current);
            current = '';
            continue;
        }

        current += character;
    }

    parts.push(current);
    return parts;
}

function findUnescapedEquals(value) {
    for (let index = 0; index < value.length; index += 1) {
        if (value[index] === '\\') {
            index += 1;
            continue;
        }
        if (value[index] === '=') {
            return index;
        }
    }
    return -1;
}

function validateAttributeValue(value) {
    if ((value.startsWith(' ') || value.startsWith('#')) && !value.startsWith('\\')) {
        throw new Error('Inicio de valor nao escapado');
    }
    if (value.endsWith(' ')) {
        throw new Error('Fim de valor nao escapado');
    }

    for (let index = 0; index < value.length; index += 1) {
        const character = value[index];
        if (character === '\\') {
            const escapedCharacter = value[index + 1];
            if (escapedCharacter === undefined) {
                throw new Error('Escape incompleto');
            }

            const possibleHexPair = value.slice(index + 1, index + 3);
            if (possibleHexPair.length === 2 && HEX_PAIR_PATTERN.test(possibleHexPair)) {
                index += 2;
                continue;
            }

            if (!ESCAPABLE_VALUE_CHARACTERS.has(escapedCharacter)) {
                throw new Error('Escape invalido');
            }
            index += 1;
            continue;
        }

        if (UNESCAPED_VALUE_CHARACTERS.has(character)) {
            throw new Error('Caractere especial nao escapado');
        }
    }
}

function parseDistinguishedName(value) {
    const rdns = splitUnescaped(value, ',');
    if (rdns.length < 2) {
        throw new Error('DN incompleto');
    }

    rdns.forEach((rdn) => {
        if (!rdn.trim()) {
            throw new Error('RDN vazio');
        }

        splitUnescaped(rdn, '+').forEach((attributeAndValue) => {
            const equalsIndex = findUnescapedEquals(attributeAndValue);
            if (equalsIndex <= 0) {
                throw new Error('Atributo sem valor');
            }

            const attributeType = attributeAndValue.slice(0, equalsIndex).trim();
            const attributeValue = attributeAndValue.slice(equalsIndex + 1);
            if (!ATTRIBUTE_TYPE_PATTERN.test(attributeType)) {
                throw new Error('Tipo de atributo invalido');
            }

            validateAttributeValue(attributeValue);
        });
    });

    return rdns;
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
        parseDistinguishedName(normalizedDn);
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
    parseDistinguishedName,
    validateAllowedAdGroupDn
};
