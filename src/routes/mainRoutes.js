const express = require('express');
const router = express.Router();
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

// Rota principal
router.get('/', (req, res) => {
  if (!req.session.user) {
    return res.redirect('/login');
  }

  const scriptsDir = path.join(process.cwd(), "scripts");
  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler pasta de scripts:", err);
      return res.render('index', { 
        user: req.session.user,
        messages: res.locals.messages,
        scripts: []
      });
    }

    const scripts = files.filter((f) => f.endsWith(".ps1"));
    res.render('index', { 
      user: req.session.user,
      messages: res.locals.messages,
      scripts: scripts
    });
  });
});

// Rota para listar scripts
router.get("/list-scripts", (req, res) => {
  const scriptsDir = path.join(process.cwd(), "scripts");

  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler pasta de scripts:", err);
      return res.status(500).json({ error: "Erro ao listar scripts" });
    }

    const scripts = files.filter((f) => f.endsWith(".ps1"));
    res.json(scripts);
  });
});

router.get("/render-scripts", (req, res) => {
  const scriptsDir = path.join(process.cwd(), "scripts");

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

router.post("/run-script", (req, res) => {
  const { script, params } = req.body;

  const scriptsDir = path.join(process.cwd(), "scripts");
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

module.exports = router; 