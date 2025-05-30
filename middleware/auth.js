require('dotenv').config();

const passport = require('passport');
const LocalStrategy = require('passport-local').Strategy;
const LdapStrategy = require('passport-ldapauth');
const bcrypt = require('bcryptjs');

console.log('\n=== Inicializando middleware de autenticação ===');
console.log('Verificando variáveis de ambiente:');
console.log('ADMIN_USERNAME:', process.env.ADMIN_USERNAME);
console.log('ADMIN_PASSWORD_HASH definido:', !!process.env.ADMIN_PASSWORD_HASH);

// Configuração do usuário admin local
const localAdmin = {
    username: process.env.ADMIN_USERNAME || 'admin',
    passwordHash: process.env.ADMIN_PASSWORD_HASH
};

// Verifica se as configurações do admin local estão presentes
if (!localAdmin.passwordHash) {
    console.error('AVISO: ADMIN_PASSWORD_HASH não está definido no arquivo .env');
    console.error('Use o script scripts/generate-password-hash.js para gerar um hash');
    console.error('Valor atual:', process.env.ADMIN_PASSWORD_HASH);
}

// Estratégia Local para o admin
passport.use('local', new LocalStrategy(
    async function(username, password, done) {
        console.log('\n=== Tentativa de autenticação local ===');
        console.log('Usuário tentando autenticar:', username);
        
        try {
            // Verifica se as configurações do admin estão presentes
            if (!localAdmin.passwordHash) {
                console.error('Erro: Hash da senha do admin não está configurado');
                return done(null, false, { message: 'Configuração do admin local não está completa' });
            }

            if (username !== localAdmin.username) {
                console.log('Erro: Usuário não encontrado');
                return done(null, false, { message: 'Usuário não encontrado' });
            }

            console.log('Verificando senha...');
            console.log('Password recebido:', password ? '[PRESENTE]' : '[VAZIO]');
            console.log('Hash armazenado:', localAdmin.passwordHash ? localAdmin.passwordHash.substring(0, 10) + '...' : '[VAZIO]');

            const isValidPassword = await bcrypt.compare(password, localAdmin.passwordHash);
            console.log('Resultado da verificação da senha:', isValidPassword);

            if (!isValidPassword) {
                console.log('Erro: Senha incorreta');
                return done(null, false, { message: 'Senha incorreta' });
            }

            console.log('Autenticação local bem-sucedida para:', username);
            return done(null, { 
                username: localAdmin.username, 
                isAdmin: true 
            });
        } catch (error) {
            console.error('Erro na autenticação local:', error);
            return done(error);
        }
    }
));

// Estratégia LDAP para Active Directory
const LDAP_OPTIONS = {
    server: {
        url: process.env.LDAP_URL,
        bindDN: process.env.LDAP_BIND_DN,
        bindCredentials: process.env.LDAP_BIND_PASSWORD,
        searchBase: process.env.LDAP_SEARCH_BASE,
        searchFilter: process.env.LDAP_SEARCH_FILTER || '(&(objectClass=user)(sAMAccountName={{username}})(memberOf=CN=PSPanel_Users,OU=Groups,DC=company,DC=local))',
        searchAttributes: ['displayName', 'mail', 'memberOf'],
        tlsOptions: {
            rejectUnauthorized: false
        }
    },
    usernameField: 'username',
    passwordField: 'password',
    handleErrorsAsFailures: true
};

passport.use('ldap', new LdapStrategy(LDAP_OPTIONS, (user, done) => {
    console.log('\n=== Autenticação LDAP ===');
    console.log('Usuário LDAP autenticado:', user.sAMAccountName);
    
    return done(null, {
        username: user.sAMAccountName,
        displayName: user.displayName,
        email: user.mail,
        isAdmin: false
    });
}));

// Serialização do usuário para a sessão
passport.serializeUser((user, done) => {
    console.log('\n=== Serializando usuário ===');
    console.log('Usuário:', user.username);
    done(null, user);
});

// Deserialização do usuário da sessão
passport.deserializeUser((user, done) => {
    console.log('\n=== Deserializando usuário ===');
    console.log('Usuário:', user.username);
    done(null, user);
});

// Middleware para verificar se o usuário está autenticado
const isAuthenticated = (req, res, next) => {
    console.log('\n=== Verificando autenticação ===');
    console.log('Usuário autenticado:', req.isAuthenticated());
    console.log('Sessão:', req.session);
    
    if (req.isAuthenticated()) {
        console.log('Usuário autorizado:', req.user.username);
        return next();
    }
    console.log('Usuário não autenticado, redirecionando para /login');
    res.redirect('/login');
};

// Middleware para verificar se o usuário é admin
const isAdmin = (req, res, next) => {
    console.log('\n=== Verificando permissão de admin ===');
    console.log('Usuário:', req.user);
    
    if (req.isAuthenticated() && req.user.isAdmin) {
        console.log('Usuário é admin:', req.user.username);
        return next();
    }
    console.log('Acesso negado: usuário não é admin');
    res.status(403).send('Acesso negado');
};

module.exports = {
    passport,
    isAuthenticated,
    isAdmin
}; 