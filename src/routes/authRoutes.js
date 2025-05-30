const express = require('express');
const router = express.Router();
const { authenticateUser } = require('../services/authService');

// Rota de login
router.get('/login', (req, res) => {
  if (req.session.user) {
    return res.redirect('/');
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