# TASK-053 - Atualizar sqlite3 para 6.0.1

## Contexto

O deploy da versao `v2026.08.11-050` concluiu com sucesso, mas o comando
`npm ci --omit=dev` apresentou avisos de pacotes descontinuados na arvore de
dependencias do `sqlite3@5.1.7`. Entre eles estao versoes antigas de `tar`,
`node-gyp`, `glob`, `rimraf`, `inflight`, `npmlog` e outros pacotes usados no
download ou na compilacao do modulo nativo.

O npm tambem informou que o script de instalacao do `sqlite3@5.1.7` ainda nao
esta coberto por uma entrada `allowScripts`. A instalacao atual funciona e foi
validada com o SQLite em memoria, mas a ausencia de uma aprovacao explicita
pode causar falha em versoes do npm que apliquem a politica de scripts de forma
mais restritiva.

O `sqlite3@6.0.1` e a versao publicada mais recente. Ela exige Node.js
`>=20.17.0`, enquanto o PS Panel homologa Node.js 24, e atualiza o SQLite
embarcado e dependencias da cadeia de instalacao. Entretanto, o projeto
`node-sqlite3` foi arquivado e declarado sem manutencao. Portanto, esta
atualizacao deve ser tratada como uma reducao de risco intermediaria, nao como
a solucao definitiva para o driver de persistencia.

## Objetivo

Atualizar a dependencia de producao `sqlite3` de `5.1.7` para a versao exata
`6.0.1`, registrar uma aprovacao versionada para seu script de instalacao e
validar que o PS Panel continua operando sobre os bancos SQLite existentes sem
alteracao de formato ou perda de dados.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

1. Alterar `package.json` para usar exatamente:

   ```json
   "sqlite3": "6.0.1"
   ```

   Nao usar `^`, `~` ou outra faixa, pois o pacote esta sem manutencao e novas
   versoes nao devem entrar no deploy sem validacao explicita.

2. Atualizar `package-lock.json` com npm, preservando as demais dependencias e
   evitando atualizacoes oportunistas fora da arvore necessaria para o
   `sqlite3@6.0.1`.

3. Adicionar ao `package.json` uma aprovacao restrita e versionada para o
   script de instalacao:

   ```json
   "allowScripts": {
     "sqlite3@6.0.1": true
   }
   ```

   Nao usar liberacao global de scripts, `dangerously-allow-all-scripts` ou
   configuracao equivalente.

4. Confirmar que `npm ci --omit=dev` executa o script necessario para obter ou
   compilar o binario nativo do SQLite e nao apresenta pendencia de aprovacao
   para `sqlite3@6.0.1`.

5. Preservar o contrato publico de `src/database/connection.js`, incluindo:

   - `configure()`;
   - `run()` com retorno de `lastID` e `changes`;
   - `get()`;
   - `all()`;
   - `exec()`;
   - exportacao de `db`, `databaseDir` e `databasePath`.

   Nao alterar o adaptador se a API do `sqlite3@6.0.1` permanecer compativel.

6. Confirmar que a pagina de ambiente de dados continua identificando o
   driver e sua versao corretamente.

7. Atualizar `src/config/release.js` ao concluir a implementacao, usando a data
   local e incrementando em 1 o sequencial global no formato
   `vAAAA.MM.DD-NNN`.

## Arquivos previstos

```text
package.json
package-lock.json
src/config/release.js
```

Alterar `src/database/connection.js` ou
`src/services/dataEnvironmentService.js` somente se um problema real de
compatibilidade for identificado durante a implementacao.

## Procedimento de implementacao

1. Verificar `git status --short` e preservar alteracoes locais do usuario.
2. Confirmar a versao homologada do Node.js e a versao do npm usadas em DEV.
3. Atualizar somente o `sqlite3` para `6.0.1`, preferencialmente com uma
   operacao equivalente a:

   ```powershell
   npm install sqlite3@6.0.1 --save-exact
   ```

4. Revisar o diff de `package.json` e `package-lock.json` para garantir que nao
   houve atualizacoes alheias.
5. Registrar `allowScripts` de forma restrita a `sqlite3@6.0.1`.
6. Executar uma instalacao limpa com `npm ci --omit=dev`.
7. Executar as validacoes funcionais e de sintaxe descritas nesta task.
8. Atualizar o identificador de release somente depois que as validacoes forem
   aprovadas.

Se o registro npm exigir a autoridade certificadora corporativa, configurar o
`cafile` apropriado no ambiente antes de instalar. Nao desabilitar
`strict-ssl`, nao gravar certificados privados no repositorio e nao incluir
informacoes sensiveis nos logs ou na documentacao.

## Validacao obrigatoria

### Dependencias

Executar e registrar o resultado de:

```powershell
node --version
npm --version
npm ls sqlite3 --omit=dev
npm ci --omit=dev
```

O resultado esperado e uma unica versao `sqlite3@6.0.1`, sem dependencia
invalida e sem aviso de script de instalacao pendente para o pacote.

Avisos remanescentes devem ser listados e classificados. A task nao deve ser
considerada falha apenas porque uma dependencia ainda mantem aviso de
descontinuacao, desde que o aviso seja conhecido, documentado e nao possua
correcao compativel nesta arvore.

### SQLite em memoria

Executar um teste isolado, sem abrir ou alterar os arquivos em `database/`, que:

- carregue `require('sqlite3')`;
- abra um banco `:memory:`;
- crie uma tabela temporaria;
- insira um registro usando placeholder `?`;
- consulte o registro;
- valide `lastID`, `changes` e os valores retornados;
- feche a conexao sem erro;
- consulte `sqlite_version()` para registrar a versao embarcada.

### Aplicacao

- Rodar `node --check` nos arquivos JavaScript alterados.
- Rodar `node --check app.js` se algum arquivo carregado no bootstrap for
  modificado.
- Iniciar um servidor temporario somente na porta `3100` ou na proxima porta
  livre autorizada, com `PORT`, `NODE_ENV=development` e
  `DEV_AUTO_LOGIN_LOCAL=true` definidos explicitamente.
- Capturar o PID e encerrar somente o processo iniciado pelo agente.
- Validar health check HTTP 200.
- Validar uma pagina autenticada que consulte o banco.
- Conferir a pagina de ambiente de dados e a identificacao do driver
  `sqlite3 6.0.1`.
- Executar o worker de agendamentos quando for seguro e confirmar encerramento
  sem erro.

Credenciais locais podem ser carregadas internamente pela aplicacao conforme o
fluxo autorizado do repositorio, mas nunca devem ser impressas ou documentadas.

### Auditoria

Quando a cadeia de certificados do registro npm estiver configurada, executar:

```powershell
npm audit --omit=dev
```

Nao executar `npm audit fix` automaticamente. Vulnerabilidades encontradas
devem ser analisadas antes de qualquer outra atualizacao de dependencia.

## Criterios de aceite

- `package.json` referencia exatamente `sqlite3@6.0.1`.
- `package-lock.json` esta consistente com a versao declarada.
- `allowScripts` aprova somente a versao revisada do `sqlite3`.
- `npm ci --omit=dev` conclui com codigo zero.
- O npm nao informa que o script do `sqlite3@6.0.1` esta pendente de aprovacao.
- O teste SQLite em memoria confirma escrita, leitura, metadados de execucao e
  fechamento da conexao.
- Nenhum banco real em `database/` ou `src/database/` foi alterado pela
  implementacao ou pelos testes isolados.
- A aplicacao inicia, responde HTTP 200 e acessa dados normalmente.
- O worker de agendamentos conclui sem erro quando validado.
- A pagina de ambiente de dados exibe a versao correta do driver.
- O identificador de release foi incrementado conforme `AGENTS.md`.
- O diff nao contem atualizacoes de dependencias fora do escopo.

## Riscos e cuidados

- `sqlite3` e um modulo nativo; falhas no download do binario podem acionar uma
  compilacao local via `node-gyp`.
- O certificado corporativo pode impedir acesso ao registro npm. Corrigir a
  cadeia de confianca; nunca contornar com `strict-ssl=false`.
- O novo driver pode incluir uma versao mais recente do engine SQLite. Criar
  snapshot antes do deploy e preservar o rollback operacional existente.
- Nao testar gravacao usando `database/pspanel.sqlite` ou qualquer banco real.
- Nao executar migracoes destrutivas, vacuum ou conversao de formato como parte
  desta atualizacao.
- Nao remover backups, arquivos WAL ou SHM manualmente.
- A atualizacao reduz avisos e melhora compatibilidade, mas nao elimina o risco
  estrutural de depender de um projeto arquivado.

## Rollback

Se houver incompatibilidade:

1. restaurar `package.json` e `package-lock.json` para `sqlite3@5.1.7`;
2. restaurar a entrada `allowScripts` para refletir a versao efetivamente
   instalada ou removê-la se ela nao existia antes;
3. executar `npm ci --omit=dev` com o lockfile restaurado;
4. validar novamente o carregamento do driver e o health check;
5. em producao, usar o snapshot criado pelo fluxo de deploy quando necessario.

Nao deve haver rollback de schema ou dados, pois esta task nao cria migracao de
banco.

## Evolucao posterior

Criar uma task independente para avaliar a remocao de `node-sqlite3` e a
migracao do adaptador central para `node:sqlite` ou outro driver mantido. Essa
avaliacao deve considerar concorrencia, bloqueio do event loop, compatibilidade
com o contrato assíncrono atual e estabilidade da API na versao homologada do
Node.js.

---

## Assinatura da LLM

- Data: 2026-08-11 14:20:52 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao

---

## Resultado da implementacao

Status: concluida em 2026-08-11.

- Dependencia atualizada e fixada em `sqlite3@6.0.1`.
- Script de instalacao aprovado exclusivamente para `sqlite3@6.0.1`.
- Lockfile atualizado somente na arvore necessaria ao novo driver.
- Instalacao limpa validada com `npm ci --omit=dev`, sem pendencia
  `allow-scripts`.
- Driver `6.0.1` validado com engine SQLite `3.52.0` em banco `:memory:`.
- Contrato de insercao, `lastID`, `changes`, consulta e fechamento validado.
- Aplicacao autenticada e pagina de ambiente de dados validadas em servidor
  temporario na porta 3100, usando banco temporario.
- Worker validado separadamente com banco temporario vazio.
- Bancos reais do repositorio nao foram abertos pelos testes funcionais desta
  implementacao.
- Release atualizada para `v2026.08.11-051`.

Avisos remanescentes conhecidos:

- `prebuild-install@7.1.3`, dependencia do proprio `sqlite3@6.0.1`;
- pacotes da arvore de `ldapjs@3.0.7`, fora do escopo desta task;
- auditoria npm com tres ocorrencias nas arvores de `body-parser`/`express` e
  `ejs`, sem aplicacao automatica de `npm audit fix`.

---

## Assinatura da LLM

- Data: 2026-08-11 14:31:05 -03:00
- Modelo: GPT-5
- Versao: nao informado
- Acao: atualizacao
