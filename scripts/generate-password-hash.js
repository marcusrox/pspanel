const bcrypt = require('bcryptjs');

// Senha que você quer usar para o admin
const password = 'admin123';

// Gera o hash
bcrypt.hash(password, 10, function(err, hash) {
    if (err) {
        console.error('Erro ao gerar hash:', err);
        return;
    }
    console.log('\nHash gerado com sucesso!\n');
    console.log('Adicione a seguinte linha ao seu arquivo .env:');
    console.log('ADMIN_PASSWORD_HASH=' + hash);
    console.log('\nSenha utilizada:', password);
}); 