const {
  bindLDAP,
  buildUserSearchFilter,
  createLDAPClient,
  isInvalidCredentialsError,
  searchLDAP,
  unbindLDAP
} = require('./ldapService');
const Settings = require('../models/Settings');
const { isUserInAllowedAdGroup } = require('./adAccessService');

async function authenticateUser(username, password, loginType) {
  if (loginType === 'local') {
    return authenticateLocal(username, password);
  }
  return authenticateLDAP(username, password);
}

async function authenticateLocal(username, password) {
  console.log('\n=== Iniciando autenticação Local ===');

  console.log('Configurações:');
  console.log('Admin User configurado:', process.env.ADMIN_USER ? 'sim' : 'não');
  console.log('Admin Password configurado:', process.env.ADMIN_PASSWORD ? 'sim' : 'não');
  console.log('Senha fornecida:', password ? '[REDACTED]' : '[vazia]');

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
  return {
    success: false,
    message: 'Credenciais locais inválidas',
    reasonCode: 'INVALID_CREDENTIALS',
    auditAction: 'LOGIN_FAILURE'
  };
}

function logLdapError(context, error) {
  console.error(context, {
    message: error && error.message,
    code: error && error.code,
    name: error && error.name
  });
}

async function closeLDAPClient(client, description) {
  if (!client) {
    return;
  }

  try {
    await unbindLDAP(client);
  } catch (error) {
    logLdapError(`Erro ao desconectar ${description}:`, error);
  }
}

async function authenticateLDAP(username, password) {
  console.log('\n=== Iniciando autenticação LDAP ===');
  console.log('Configurações:');
  console.log('URL LDAP configurada:', process.env.LDAP_URL ? 'sim' : 'não');
  console.log('Bind DN configurado:', process.env.LDAP_BIND_DN ? 'sim' : 'não');
  console.log('Search Base configurado:', process.env.LDAP_SEARCH_BASE ? 'sim' : 'não');

  let serviceClient;
  try {
    serviceClient = createLDAPClient();
    await bindLDAP(serviceClient, process.env.LDAP_BIND_DN, process.env.LDAP_BIND_PASSWORD);

    const users = await searchLDAP(serviceClient, process.env.LDAP_SEARCH_BASE, {
      scope: 'sub',
      filter: buildUserSearchFilter(username),
      attributes: ['sAMAccountName', 'displayName', 'mail', 'distinguishedName', 'memberOf']
    });

    if (users.length === 0) {
      return {
        success: false,
        message: 'Usuário não encontrado',
        reasonCode: 'USER_NOT_FOUND',
        auditAction: 'LOGIN_FAILURE'
      };
    }

    const user = users[0];
    const userDN = user.distinguishedName;
    if (!userDN) {
      return {
        success: false,
        message: 'Erro ao obter informações do usuário',
        reasonCode: 'USER_PROFILE_INCOMPLETE',
        auditAction: 'LOGIN_FAILURE'
      };
    }

    let userClient;
    try {
      userClient = createLDAPClient();
      await bindLDAP(userClient, userDN, password);

      let allowedGroupDn;
      try {
        allowedGroupDn = await Settings.get('auth.allowed_ad_group_dn');
      } catch (error) {
        logLdapError('Erro ao carregar configuração de acesso do Active Directory:', error);
        return {
          success: false,
          message: 'Erro interno durante autenticação',
          reasonCode: 'AUTH_CONFIGURATION_ERROR',
          auditAction: 'LOGIN_FAILURE'
        };
      }

      if (!isUserInAllowedAdGroup(user.memberOf, allowedGroupDn)) {
        console.warn('Acesso LDAP negado: usuário autenticado não pertence ao grupo permitido.');
        return {
          success: false,
          message: 'Acesso negado: seu usuário foi autenticado, mas não pertence ao grupo do Active Directory autorizado a acessar o PS Panel.',
          reasonCode: 'AD_GROUP_ACCESS_DENIED',
          auditAction: 'ACCESS_DENIED'
        };
      }

      return {
        success: true,
        user: {
          username: user.sAMAccountName,
          displayName: user.displayName,
          email: user.mail,
          groups: user.memberOf,
          type: 'ldap'
        }
      };
    } catch (error) {
      logLdapError('Falha na autenticação do usuário LDAP:', error);
      if (isInvalidCredentialsError(error)) {
        return {
          success: false,
          message: 'Senha inválida',
          reasonCode: 'INVALID_CREDENTIALS',
          auditAction: 'LOGIN_FAILURE'
        };
      }

      return {
        success: false,
        message: 'Erro interno durante autenticação',
        reasonCode: 'AUTH_INTERNAL_ERROR',
        auditAction: 'LOGIN_FAILURE'
      };
    } finally {
      await closeLDAPClient(userClient, 'cliente LDAP do usuário');
    }
  } catch (error) {
    logLdapError('Erro durante o processo de autenticação LDAP:', error);
    return {
      success: false,
      message: 'Erro interno durante autenticação',
      reasonCode: 'AUTH_INTERNAL_ERROR',
      auditAction: 'LOGIN_FAILURE'
    };
  } finally {
    await closeLDAPClient(serviceClient, 'cliente LDAP de serviço');
  }
}

module.exports = {
  authenticateUser
};
