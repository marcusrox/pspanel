const { createLDAPClient, bindLDAP, searchLDAP } = require('./ldapService');

async function authenticateUser(username, password, loginType) {
  if (loginType === 'local') {
    return authenticateLocal(username, password);
  }
  return authenticateLDAP(username, password);
}

async function authenticateLocal(username, password) {
  console.log('\n=== Iniciando autenticação Local ===');

  console.log('Configurações:');
  console.log('Admin User:', process.env.ADMIN_USER);
  console.log('Admin Password:', process.env.ADMIN_PASSWORD);

  console.log('Usuário tentando autenticar:', username);
  console.log('Senha fornecida:', password);

  if (username === process.env.ADMIN_USER && password === process.env.ADMIN_PASSWORD) {
    console.log('✓ Autenticação Local bem sucedida!');
    return {
      success: true,
      user: {
        username: username,
        displayName: 'Administrador Local',
        type: 'local'
      }
    };
  }
  return { success: false, message: 'Credenciais locais inválidas' };
}

async function authenticateLDAP(username, password) {
  console.log('\n=== Iniciando autenticação LDAP ===');
  console.log('Configurações:');
  console.log('URL:', process.env.LDAP_URL);
  console.log('Bind DN:', process.env.LDAP_BIND_DN);
  console.log('Search Base:', process.env.LDAP_SEARCH_BASE);
  console.log('Usuário tentando autenticar:', username);

  const client = createLDAPClient();
  console.log('Cliente LDAP criado');

  try {
    console.log('\n1. Tentando conectar com credenciais de serviço...');
    await bindLDAP(client, process.env.LDAP_BIND_DN, process.env.LDAP_BIND_PASSWORD);
    console.log('✓ Conexão com credenciais de serviço bem sucedida!');

    console.log('\n2. Buscando usuário no AD...');
    console.log('Filtro de busca:', `(&(objectClass=user)(objectCategory=person)(sAMAccountName=${username}))`);
    
    const users = await searchLDAP(client, process.env.LDAP_SEARCH_BASE, {
      scope: 'sub',
      filter: `(&(objectClass=user)(objectCategory=person)(sAMAccountName=${username}))`,
      attributes: ['sAMAccountName', 'displayName', 'mail', 'distinguishedName', 'memberOf']
    });

    console.log(`Resultados encontrados: ${users.length}`);
    
    if (users.length === 0) {
      console.log('✗ Usuário não encontrado no AD');
      return { success: false, message: 'Usuário não encontrado' };
    }

    const user = users[0];
    console.log('\nDados do usuário encontrado:');
    console.log('- sAMAccountName:', user.sAMAccountName);
    console.log('- displayName:', user.displayName);
    console.log('- mail:', user.mail);
    console.log('- distinguishedName:', user.distinguishedName);
    console.log('- Total de grupos:', Array.isArray(user.memberOf) ? user.memberOf.length : 'N/A');

    const userDN = user.distinguishedName;
    if (!userDN) {
      console.log('✗ DN do usuário não encontrado nos atributos');
      return { success: false, message: 'Erro ao obter informações do usuário' };
    }

    console.log('\n3. Tentando autenticar com as credenciais do usuário...');
    console.log('DN para autenticação:', userDN);
    
    const testClient = createLDAPClient();
    console.log('Novo cliente LDAP criado para teste de autenticação');

    try {
      await bindLDAP(testClient, userDN, password);
      console.log('✓ Autenticação do usuário bem sucedida!');

      const userProfile = {
        success: true,
        user: {
          username: user.sAMAccountName,
          displayName: user.displayName,
          email: user.mail,
          groups: user.memberOf,
          type: 'ldap'
        }
      };  

      //console.log('\nPerfil do usuário montado:', JSON.stringify(userProfile, null, 2));
      return userProfile;

    } catch (error) {
      console.error('\n✗ Falha na autenticação do usuário:', error.message);
      console.error('Código do erro:', error.code);
      console.error('Nome do erro:', error.name);
      if (error.stack) {
        console.error('Stack trace:', error.stack);
      }
      return { success: false, message: 'Senha inválida' };
    } finally {
      console.log('Desconectando cliente de teste...');
      testClient.unbind();
    }
  } catch (error) {
    console.error('\n✗ Erro durante o processo de autenticação:', error.message);
    console.error('Código do erro:', error.code);
    console.error('Nome do erro:', error.name);
    if (error.stack) {
      console.error('Stack trace:', error.stack);
    }
    return { success: false, message: 'Erro interno durante autenticação' };
  } finally {
    console.log('Desconectando cliente principal...');
    client.unbind();
  }
}

module.exports = {
  authenticateUser
}; 