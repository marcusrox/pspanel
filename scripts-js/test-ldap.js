require('dotenv').config();
const ldap = require('ldapjs');
const util = require('util');

// Configurações do LDAP do arquivo .env
const config = {
    url: process.env.LDAP_URL,
    bindDN: process.env.LDAP_BIND_DN,
    bindCredentials: process.env.LDAP_BIND_PASSWORD,
    searchBase: process.env.LDAP_SEARCH_BASE,
    testUser: process.env.TEST_USERNAME || 'msouza',
    testPassword: process.env.TEST_PASSWORD || 'Mmdmmd@04'
};

// Função para criar cliente LDAP
function createClient() {
    const client = ldap.createClient({
        url: config.url,
        tlsOptions: { rejectUnauthorized: false }
    });

    // Adiciona handler de erro para o cliente
    client.on('error', (err) => {
        console.error('Erro no cliente LDAP:', err);
    });

    return client;
}

// Função para fazer bind (autenticação) no LDAP
async function bindLDAP(client, dn, password) {
    return new Promise((resolve, reject) => {
        client.bind(dn, password, (err) => {
            if (err) {
                reject(err);
                return;
            }
            resolve();
        });
    });
}

// Função para realizar busca no LDAP
async function searchLDAP(client, base, opts) {
    return new Promise((resolve, reject) => {
        const results = [];
        client.search(base, opts, (err, res) => {
            if (err) {
                console.error('Erro na busca:', err);
                reject(err);
                return;
            }

            res.on('searchEntry', (entry) => {
                // Processar os atributos da entrada
                const obj = {};
                if (entry.pojo && entry.pojo.attributes) {
                    entry.pojo.attributes.forEach(attr => {
                        obj[attr.type] = attr.values && attr.values.length === 1 ? attr.values[0] : attr.values;
                    });
                }
                results.push(obj);
            });

            res.on('error', (err) => {
                console.error('Erro durante a busca:', err);
                reject(err);
            });

            res.on('end', (result) => {
                if (results.length === 0) {
                    console.log('Nenhum resultado encontrado');
                }
                resolve(results);
            });
        });
    });
}

// Função principal de teste
async function testLDAPConnection() {
    console.log('\n=== Iniciando Teste de Conexão LDAP ===\n');
    console.log('Configurações:');
    console.log('URL:', config.url);
    console.log('Bind DN:', config.bindDN);
    console.log('Search Base:', config.searchBase);
    
    const client = createClient();

    try {
        // Teste 1: Conexão inicial com credenciais de serviço
        console.log('\n1. Testando conexão com credenciais de serviço...');
        await bindLDAP(client, config.bindDN, config.bindCredentials);
        console.log('✓ Conexão bem sucedida com credenciais de serviço!');

        // Teste 2: Buscar usuários
        console.log('\n2. Buscando usuários...');
        const users = await searchLDAP(client, config.searchBase, {
            scope: 'sub',
            filter: '(&(objectClass=user)(objectCategory=person))',
            attributes: ['sAMAccountName', 'displayName', 'mail', 'distinguishedName']
        });
        
        console.log(`✓ Encontrados ${users.length} usuários`);
        if (users.length > 0) {
            console.log('Primeiros 5 usuários:');
            users.slice(0, 5).forEach(user => {
                if (user) {
                    console.log('\nUsuário:', {
                        sAMAccountName: user.sAMAccountName || 'N/A',
                        displayName: user.displayName || 'N/A',
                        mail: user.mail || 'N/A',
                        dn: user.distinguishedName || 'N/A'
                    });
                } else {
                    console.log('Usuário indefinido');
                }
            });
        }

        // Teste 3: Buscar grupos
        console.log('\n3. Buscando grupos...');
        const groups = await searchLDAP(client, config.searchBase, {
            scope: 'sub',
            filter: '(&(objectClass=group)(!(objectClass=computer)))',
            attributes: ['cn', 'description', 'distinguishedName']
        });

        console.log(`✓ Encontrados ${groups.length} grupos`);
        if (groups.length > 0) {
            console.log('Primeiros 5 grupos:');
            groups.slice(0, 5).forEach(group => {
                if (group) {
                    console.log('\nGrupo:', {
                        cn: group.cn || 'N/A',
                        description: group.description || 'N/A',
                        dn: group.distinguishedName || 'N/A'
                    });
                } else {
                    console.log('Grupo indefinido');
                }
            });
        }

        // Teste 4: Testar autenticação do usuário específico
        console.log('\n4. Testando autenticação do usuário:', config.testUser);
        
        const userSearchResults = await searchLDAP(client, config.searchBase, {
            scope: 'sub',
            filter: `(&(objectClass=user)(objectCategory=person)(sAMAccountName=${config.testUser}))`,
            attributes: ['distinguishedName', 'memberOf', 'sAMAccountName']
        });

        if (userSearchResults.length === 0) {
            throw new Error(`Usuário ${config.testUser} não encontrado`);
        }

        const userDN = userSearchResults[0].distinguishedName;
        console.log('DN do usuário encontrado:', userDN);
        
        if (!userDN) {
            throw new Error('DN do usuário não encontrado');
        }

        const userGroups = userSearchResults[0].memberOf;

        // Criar novo cliente para testar autenticação do usuário
        const testClient = createClient();
        
        try {
            await bindLDAP(testClient, userDN, config.testPassword);
            console.log('✓ Autenticação do usuário bem sucedida!');
            console.log('Grupos do usuário:');
            if (Array.isArray(userGroups)) {
                userGroups.forEach(group => console.log(`- ${group}`));
            } else if (userGroups) {
                console.log(`- ${userGroups}`);
            } else {
                console.log('Nenhum grupo encontrado');
            }
        } catch (error) {
            console.error('✗ Falha na autenticação do usuário:', error.message);
        } finally {
            testClient.unbind();
        }

    } catch (error) {
        console.error('\n✗ Erro durante os testes:', error.message);
    } finally {
        client.unbind();
    }
}

// Executar os testes
testLDAPConnection().catch(console.error); 