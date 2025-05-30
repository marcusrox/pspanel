const ldap = require('ldapjs');

function createLDAPClient() {
  console.log('Criando novo cliente LDAP...');
  const client = ldap.createClient({
    url: process.env.LDAP_URL,
    tlsOptions: { rejectUnauthorized: false }
  });

  client.on('error', (err) => {
    console.error('Erro no cliente LDAP:', {
      message: err.message,
      code: err.code,
      name: err.name,
      stack: err.stack
    });
  });

  client.on('connectError', (err) => {
    console.error('Erro de conexão LDAP:', {
      message: err.message,
      code: err.code,
      name: err.name,
      stack: err.stack
    });
  });

  return client;
}

async function bindLDAP(client, dn, password) {
  console.log(`\nTentando bind LDAP com DN: ${dn}`);
  
  return new Promise((resolve, reject) => {
    client.bind(dn, password, (err) => {
      if (err) {
        console.error('Erro durante bind LDAP:', {
          message: err.message,
          code: err.code,
          name: err.name,
          stack: err.stack
        });
        reject(err);
        return;
      }
      console.log('Bind LDAP bem sucedido!');
      resolve();
    });
  });
}

async function searchLDAP(client, base, opts) {
  console.log('\nIniciando busca LDAP...');
  console.log('Base:', base);
  console.log('Filtro:', opts.filter);
  console.log('Atributos solicitados:', opts.attributes);

  return new Promise((resolve, reject) => {
    const results = [];
    client.search(base, opts, (err, res) => {
      if (err) {
        console.error('Erro ao iniciar busca LDAP:', {
          message: err.message,
          code: err.code,
          name: err.name,
          stack: err.stack
        });
        reject(err);
        return;
      }

      res.on('searchEntry', (entry) => {
        console.log('\nEntrada LDAP encontrada:');
        console.log('DN:', entry.objectName);
        
        const obj = {};
        if (entry.pojo && entry.pojo.attributes) {
          entry.pojo.attributes.forEach(attr => {
            obj[attr.type] = attr.values && attr.values.length === 1 ? attr.values[0] : attr.values;
            //console.log(`Atributo ${attr.type}:`, obj[attr.type]);
          });
        }
        results.push(obj);
      });

      res.on('error', (err) => {
        console.error('Erro durante busca LDAP:', {
          message: err.message,
          code: err.code,
          name: err.name,
          stack: err.stack
        });
        reject(err);
      });

      res.on('end', (result) => {
        console.log(`\nBusca LDAP finalizada. ${results.length} resultados encontrados.`);
        resolve(results);
      });
    });
  });
}

module.exports = {
  createLDAPClient,
  bindLDAP,
  searchLDAP
}; 