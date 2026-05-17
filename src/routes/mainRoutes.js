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

function findParamBlock(content) {
    const paramMatch = content.match(/\bparam\s*\(/i);
    if (!paramMatch || typeof paramMatch.index !== 'number') {
        return null;
    }

    const openIndex = content.indexOf('(', paramMatch.index);
    if (openIndex === -1) {
        return null;
    }

    let openParens = 1;
    let endIndex = openIndex + 1;

    while (openParens > 0 && endIndex < content.length) {
        if (content[endIndex] === '(') openParens++;
        if (content[endIndex] === ')') openParens--;
        endIndex++;
    }

    if (openParens > 0) {
        return null;
    }

    return content.substring(openIndex + 1, endIndex - 1);
}

function splitTopLevelParameterDeclarations(paramContent) {
    const declarations = [];
    let current = '';
    let bracketDepth = 0;
    let parenDepth = 0;
    let quote = null;

    for (let i = 0; i < paramContent.length; i++) {
        const char = paramContent[i];

        if (quote) {
            current += char;
            if (char === '`') {
                i++;
                if (i < paramContent.length) current += paramContent[i];
                continue;
            }
            if (char === quote) {
                quote = null;
            }
            continue;
        }

        if (char === '\'' || char === '"') {
            quote = char;
            current += char;
            continue;
        }

        if (char === '[') bracketDepth++;
        if (char === ']') bracketDepth = Math.max(0, bracketDepth - 1);
        if (char === '(') parenDepth++;
        if (char === ')') parenDepth = Math.max(0, parenDepth - 1);

        if (char === ',' && bracketDepth === 0 && parenDepth === 0) {
            if (current.trim()) {
                declarations.push(current.trim());
            }
            current = '';
            continue;
        }

        current += char;
    }

    if (current.trim()) {
        declarations.push(current.trim());
    }

    return declarations;
}

function normalizeDefaultValue(value) {
    if (!value) return null;
    const trimmed = value.trim();
    return trimmed.replace(/,$/, '').trim() || null;
}

function parseValidateSetOptions(declaration) {
    const validateSetMatch = declaration.match(/\[\s*ValidateSet\s*\(([\s\S]*?)\)\s*\]/i);
    if (!validateSetMatch) {
        return [];
    }

    return validateSetMatch[1]
        .split(',')
        .map((item) => item.trim().replace(/^['"]|['"]$/g, ''))
        .filter(Boolean);
}

function parseParameterDefinition(declaration) {
    const defaultStartIndex = declaration.search(/\$[A-Za-z_][A-Za-z0-9_]*\b\s*=/);
    const declarationBeforeDefault = defaultStartIndex === -1
        ? declaration
        : declaration.slice(0, defaultStartIndex + declaration.slice(defaultStartIndex).indexOf('='));
    const variableMatches = [...declarationBeforeDefault.matchAll(/\$([A-Za-z_][A-Za-z0-9_]*)\b/g)]
        .filter((match) => !['true', 'false', 'null'].includes(match[1].toLowerCase()));

    if (!variableMatches.length) {
        return null;
    }

    const variableMatch = variableMatches[variableMatches.length - 1];
    const variableIndex = variableMatch.index;
    const beforeVariable = declaration.slice(0, variableIndex);
    const afterVariable = declaration.slice(variableIndex + variableMatch[0].length);
    const typeMatches = [...beforeVariable.matchAll(/\[\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\]/g)];
    const type = typeMatches.length ? typeMatches[typeMatches.length - 1][1] : null;
    const parameterAttributeMatch = declaration.match(/\[\s*Parameter\s*\(([\s\S]*?)\)\s*\]/i);
    const mandatory = Boolean(
        parameterAttributeMatch && /\bMandatory\s*=\s*\$true\b/i.test(parameterAttributeMatch[1])
    );
    const defaultMatch = afterVariable.match(/^\s*=\s*([\s\S]+)$/);

    return {
        name: variableMatch[1],
        type,
        mandatory,
        defaultValue: defaultMatch ? normalizeDefaultValue(defaultMatch[1]) : null,
        validateSet: parseValidateSetOptions(declaration)
    };
}

/** Extrai metadados simples do bloco param(...) a partir do texto do arquivo. */
function parseScriptParametersFromContent(content) {
    const paramContent = findParamBlock(content);
    if (!paramContent) {
        return null;
    }
    const lines = paramContent.split('\n');

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

    return {
        content: processedContent,
        parameters: splitTopLevelParameterDeclarations(paramContent)
            .map(parseParameterDefinition)
            .filter(Boolean)
    };
}

function getMissingRequiredParameters(parameterDefinitions, providedParams) {
    const values = providedParams && typeof providedParams === 'object' ? providedParams : {};
    return (parameterDefinitions || [])
        .filter((param) => param.mandatory)
        .filter((param) => !values[param.name] || !String(values[param.name]).trim())
        .map((param) => param.name);
}

function parseRawNamedParameters(rawParams, parameterDefinitions) {
    const values = {};
    if (!rawParams || !String(rawParams).trim()) {
        return values;
    }

    const tokens = String(rawParams).trim().match(/"[^"]*"|'[^']*'|\S+/g) || [];
    const knownNames = new Map((parameterDefinitions || []).map((param) => [param.name.toLowerCase(), param.name]));

    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        if (!token.startsWith('-')) {
            continue;
        }

        const name = token.slice(1);
        const canonicalName = knownNames.get(name.toLowerCase());
        if (!canonicalName) {
            continue;
        }

        const nextToken = tokens[i + 1];
        if (!nextToken || nextToken.startsWith('-')) {
            values[canonicalName] = 'true';
            continue;
        }

        values[canonicalName] = nextToken.replace(/^['"]|['"]$/g, '');
        i++;
    }

    return values;
}

function buildPowerShellArgs(parameterDefinitions, providedParams, rawParams) {
    const args = [];
    const values = providedParams && typeof providedParams === 'object' ? providedParams : {};

    for (const param of parameterDefinitions || []) {
        const value = values[param.name];
        if (value !== undefined && value !== null && String(value).trim()) {
            args.push(`-${param.name}`, String(value).trim());
        }
    }

    if (rawParams && String(rawParams).trim()) {
        args.push(...String(rawParams).trim().split(/\s+/));
    }

    return args;
}

function formatProvidedParams(parameterDefinitions, providedParams, rawParams) {
    const structuredParams = [];
    const values = providedParams && typeof providedParams === 'object' ? providedParams : {};

    for (const param of parameterDefinitions || []) {
        const value = values[param.name];
        if (value !== undefined && value !== null && String(value).trim()) {
            structuredParams.push(`-${param.name} ${String(value).trim()}`);
        }
    }

    if (rawParams && String(rawParams).trim()) {
        structuredParams.push(String(rawParams).trim());
    }

    return structuredParams.join(' ');
}

function getScriptsDirectory() {
    return path.resolve(process.cwd(), 'scripts-ps');
}

function resolveScriptPath(scriptName) {
    if (!scriptName || typeof scriptName !== 'string') {
        return null;
    }

    const hasPathTraversal = scriptName.includes('..') || scriptName.includes('/') || scriptName.includes('\\');
    if (hasPathTraversal || path.basename(scriptName) !== scriptName || !scriptName.toLowerCase().endsWith('.ps1')) {
        return null;
    }

    const scriptsDir = getScriptsDirectory();
    const scriptPath = path.resolve(scriptsDir, scriptName);
    if (!scriptPath.startsWith(scriptsDir + path.sep)) {
        return null;
    }

    return scriptPath;
}

function normalizeScriptName(scriptName) {
    if (!scriptName || typeof scriptName !== 'string') {
        return null;
    }

    const normalized = scriptName.trim();
    if (!normalized) {
        return null;
    }

    return normalized.toLowerCase().endsWith('.ps1')
        ? normalized
        : `${normalized}.ps1`;
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

router.get('/scripts/:scriptName/source', async (req, res) => {
    const scriptName = req.params.scriptName;
    const scriptPath = resolveScriptPath(scriptName);

    if (!scriptPath) {
        return res.status(400).render('script-source-popup', {
            scriptName,
            source: null,
            error: 'Nome de script invalido.'
        });
    }

    try {
        const source = await fs.readFile(scriptPath, 'utf8');
        res.render('script-source-popup', {
            scriptName,
            source,
            error: null
        });
    } catch (error) {
        console.error(`Erro ao ler codigo fonte do script ${scriptPath}:`, error);
        res.status(error.code === 'ENOENT' ? 404 : 500).render('script-source-popup', {
            scriptName,
            source: null,
            error: error.code === 'ENOENT'
                ? 'Script nao encontrado.'
                : 'Nao foi possivel ler o codigo fonte do script.'
        });
    }
});

router.post('/scripts/:scriptName/rename', async (req, res) => {
    const currentScriptName = req.params.scriptName;
    const newScriptName = normalizeScriptName(req.body && req.body.newScriptName);
    const currentScriptPath = resolveScriptPath(currentScriptName);
    const newScriptPath = resolveScriptPath(newScriptName);

    if (!currentScriptPath || !newScriptPath) {
        return res.status(400).json({ error: 'Nome de script invalido.' });
    }

    if (currentScriptName === newScriptName) {
        return res.status(400).json({ error: 'Informe um nome diferente do atual.' });
    }

    try {
        await fs.access(currentScriptPath);
    } catch (error) {
        return res.status(404).json({ error: 'Script original nao encontrado.' });
    }

    try {
        await fs.access(newScriptPath);
        return res.status(409).json({ error: 'Ja existe um script com esse nome.' });
    } catch (error) {
        if (error.code !== 'ENOENT') {
            console.error(`Erro ao validar destino da renomeacao ${newScriptPath}:`, error);
            return res.status(500).json({ error: 'Nao foi possivel validar o novo nome do script.' });
        }
    }

    try {
        await fs.rename(currentScriptPath, newScriptPath);
        res.json({ success: true, scriptName: newScriptName });
    } catch (error) {
        console.error(`Erro ao renomear script ${currentScriptPath} para ${newScriptPath}:`, error);
        res.status(500).json({ error: 'Nao foi possivel renomear o script.' });
    }
});

router.post("/run-script", async (req, res) => {
    console.log('\n=== Iniciando execução de script ===');
    const { script, params, paramValues } = req.body;
    console.log('Script solicitado:', script);
    console.log('Parâmetros:', params);
    console.log('Parâmetros estruturados:', paramValues);

    const scriptPath = resolveScriptPath(script);
    console.log('Caminho completo do script:', scriptPath);

    if (!scriptPath) {
        console.error('Erro: Nome de script invalido:', script);
        return res.status(400).send("Nome de script invalido");
    }

    if (!fsSync.existsSync(scriptPath)) {
        console.error('Erro: Script não encontrado em:', scriptPath);
        return res.status(404).send("Script não encontrado");
    }
    console.log('Script encontrado com sucesso');

    let parameterDefinitions = [];
    try {
        const source = await fs.readFile(scriptPath, 'utf8');
        const parameterInfo = parseScriptParametersFromContent(source);
        parameterDefinitions = parameterInfo && Array.isArray(parameterInfo.parameters)
            ? parameterInfo.parameters
            : [];
    } catch (error) {
        console.error(`Erro ao ler parametros do script ${scriptPath}:`, error);
        return res.status(500).send("Nao foi possivel validar os parametros do script");
    }

    const rawParamValues = parseRawNamedParameters(params, parameterDefinitions);
    const providedParamValues = {
        ...rawParamValues,
        ...(paramValues && typeof paramValues === 'object' ? paramValues : {})
    };
    const missingRequiredParameters = getMissingRequiredParameters(parameterDefinitions, providedParamValues);
    if (missingRequiredParameters.length) {
        const message = `Informe os parametros obrigatorios: ${missingRequiredParameters.join(', ')}.`;
        console.error('Execucao bloqueada:', message);
        return res.status(400).send(`<div class="error-message">${message}</div>`);
    }

    const args = buildPowerShellArgs(parameterDefinitions, paramValues, params);
    const parameterSummary = formatProvidedParams(parameterDefinitions, paramValues, params);
    console.log('Argumentos processados:', args);

    // Criar registro no histórico
    let historyId;
    try {
        historyId = await History.addEntry(script, parameterSummary, req.session.user.username);
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
