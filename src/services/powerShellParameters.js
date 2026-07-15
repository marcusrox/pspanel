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

function parseParameterDescriptions(content) {
    const descriptions = new Map();
    const helpBlocks = String(content || '').match(/<#([\s\S]*?)#>/g) || [];

    for (const block of helpBlocks) {
        const lines = block.slice(2, -2).split(/\r?\n/);
        let parameterName = null;
        let descriptionLines = [];

        const saveDescription = () => {
            if (!parameterName) return;
            const description = descriptionLines
                .map((line) => line.trim())
                .filter(Boolean)
                .join(' ');
            if (description) {
                descriptions.set(parameterName.toLowerCase(), description);
            }
        };

        for (const line of lines) {
            const parameterMatch = line.match(/^\s*\.PARAMETER\s+([A-Za-z_][A-Za-z0-9_]*)\s*$/i);
            if (parameterMatch) {
                saveDescription();
                parameterName = parameterMatch[1];
                descriptionLines = [];
                continue;
            }

            if (/^\s*\.[A-Za-z][A-Za-z0-9_-]*(?:\s+.*)?$/i.test(line)) {
                saveDescription();
                parameterName = null;
                descriptionLines = [];
                continue;
            }

            if (parameterName) {
                descriptionLines.push(line);
            }
        }

        saveDescription();
    }

    return descriptions;
}

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

    const parameterDescriptions = parseParameterDescriptions(content);
    const parameters = splitTopLevelParameterDeclarations(paramContent)
        .map(parseParameterDefinition)
        .filter(Boolean)
        .map((parameter) => ({
            ...parameter,
            description: parameterDescriptions.get(parameter.name.toLowerCase()) || null
        }));

    return {
        content: processedContent,
        parameters
    };
}

function getMissingRequiredParameters(parameterDefinitions, providedParams) {
    const values = providedParams && typeof providedParams === 'object' ? providedParams : {};
    return (parameterDefinitions || [])
        .filter((param) => param.mandatory)
        .filter((param) => !values[param.name] || !String(values[param.name]).trim())
        .map((param) => param.name);
}

function tokenizePowerShellArgs(rawParams) {
    if (!rawParams || !String(rawParams).trim()) {
        return [];
    }

    return String(rawParams).trim().match(/"[^"]*"|'[^']*'|\S+/g)
        .map((token) => token.replace(/^['"]|['"]$/g, ''));
}

const SENSITIVE_PARAMETER_MASK = '********';
const NAMED_PARAMETER_WITH_VALUE_PATTERN = /(-([A-Za-z_][A-Za-z0-9_]*))(\s+)(?:"([^"]*)"|'([^']*)'|((?!-)\S+))/g;

function isSensitiveParameterName(name) {
    return typeof name === 'string' && /(senha|password)/i.test(name);
}

function redactSensitiveParameters(rawParams) {
    if (rawParams == null || !String(rawParams).trim()) {
        return {
            maskedParameters: rawParams,
            sensitiveValues: []
        };
    }

    const sensitiveValues = [];
    const maskedParameters = String(rawParams).replace(
        NAMED_PARAMETER_WITH_VALUE_PATTERN,
        (match, parameterToken, parameterName, separator, doubleQuotedValue, singleQuotedValue, unquotedValue) => {
            if (!isSensitiveParameterName(parameterName)) {
                return match;
            }

            const value = doubleQuotedValue !== undefined
                ? doubleQuotedValue
                : singleQuotedValue !== undefined
                    ? singleQuotedValue
                    : unquotedValue;

            if (value) {
                sensitiveValues.push(value);
            }

            return `${parameterToken}${separator}${SENSITIVE_PARAMETER_MASK}`;
        }
    );

    return {
        maskedParameters,
        sensitiveValues: [...new Set(sensitiveValues)]
    };
}

function redactSensitiveText(text, sensitiveValues) {
    if (text == null || !Array.isArray(sensitiveValues) || !sensitiveValues.length) {
        return text;
    }

    return [...new Set(sensitiveValues.filter((value) => typeof value === 'string' && value.length > 0))]
        .sort((a, b) => b.length - a.length)
        .reduce(
            (redactedText, sensitiveValue) => redactedText.split(sensitiveValue).join(SENSITIVE_PARAMETER_MASK),
            String(text)
        );
}

function parseRawNamedParameters(rawParams, parameterDefinitions) {
    const values = {};
    const tokens = tokenizePowerShellArgs(rawParams);
    if (!tokens.length) {
        return values;
    }

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

        values[canonicalName] = nextToken;
        i++;
    }

    return values;
}

function getUnknownPowerShellArgs(rawParams, parameterDefinitions) {
    const tokens = tokenizePowerShellArgs(rawParams);
    if (!tokens.length) {
        return [];
    }

    const knownNames = new Map((parameterDefinitions || []).map((param) => [param.name.toLowerCase(), param.name]));
    const unknown = [];

    for (let i = 0; i < tokens.length; i++) {
        const token = tokens[i];
        const canonicalName = token.startsWith('-')
            ? knownNames.get(token.slice(1).toLowerCase())
            : null;

        if (canonicalName) {
            const nextToken = tokens[i + 1];
            if (nextToken && !nextToken.startsWith('-')) {
                i++;
            }
            continue;
        }

        unknown.push(token);
    }

    return unknown;
}

function formatCommandLineArg(value) {
    const text = String(value);
    if (!/\s/.test(text)) {
        return text;
    }

    if (!text.includes('"')) {
        return `"${text}"`;
    }

    if (!text.includes('\'')) {
        return `'${text}'`;
    }

    return `"${text.replace(/"/g, '\\"')}"`;
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

    args.push(...tokenizePowerShellArgs(rawParams));

    return args;
}

function formatProvidedParams(parameterDefinitions, providedParams, rawParams) {
    const structuredParams = [];
    const values = providedParams && typeof providedParams === 'object' ? providedParams : {};

    for (const param of parameterDefinitions || []) {
        const value = values[param.name];
        if (value !== undefined && value !== null && String(value).trim()) {
            structuredParams.push(`-${param.name} ${formatCommandLineArg(String(value).trim())}`);
        }
    }

    if (rawParams && String(rawParams).trim()) {
        structuredParams.push(String(rawParams).trim());
    }

    return structuredParams.join(' ');
}

module.exports = {
    parseScriptParametersFromContent,
    getMissingRequiredParameters,
    tokenizePowerShellArgs,
    parseRawNamedParameters,
    getUnknownPowerShellArgs,
    formatCommandLineArg,
    buildPowerShellArgs,
    formatProvidedParams,
    isSensitiveParameterName,
    redactSensitiveParameters,
    redactSensitiveText
};
