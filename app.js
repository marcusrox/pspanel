const express = require("express");
const bodyParser = require("body-parser");
const path = require("path");
const session = require("express-session");
const flash = require('connect-flash');
const Settings = require('./src/models/Settings');
const settingsRoutes = require('./src/routes/settingsRoutes');
const { isAuthenticated } = require('./src/middleware/authMiddleware');
require("dotenv").config();

// Importar rotas
const authRoutes = require('./src/routes/authRoutes');
const mainRoutes = require('./src/routes/mainRoutes');
const historyRoutes = require('./src/routes/historyRoutes');

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
app.use(flash());

// Middleware para disponibilizar mensagens em todas as views
app.use((req, res, next) => {
  res.locals.messages = {
    error: req.flash('error'),
    success: req.flash('success'),
    info: req.flash('info')
  };
  next();
});

// Rotas de autenticação
app.use('/', authRoutes);

// Proteger rotas que precisam de autenticação
app.use(['/panel', '/run-script', '/history', '/settings'], isAuthenticated);

// Rotas principais
app.use('/', mainRoutes);
app.use('/history', historyRoutes);
app.use('/settings', settingsRoutes);

// Inicializar configurações
Settings.initialize().catch(console.error);

app.listen(PORT, () => {
  console.log(`Servidor rodando na porta ${PORT}`);
  console.log(`URL: http://localhost:${PORT}`);
  console.log(`Iniciando servidor em ambiente: ${process.env.NODE_ENV}`);
  console.log(`Data e hora: ${new Date().toLocaleString()}`);
});

module.exports = app;


