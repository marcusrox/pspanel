const express = require('express');
const session = require('express-session');
const path = require('path');
const Settings = require('./models/Settings');
const settingsRoutes = require('./routes/settingsRoutes');

const app = express();

// Configurações do Express
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, '../views'));
app.use(express.static(path.join(__dirname, '../public')));
app.use(express.urlencoded({ extended: true }));
app.use(express.json());

// Configuração da sessão
app.use(session({
    secret: 'sua-chave-secreta',
    resave: false,
    saveUninitialized: true
}));

// Flash messages middleware
app.use((req, res, next) => {
    if (!req.session.flash) {
        req.session.flash = {};
    }
    req.flash = (type, message) => {
        req.session.flash[type] = message;
    };
    res.locals.flash = req.session.flash;
    req.session.flash = {};
    next();
});

// Inicializar configurações
Settings.initialize().catch(console.error);

// Rotas
app.use('/settings', settingsRoutes);

// Rota principal
app.get('/', (req, res) => {
    res.render('index');
});

// Tratamento de erros
app.use((err, req, res, next) => {
    console.error(err.stack);
    res.status(500).render('error', {
        message: 'Erro interno do servidor',
        error: err
    });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`Servidor rodando na porta ${PORT}`);
});

module.exports = app; 