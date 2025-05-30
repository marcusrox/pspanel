const express = require('express');
const router = express.Router();
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs').promises;
const fsSync = require('fs');

// Função para ler os parâmetros de um script PowerShell
async function getScriptParameters(scriptPath) {
    try {
        const content = await fs.readFile(scriptPath, 'utf8');
        console.log('Reading script:', scriptPath);

        // Encontra o início do bloco param
        const startIndex = content.indexOf('param(');
        if (startIndex === -1) {
            console.log('No param block found in:', scriptPath);
            return null;
        }

        // Encontra o fechamento do parênteses correspondente
        let openParens = 1;
        let endIndex = startIndex + 6; // Começa após 'param('
        
        while (openParens > 0 && endIndex < content.length) {
            if (content[endIndex] === '(') openParens++;
            if (content[endIndex] === ')') openParens--;
            endIndex++;
        }

        if (openParens > 0) {
            console.log('Incomplete param block in:', scriptPath);
            return null;
        }

        // Extrai o conteúdo entre param( e )
        const paramContent = content.substring(startIndex + 6, endIndex - 1);
        
        // Divide em linhas e processa cada uma
        const lines = paramContent.split('\n');
        
        // Se só tem uma linha, retorna ela sem processamento
        if (lines.length === 1) {
            return {
                content: paramContent.trim()
            };
        }
        
        // Encontra a indentação base (da primeira linha não vazia)
        let baseIndent = '';
        for (const line of lines) {
            if (line.trim()) {
                baseIndent = line.match(/^\s*/)[0];
                break;
            }
        }
        
        // Remove a indentação base de todas as linhas e junta novamente
        const processedContent = lines
            .map(line => {
                if (!line.trim()) return '';
                // Se a linha começa com a indentação base, remove ela
                if (line.startsWith(baseIndent)) {
                    return line.substring(baseIndent.length);
                }
                return line.trim();
            })
            .join('\n');

        console.log('Found param content:', processedContent);
        
        return {
            content: processedContent
        };
    } catch (error) {
        console.error(`Error reading script ${scriptPath}:`, error);
        return null;
    }
}

// Rota principal
router.get('/', async (req, res) => {
    if (!req.session.user) {
        return res.redirect('/login');
    }

    try {
        const scriptsDir = path.join(process.cwd(), "scripts");
        const files = await fs.readdir(scriptsDir);
        const scripts = [];

        for (const file of files) {
            if (file.endsWith('.ps1')) {
                const scriptPath = path.join(scriptsDir, file);
                const parameters = await getScriptParameters(scriptPath);
                scripts.push({
                    name: file,
                    parameters: parameters || []
                });
            }
        }

        res.render('index', { 
            user: req.session.user,
            messages: res.locals.messages,
            scripts: scripts
        });
    } catch (error) {
        console.error("Erro ao ler pasta de scripts:", error);
        res.render('index', { 
            user: req.session.user,
            messages: res.locals.messages,
            scripts: []
        });
    }
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

router.post("/run-script", async (req, res) => {
    const { script, params } = req.body;

    const scriptsDir = path.join(process.cwd(), "scripts");
    const scriptPath = path.join(scriptsDir, script);

    // Segurança: verificar se o script existe na pasta
    if (!fsSync.existsSync(scriptPath)) {
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