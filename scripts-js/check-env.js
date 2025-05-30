require('dotenv').config();

console.log('\nVerificando variáveis de ambiente:\n');

const requiredVars = [
    'ADMIN_USERNAME',
    'ADMIN_PASSWORD_HASH',
    'SESSION_SECRET'
];

const ldapVars = [
    'LDAP_URL',
    'LDAP_BIND_DN',
    'LDAP_BIND_PASSWORD',
    'LDAP_SEARCH_BASE',
    'LDAP_SEARCH_FILTER'
];

console.log('Variáveis Obrigatórias:');
console.log('----------------------');
requiredVars.forEach(varName => {
    const value = process.env[varName];
    console.log(`${varName}: ${value ? '✅ Definida' : '❌ Não definida'}`);
    if (value) {
        console.log(`Valor: ${varName === 'ADMIN_PASSWORD_HASH' ? value.substring(0, 10) + '...' : value}`);
    }
    console.log('');
});

console.log('\nVariáveis LDAP (opcional):');
console.log('----------------------');
ldapVars.forEach(varName => {
    const value = process.env[varName];
    console.log(`${varName}: ${value ? '✅ Definida' : '⚠️ Não definida'}`);
    console.log('');
});

// Verifica o caminho do arquivo .env
const path = require('path');
const fs = require('fs');
const envPath = path.join(process.cwd(), '.env');

console.log('\nVerificação do arquivo .env:');
console.log('----------------------');
if (fs.existsSync(envPath)) {
    console.log('✅ Arquivo .env encontrado');
    console.log('Caminho:', envPath);
    console.log('\nConteúdo do arquivo .env:');
    const envContent = fs.readFileSync(envPath, 'utf8');
    console.log('----------------------');
    console.log(envContent);
} else {
    console.log('❌ Arquivo .env não encontrado');
} 