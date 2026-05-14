const express = require('express');
const router = express.Router();
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs').promises;
const fsSync = require('fs');
const History = require('../models/History');

/** Extrai .SYNOPSIS do primeiro bloco de comentário baseado em ajuda (<# ... #>). */
function parseSynopsisFromContent(content) {
    const start = content.indexOf('<#');
    if (start === -1) return null;
    const end = content.indexOf('#>', start + 2);
    if (end === -1) return null;
    const help = content.slice(start + 2, end);
    const lines = help.split(/\r?\n/);
    const synopsisLines = [];
    let inSynopsis = false;

    for (let i = 0; i < lines.length; i++) {
        const trimmed = lines[i].trim();
        if (!inSynopsis) {
            if (/^\.SYNOPSIS\b/i.test(trimmed)) {
                inSynopsis = true;
                const after = trimmed.replace(/^\.SYNOPSIS\b/i, '').trim();
                if (after) synopsisLines.push(after);
            }
        } else if (/^\.[A-Z][A-Za-z0-9_]*\b/.test(trimmed)) {
            break;
        } else {
            synopsisLines.push(lines[i].trimEnd());
        }
    }

    const text = synopsisLines.join('\n').trim();
    return text.length ? text : null;
}

/** Mesma lógica de getScriptParameters, a partir do texto do arquivo (uma leitura por script). */
function parseScriptParametersFromContent(content) {
    const startIndex = content.indexOf('param(');
    if (startIndex === -1) {
        return null;
    }

    let openParens = 1;
    let endIndex = startIndex + 6;

    while (openParens > 0 && endIndex < content.length) {
        if (content[endIndex] === '(') openParens++;
        if (content[endIndex] === ')') openParens--;
        endIndex++;
    }

    if (openParens > 0) {
        return null;
    }

    const paramContent = content.substring(startIndex + 6, endIndex - 1);
    const lines = paramContent.split('\n');

    if (lines.length === 1) {
        return { content: paramContent.trim() };
    }

    let baseIndent = '';
    for (const line of lines) {
        if (line.trim()) {
            baseIndent = line.match(/^\s*/)[0];
            break;
        }
    }

    const processedContent = lines
        .map((line) => {
            if (!line.trim()) return '';
            if (line.startsWith(baseIndent)) {
                return line.substring(baseIndent.length);
            }
            return line.trim();
        })
        .join('\n');

    return { content: processedContent };
}

// Rota principal
router.get('/', async (req, res) => {
    if (!req.session.user) {
        return res.redirect('/login');
    }

    try {
        const scriptsDir = path.join(process.cwd(), "scripts-ps");
        const files = (await fs.readdir(scriptsDir)).sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
        const scripts = [];

        for (const file of files) {
            if (file.endsWith('.ps1')) {
                const scriptPath = path.join(scriptsDir, file);
                try {
                    const content = await fs.readFile(scriptPath, 'utf8');
                    const parameters = parseScriptParametersFromContent(content);
                    const synopsis = parseSynopsisFromContent(content);
                    scripts.push({
                        name: file,
                        synopsis,
                        parameters: parameters || null
                    });
                } catch (readErr) {
                    console.error(`Erro ao ler script ${scriptPath}:`, readErr);
                    scripts.push({ name: file, synopsis: null, parameters: null });
                }
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
  const scriptsDir = path.join(process.cwd(), "scripts-ps");

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
  console.log('\n=== Renderizando lista de scripts ===');
  const scriptsDir = path.join(process.cwd(), "scripts-ps");
  console.log('Diretório de scripts:', scriptsDir);

  fs.readdir(scriptsDir, (err, files) => {
    if (err) {
      console.error("Erro ao ler scripts:", err);
      return res.status(500).send("<option>Erro ao carregar</option>");
    }

    console.log('Arquivos encontrados:', files);
    const ps1Files = files.filter((f) => f.endsWith(".ps1"));
    console.log('Scripts PowerShell encontrados:', ps1Files);

    const options = [
      '<option value="">- Selecione -</option>',
      ...ps1Files.map((script) => `<option value="${script}">${script}</option>`)
    ].join("");
    
    res.send(options);
  }); 
});

router.post("/run-script", async (req, res) => {
    console.log('\n=== Iniciando execução de script ===');
    const { script, params } = req.body;
    console.log('Script solicitado:', script);
    console.log('Parâmetros:', params);

    const scriptsDir = path.join(process.cwd(), "scripts-ps");
    const scriptPath = path.join(scriptsDir, script);
    console.log('Caminho completo do script:', scriptPath);

    // Segurança: verificar se o script existe na pasta
    if (!fsSync.existsSync(scriptPath)) {
        console.error('Erro: Script não encontrado em:', scriptPath);
        return res.status(404).send("Script não encontrado");
    }
    console.log('Script encontrado com sucesso');

    const args = params ? params.split(" ") : [];
    console.log('Argumentos processados:', args);

    // Criar registro no histórico
    let historyId;
    try {
        historyId = await History.addEntry(script, params, req.session.user.username);
    } catch (error) {
        console.error('Erro ao registrar histórico:', error);
        // Continua a execução mesmo se falhar o registro no histórico
    }

    console.log('Iniciando execução do PowerShell com os seguintes parâmetros:');
    console.log('- Script:', scriptPath);
    console.log('- Argumentos:', args);

    const ps = spawn("powershell.exe", ["-File", scriptPath, ...args]);

    let output = "";
    let error = "";

    ps.stdout.on("data", (data) => {
        const newOutput = data.toString();
        console.log('Saída do script:', newOutput);
        output += newOutput;
    });

    ps.stderr.on("data", (data) => {
        const newError = data.toString();
        console.error('Erro do script:', newError);
        error += newError;
    });

    ps.on("error", (err) => {
        console.error('Erro ao executar o PowerShell:', err);
        error += `\nErro ao executar o PowerShell: ${err.message}`;
    });

    ps.on("close", async (code) => {
        console.log(`\n=== Script finalizado ===`);
        console.log('Código de saída:', code);
        console.log('Saída acumulada:', output);
        if (error) console.error('Erros acumulados:', error);

        // Atualizar registro no histórico
        if (historyId) {
            try {
                await History.updateEntry(
                    historyId,
                    output || error,
                    code === 0 ? 'success' : 'error',
                    error || null
                );
            } catch (updateError) {
                console.error('Erro ao atualizar histórico:', updateError);
            }
        }

        const result = `Script ${script} executado com código ${code}`;
        if (code === 0) {
            res.send(`<pre>${output}</pre><br />${result}`);
        } else {
            res.send(`<pre>Erro: ${error}</pre><br />${result}`);
        }
    });
});

module.exports = router; 