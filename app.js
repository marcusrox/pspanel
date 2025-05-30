const express = require("express");
const bodyParser = require("body-parser");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
const session = require('express-session');
const flash = require('connect-flash');
const { passport, isAuthenticated } = require('./middleware/auth');
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3000;

// Configuração do Express
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

// Configuração do Passport e Flash messages
app.use(passport.initialize());
app.use(passport.session());
app.use(flash());

// Configuração do template engine
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));

// Middleware para logging de requisições
app.use((req, res, next) => {
  console.log('\n=== Nova Requisição ===');
  console.log('Método:', req.method);
  console.log('URL:', req.url);
  console.log('Autenticado:', req.isAuthenticated());
  if (req.user) {
    console.log('Usuário:', req.user.username);
  }
  next();
});

// Rota de login
app.get('/login', (req, res) => {
  console.log('\n=== Acessando página de login ===');
  console.log('Mensagens de erro:', req.flash('error'));
  res.render('login', { messages: { error: req.flash('error') } });
});

app.post('/login', (req, res, next) => {
  console.log('\n=== Tentativa de login ===');
  console.log('Tipo de autenticação:', req.body.authType);
  console.log('Usuário:', req.body.username);
  console.log('Senha presente:', !!req.body.password);
  
  passport.authenticate(req.body.authType, {
    successRedirect: '/',
    failureRedirect: '/login',
    failureFlash: true
  })(req, res, next);
});

app.get('/logout', (req, res) => {
  console.log('\n=== Logout ===');
  console.log('Usuário:', req.user?.username);
  req.logout(() => {
    res.redirect('/login');
  });
});

// Middleware de autenticação para todas as rotas abaixo
app.use(isAuthenticated);

// Rota principal
app.get("/", (req, res) => {
  res.render('index', { user: req.user });
});

// Rota para listar scripts
app.get("/list-scripts", (req, res) => {
  const scriptsDir = path.join(__dirname, "scripts");

  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler pasta de scripts:", err);
      return res.status(500).json({ error: "Erro ao listar scripts" });
    }

    const scripts = files.filter((f) => f.endsWith(".ps1"));
    res.json(scripts);
  });
});

app.get("/render-scripts", (req, res) => {
  const scriptsDir = path.join(__dirname, "scripts");

  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler scripts:", err);
      return res.status(500).send("<option>Erro ao carregar</option>");
    }

    const ps1Files = files.filter((f) => f.endsWith(".ps1"));

    const options = [
      '<option value="">- Selecione -</option>',
      ...ps1Files.map((script) => `<option value="${script}">${script}</option>`)
    ].join("");
    
    res.send(options);
  }); 
});

app.post("/run-script", (req, res) => {
  const { script, params } = req.body;

  const scriptsDir = path.join(__dirname, "scripts");
  const scriptPath = path.join(scriptsDir, script);

  // Segurança: verificar se o script existe na pasta
  if (!fs.existsSync(scriptPath)) {
    return res.status(404).send("Script não encontrado");
  }
  const args = params ? params.split(" ") : [];

  const ps = spawn("powershell.exe", ["-File", scriptPath, ...args]);

  let output = "";
  let error = "";

  ps.stdout.on("data", (data) => {
    output += data.toString();
  });

  ps.stderr.on("data", (data) => {
    error += data.toString();
  });

  ps.on("close", (code) => {
    const result = `Script ${script} executado com código ${code}`;
    console.log(result);
    if (code === 0) {
      res.send(`<pre>${output}</pre><br />${result}`);
    } else {
      res.send(`<pre>Erro: ${error}</pre><br />${result} `);
    }
  });
});

app.listen(PORT, () => {
  console.log(`\n=== Servidor iniciado ===`);
  console.log(`Porta: ${PORT}`);
  console.log(`Ambiente: ${process.env.NODE_ENV}`);
  console.log(`Diretório base: ${__dirname}`);
});
