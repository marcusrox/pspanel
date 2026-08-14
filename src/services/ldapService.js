const { Client, InvalidCredentialsError, escapeFilter } = require('ldapts');

function createLDAPClient() {
    const url = process.env.LDAP_URL;
    const options = { url };

    if (new URL(url).protocol === 'ldaps:') {
        options.tlsOptions = { rejectUnauthorized: false };
    }

    return new Client(options);
}

async function bindLDAP(client, dn, password) {
    await client.bind(dn, password);
}

function getAttributeValue(entry, attributeName) {
    const matchingKey = Object.keys(entry).find(
        (key) => key.toLocaleLowerCase('en-US') === attributeName.toLocaleLowerCase('en-US')
    );

    if (matchingKey) {
        return entry[matchingKey];
    }

    if (attributeName.toLocaleLowerCase('en-US') === 'distinguishedname') {
        return entry.dn;
    }

    return undefined;
}

function normalizeSearchEntry(entry, attributes = []) {
    const normalizedEntry = {};

    attributes.forEach((attributeName) => {
        const value = getAttributeValue(entry, attributeName);
        if (value !== undefined) {
            normalizedEntry[attributeName] = value;
        }
    });

    return normalizedEntry;
}

async function searchLDAP(client, base, opts) {
    const { searchEntries } = await client.search(base, opts);
    return searchEntries.map((entry) => normalizeSearchEntry(entry, opts.attributes));
}

async function unbindLDAP(client) {
    if (client) {
        await client.unbind();
    }
}

function buildUserSearchFilter(username) {
    return escapeFilter`(&(objectClass=user)(objectCategory=person)(sAMAccountName=${String(username || '')}))`;
}

function isInvalidCredentialsError(error) {
    return error instanceof InvalidCredentialsError;
}

module.exports = {
    bindLDAP,
    buildUserSearchFilter,
    createLDAPClient,
    isInvalidCredentialsError,
    normalizeSearchEntry,
    searchLDAP,
    unbindLDAP
};
