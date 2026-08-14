require('dotenv').config();

const {
    bindLDAP,
    buildUserSearchFilter,
    createLDAPClient,
    searchLDAP,
    unbindLDAP
} = require('../src/services/ldapService');

const REQUIRED_ENVIRONMENT_VARIABLES = [
    'LDAP_URL',
    'LDAP_BIND_DN',
    'LDAP_BIND_PASSWORD',
    'LDAP_SEARCH_BASE',
    'TEST_USERNAME',
    'TEST_PASSWORD'
];

function assertConfiguration() {
    const missingVariables = REQUIRED_ENVIRONMENT_VARIABLES.filter((name) => !process.env[name]);
    if (missingVariables.length > 0) {
        throw new Error(`Variáveis obrigatórias ausentes: ${missingVariables.join(', ')}`);
    }
}

async function closeClient(client, description) {
    if (!client) {
        return;
    }

    try {
        await unbindLDAP(client);
    } catch (error) {
        console.error(`Erro ao desconectar ${description}:`, error.message);
    }
}

async function testLDAPConnection() {
    assertConfiguration();
    console.log('=== Iniciando teste de conexão LDAP ===');

    let serviceClient;
    let userClient;
    try {
        serviceClient = createLDAPClient();
        await bindLDAP(serviceClient, process.env.LDAP_BIND_DN, process.env.LDAP_BIND_PASSWORD);
        console.log('Bind da conta de serviço concluído.');

        const users = await searchLDAP(serviceClient, process.env.LDAP_SEARCH_BASE, {
            scope: 'sub',
            filter: buildUserSearchFilter(process.env.TEST_USERNAME),
            attributes: ['sAMAccountName', 'displayName', 'mail', 'distinguishedName', 'memberOf']
        });

        if (users.length !== 1 || !users[0].distinguishedName) {
            throw new Error(`A busca do usuário de teste retornou ${users.length} resultado(s).`);
        }
        console.log('Busca do usuário de teste concluída com um resultado.');

        userClient = createLDAPClient();
        await bindLDAP(userClient, users[0].distinguishedName, process.env.TEST_PASSWORD);
        console.log('Bind do usuário de teste concluído.');
        console.log('Teste LDAP concluído com sucesso.');
    } finally {
        await closeClient(userClient, 'cliente do usuário');
        await closeClient(serviceClient, 'cliente de serviço');
    }
}

testLDAPConnection().catch((error) => {
    console.error('Teste LDAP falhou:', error.message);
    process.exitCode = 1;
});
