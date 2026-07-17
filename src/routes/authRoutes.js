const express = require('express');
const router = express.Router();
const { authenticateUser } = require('../services/authService');
const DEVELOPMENT_AUTO_LOGIN_ENABLED = process.env.NODE_ENV === 'development'
  && process.env.DEV_AUTO_LOGIN_LOCAL === 'true';
const MANUAL_LOGIN_URL = '/login?skipAutoLogin=1';

function isLoopbackRequest(req) {
  const remoteAddress = req.socket && req.socket.remoteAddress;
  return ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(remoteAddress);
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
        console.error('Falha no login automatico do administrador local.');
        req.flash('error', 'Nao foi possivel realizar o login automatico. Use o login manual.');
        return res.redirect(MANUAL_LOGIN_URL);
      }

      req.session.user = result.user;
      req.session.save((error) => {
        if (error) {
          console.error('Erro ao salvar a sessao do login automatico local:', error.message);
          req.flash('error', 'Erro ao iniciar a sessao. Use o login manual.');
          return res.redirect(MANUAL_LOGIN_URL);
        }

        return res.redirect('/');
      });
    } catch (error) {
      console.error('Erro durante o login automatico local:', error.message);
      req.flash('error', 'Erro durante o login automatico. Use o login manual.');
      return res.redirect(MANUAL_LOGIN_URL);
    }
  });
}

// Rota de login
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
  
  console.log('\n=== Tentativa de login ===');
  console.log('Usuário:', username);
  console.log('Tipo de login:', loginType);

  try {
    const result = await authenticateUser(username, password, loginType);

    if (result.success) {
      req.session.user = result.user;
      console.log('Login bem sucedido para:', result.user.displayName);
      res.redirect('/');
    } else {
      console.log('Falha no login:', result.message);
      req.flash('error', result.message || 'Credenciais inválidas');
      res.render('login', {
        messages: {
          error: [result.message || 'Credenciais inválidas'],
          success: [],
          info: []
        }
      });
    }
  } catch (error) {
    console.error('Erro durante autenticação:', error);
    req.flash('error', 'Erro interno durante autenticação');
    res.render('login', {
      messages: {
        error: ['Erro interno durante autenticação'],
        success: [],
        info: []
      }
    });
  }
});

router.get('/logout', (req, res) => {
  req.session.destroy((err) => {
    if (err) {
      console.error('Erro ao fazer logout:', err);
    }
    res.redirect('/login');
  });
});

module.exports = router;
