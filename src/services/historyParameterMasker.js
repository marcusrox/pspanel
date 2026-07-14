const MASKED_PARAMETER_VALUE = '********';

function tokenizeWithRanges(value) {
    const tokens = [];
    let index = 0;

    while (index < value.length) {
        while (index < value.length && /\s/.test(value[index])) {
            index++;
        }

        if (index >= value.length) {
            break;
        }

        const start = index;
        let quote = null;

        while (index < value.length) {
            const character = value[index];

            if (quote) {
                if (character === quote && value[index - 1] !== '`') {
                    quote = null;
                }
            } else if (character === '"' || character === "'") {
                quote = character;
            } else if (/\s/.test(character)) {
                break;
            }

            index++;
        }

        tokens.push({
            start,
            end: index,
            value: value.slice(start, index)
        });
    }

    return tokens;
}

function isPasswordParameterName(name) {
    const normalizedName = String(name || '').toLowerCase();
    return normalizedName.includes('password') || normalizedName.includes('senha');
}

function maskSensitiveParameterValues(parameters) {
    if (parameters === undefined || parameters === null || parameters === '') {
        return parameters;
    }

    const value = String(parameters);
    const tokens = tokenizeWithRanges(value);
    const replacements = [];

    tokens.forEach((token, index) => {
        const parameterMatch = token.value.match(/^(-{1,2})([^:=\s]+)(?:([:=])(.*))?$/);
        if (!parameterMatch || !isPasswordParameterName(parameterMatch[2])) {
            return;
        }

        const delimiter = parameterMatch[3];
        if (delimiter) {
            const delimiterIndex = token.value.indexOf(delimiter);
            replacements.push({
                start: token.start + delimiterIndex + 1,
                end: token.end,
                value: MASKED_PARAMETER_VALUE
            });
            return;
        }

        const nextToken = tokens[index + 1];
        if (nextToken) {
            replacements.push({
                start: nextToken.start,
                end: nextToken.end,
                value: MASKED_PARAMETER_VALUE
            });
        }
    });

    return replacements
        .sort((left, right) => right.start - left.start)
        .reduce((maskedValue, replacement) => (
            maskedValue.slice(0, replacement.start)
            + replacement.value
            + maskedValue.slice(replacement.end)
        ), value);
}

module.exports = {
    isPasswordParameterName,
    maskSensitiveParameterValues
};
