const express = require('express');
const router = express.Router();
const { authenticateUser } = require('../services/authService');
const User = require('../models/User');
const AccessAudit = require('../models/AccessAudit');
const { getRequestAuditContext } = require('../services/requestAuditContext');

const DEVELOPMENT_AUTO_LOGIN_ENABLED = process.env.NODE_ENV === 'development'
  && process.env.DEV_AUTO_LOGIN_LOCAL === 'true';
const MANUAL_LOGIN_URL = '/login?skipAutoLogin=1';

function isLoopbackRequest(req) {
  const remoteAddress = req.socket && req.socket.remoteAddress;
  return ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(remoteAddress);
}

function normalizeLoginType(loginType) {
  return loginType === 'local' ? 'local' : 'ldap';
}

function saveSession(req) {
  return new Promise((resolve, reject) => {
    req.session.save((error) => (error ? reject(error) : resolve()));
  });
}

async function recordRejectedLogin(req, username, loginType, result) {
  const authType = normalizeLoginType(loginType);
  const requestContext = getRequestAuditContext(req);
  let user = null;

  try {
    user = await User.findByIdentity(authType, username);
    await AccessAudit.record({
      userId: user && user.id,
      username,
      authType,
      action: result.auditAction === 'ACCESS_DENIED' ? 'ACCESS_DENIED' : 'LOGIN_FAILURE',
      success: false,
      reasonCode: result.reasonCode || 'AUTHENTICATION_FAILED',
      ...requestContext
    });
  } catch (error) {
    console.error('Nao foi possivel registrar a tentativa de login recusada:', error.message);
  }
}

async function establishAuthenticatedSession(req, result) {
  const requestContext = getRequestAuditContext(req);
  const user = await User.recordSuccessfulLogin(result.user, requestContext);

  await AccessAudit.record({
    userId: user.id,
    username: user.username,
    authType: user.auth_type,
    action: 'LOGIN_SUCCESS',
    success: true,
    reasonCode: 'AUTHENTICATED',
    ...requestContext
  });

  req.session.user = {
    ...result.user,
    id: user.id,
    username: user.username,
    displayName: user.display_name || result.user.displayName,
    email: user.email || result.user.email,
    type: user.auth_type
  };

  try {
    await saveSession(req);
  } catch (error) {
    delete req.session.user;
    try {
      await AccessAudit.record({
        userId: user.id,
        username: user.username,
        authType: user.auth_type,
        action: 'SESSION_ERROR',
        success: false,
        reasonCode: 'SESSION_SAVE_FAILED',
        ...requestContext
      });
    } catch (auditError) {
      console.error('Nao foi possivel registrar falha ao salvar sessao:', auditError.message);
    }
    throw error;
  }
}

if (DEVELOPMENT_AUTO_LOGIN_ENABLED) {
  router.get('/dev-login', async (req, res) => {
    if (!isLoopbackRequest(req)) {
      return res.sendStatus(404);
    }

    if (!process.env.ADMIN_USER || !process.env.ADMIN_PASSWORD) {
      console.error('Login automatico local indisponivel: configuracao do admin local incompleta.');
      req.flash('error', 'Login automatico indisponivel. Use o login manual.');
      return res.redirect(MANUAL_LOGIN_URL);
    }

    try {
      const result = await authenticateUser(
        process.env.ADMIN_USER,
        process.env.ADMIN_PASSWORD,
        'local'
      );

      if (!result.success) {
        await recordRejectedLogin(req, process.env.ADMIN_USER, 'local', result);
        console.error('Falha no login automatico do administrador local.');
        req.flash('error', 'Nao foi possivel realizar o login automatico. Use o login manual.');
        return res.redirect(MANUAL_LOGIN_URL);
      }

      await establishAuthenticatedSession(req, result);
      return res.redirect('/');
    } catch (error) {
      console.error('Erro durante o login automatico local:', error.message);
      req.flash('error', 'Erro durante o login automatico. Use o login manual.');
      return res.redirect(MANUAL_LOGIN_URL);
    }
  });
}

router.get('/login', (req, res) => {
  if (req.session.user) {
    return res.redirect('/');
  }

  if (
    DEVELOPMENT_AUTO_LOGIN_ENABLED
    && isLoopbackRequest(req)
    && req.query.skipAutoLogin !== '1'
  ) {
    return res.redirect('/dev-login');
  }

  res.render('login', {
    messages: res.locals.messages
  });
});

router.post('/login', async (req, res) => {
  const { username, password, loginType } = req.body;
  const authType = normalizeLoginType(loginType);

  console.log('\n=== Tentativa de login ===');
  console.log('Usuario:', username);
  console.log('Tipo de login:', authType);

  try {
    const result = await authenticateUser(username, password, authType);

    if (result.success) {
      await establishAuthenticatedSession(req, result);
      console.log('Login bem sucedido para:', result.user.displayName);
      return res.redirect('/');
    }

    await recordRejectedLogin(req, username, authType, result);
    console.log('Falha no login:', result.reasonCode || 'AUTHENTICATION_FAILED');
    req.flash('error', result.message || 'Credenciais invalidas');
    return res.render('login', {
      messages: {
        error: [result.message || 'Credenciais invalidas'],
        success: [],
        info: []
      }
    });
  } catch (error) {
    console.error('Erro durante autenticacao:', error.message);
    await recordRejectedLogin(req, username, authType, {
      reasonCode: 'AUTH_ROUTE_ERROR',
      auditAction: 'LOGIN_FAILURE'
    });
    req.flash('error', 'Erro interno durante autenticacao');
    return res.render('login', {
      messages: {
        error: ['Erro interno durante autenticacao'],
        success: [],
        info: []
      }
    });
  }
});

router.get('/logout', async (req, res) => {
  const sessionUser = req.session && req.session.user ? { ...req.session.user } : null;

  if (sessionUser) {
    try {
      await AccessAudit.record({
        userId: sessionUser.id,
        username: sessionUser.username,
        authType: sessionUser.type,
        action: 'LOGOUT',
        success: true,
        reasonCode: 'USER_REQUEST',
        ...getRequestAuditContext(req)
      });
    } catch (error) {
      console.error('Nao foi possivel registrar o logout:', error.message);
    }
  }

  req.session.destroy((error) => {
    if (error) {
      console.error('Erro ao fazer logout:', error.message);
    }
    res.redirect('/login');
  });
});

module.exports = router;
