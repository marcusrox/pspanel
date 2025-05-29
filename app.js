const express = require("express");
const bodyParser = require("body-parser");
const { spawn } = require("child_process");
const path = require("path");
const fs = require("fs");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(bodyParser.urlencoded({ extended: true }));
app.use(bodyParser.json());

app.use(express.static("public"));

app.get("/", (req, res) => {
  res.sendFile(path.join(__dirname, "views", "index.html"));
});

app.get("/list-scripts", (req, res) => {
  const scriptsDir = path.join(__dirname, "scripts");

  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler pasta de scripts:", err);
      return res.status(500).json({ error: "Erro ao listar scripts" });
    }

    // Filtra apenas arquivos .ps1
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
  console.log(`Servidor rodando na porta ${PORT}`);
});
