const express = require("express");
const bodyParser = require("body-parser");
const path = require("path");
const session = require("express-session");
const Settings = require('./src/models/Settings');
const settingsRoutes = require('./src/routes/settingsRoutes');
const { isAuthenticated } = require('./src/middleware/authMiddleware');
const { installConsoleFileLogger } = require('./src/services/webLogger');
require("dotenv").config();

installConsoleFileLogger();

// Importar rotas
const authRoutes = require('./src/routes/authRoutes');
const mainRoutes = require('./src/routes/mainRoutes');
const historyRoutes = require('./src/routes/historyRoutes');
const scheduleRoutes = require('./src/routes/scheduleRoutes');
const logRoutes = require('./src/routes/logRoutes');
const runtimeEnvironmentRoutes = require('./src/routes/runtimeEnvironmentRoutes');
const Schedule = require('./src/models/Schedule');
const History = require('./src/models/History');
const release = require('./src/config/release');

const app = express();
const PORT = process.env.PORT || 3000;

// Configuração do template engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Configuração dos middlewares
app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());
app.use(express.static("public"));

// Configuração da sessão
app.use(session({
  secret: process.env.SESSION_SECRET || 'sua-chave-secreta-aqui',
  resave: false,
  saveUninitialized: false,
  cookie: {
    secure: process.env.NODE_ENV === 'production',
    maxAge: 1000 * 60 * 60 * 8 // 8 horas
  }
}));

// Configuração do Flash
app.use((req, res, next) => {
  req.flash = (type, message) => {
    req.session.flash = req.session.flash || {};

    if (message === undefined) {
      const messages = req.session.flash[type] || [];
      delete req.session.flash[type];
      return messages;
    }

    req.session.flash[type] = req.session.flash[type] || [];
    if (Array.isArray(message)) {
      req.session.flash[type].push(...message);
    } else {
      req.session.flash[type].push(message);
    }

    return req.session.flash[type].length;
  };

  next();
});

// Middleware para disponibilizar mensagens em todas as views
app.use((req, res, next) => {
  res.locals.messages = {
    error: req.flash('error'),
    success: req.flash('success'),
    info: req.flash('info')
  };
  res.locals.release = release;
  next();
});

// Preferencias visuais globais
app.use(async (req, res, next) => {
  try {
    const fontScale = await Settings.get('ui.font_scale');
    res.locals.ui = {
      fontScale: ['85', '90', '100', '110'].includes(fontScale) ? fontScale : '100'
    };
    next();
  } catch (error) {
    res.locals.ui = { fontScale: '100' };
    next();
  }
});

// Rotas de autenticação
app.use('/', authRoutes);

// Proteger rotas que precisam de autenticação
app.use(['/panel', '/run-script', '/history', '/settings', '/schedules', '/scripts', '/logs', '/runtime-environment'], isAuthenticated);

// Rotas principais
app.use('/', mainRoutes);
app.use('/history', historyRoutes);
app.use('/settings', settingsRoutes);
app.use('/schedules', scheduleRoutes);
app.use('/logs', logRoutes);
app.use('/runtime-environment', runtimeEnvironmentRoutes);

async function start() {
  try {
    await History.initialize();
    await Settings.initialize();
    await Schedule.initialize();

    app.listen(PORT, () => {
      console.log(`Servidor rodando na porta ${PORT}`);
      console.log(`URL: http://localhost:${PORT}`);
      console.log(`Iniciando servidor em ambiente: ${process.env.NODE_ENV}`);
      console.log(`Data e hora: ${new Date().toLocaleString()}`);
    });
  } catch (error) {
    console.error('Erro ao inicializar banco de dados:', error);
    process.exit(1);
  }
}

start();

module.exports = app;


