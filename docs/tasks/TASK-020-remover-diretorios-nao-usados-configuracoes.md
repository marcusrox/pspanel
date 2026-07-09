# TASK-020 - Remover diretorios nao usados da tela de Configuracoes

## Contexto

Na tela de Configuracoes (`/settings`), a secao Diretórios exibe os campos:

- `Diretório de Scripts`, persistido como `scripts.directory`;
- `Diretório de Logs`, persistido como `scripts.log_directory`.

Esses parametros aparecem em `views/settings.ejs`, possuem valores padrao em `src/models/Settings.js` e sao validados em `src/controllers/settingsController.js`. Porem, a aplicacao nao usa esses valores para localizar scripts ou logs.

Manter campos editaveis que nao afetam o comportamento pode confundir administradores e sugerir uma configuracao inexistente.

## Objetivo

Remover da tela `/settings` os parametros de Diretorio de Scripts e Diretorio de Logs, eliminando tambem defaults, validacoes e referencias de codigo relacionadas, sem deixar residuos visiveis ou persistencias novas para esses parametros.


## Escopo

- Remover da view `views/settings.ejs` a secao/campos de diretorios nao usados.
- Remover do controller de configuracoes o tratamento de `scripts.directory` e `scripts.log_directory`.
- Remover de `Settings.initialize()` os defaults para:
  - `scripts.directory`;
  - `scripts.log_directory`.
- Confirmar que nenhum fluxo ativo depende dessas chaves antes de remove-las.
- Manter a configuracao `scripts.max_execution_time`, pois ela ainda pode ser util para regras de execucao.
- Ajustar textos, espacamentos e estrutura visual da tela para nao deixar lacunas ou titulos vazios.
- Atualizar documentacao tecnica que mencione essas configuracoes como padrao ativo, se necessario.

## Fora de escopo

- Alterar o diretorio real de scripts executaveis (`scripts-ps/`).
- Criar configuracao nova para diretorio de scripts.
- Criar configuracao nova para diretorio de logs.
- Migrar, limpar ou editar diretamente bancos SQLite em `database/`.
- Remover dados historicos ja existentes no banco local para essas chaves.
- Alterar o mecanismo de log web.
- Alterar execucao manual, agendada ou worker de scripts.
- Enfraquecer validacoes de seguranca sobre nomes e caminhos de scripts.

## Arquivos provaveis

```text
views/settings.ejs
src/controllers/settingsController.js
src/models/Settings.js
docs/patterns.md
```

`docs/patterns.md` deve ser alterado apenas se a implementacao confirmar que ele ainda documenta `scripts.directory` ou `scripts.log_directory` como configuracoes esperadas.

## Requisitos funcionais

1. Ao abrir `/settings`, a tela nao deve mais exibir `Diretório de Scripts`.
2. Ao abrir `/settings`, a tela nao deve mais exibir `Diretório de Logs`.
3. O formulario de configuracoes nao deve enviar `scripts.directory` nem `scripts.log_directory`.
4. Salvar configuracoes deve continuar funcionando para os demais parametros existentes.
5. A tela nao deve exibir uma secao Diretórios vazia ou qualquer texto residual sobre esses caminhos.
6. A aplicacao deve continuar usando `scripts-ps/` para scripts executaveis.
7. A aplicacao deve continuar usando seus caminhos reais atuais para logs, sem depender das chaves removidas.
8. Registros antigos dessas chaves no SQLite local nao devem reaparecer na interface.

## Requisitos tecnicos

- Manter CommonJS (`require`, `module.exports`).
- Manter mensagens ao usuario em portugues.
- Nao alterar `.env`, `.env.example`, `package.json`, `package-lock.json`, arquivos SQLite ou scripts em `scripts-ps/`.
- Nao adicionar dependencia externa.
- Nao criar migracao destrutiva para apagar dados locais.
- Usar busca por `scripts.directory`, `scripts.log_directory`, `Diretório de Scripts` e `Diretório de Logs` para confirmar ausencia de residuos relevantes apos a alteracao.
- Preservar o comportamento das demais configuracoes da tela.

## Sugestao de implementacao

1. Em `views/settings.ejs`, remover os campos relacionados a:
   - `settings.scripts?.directory`;
   - `settings.scripts?.log_directory`.
2. Se a secao Diretórios ficar sem conteudo, remover tambem seu titulo e bloco visual.
3. Em `src/controllers/settingsController.js`, remover validacoes e atualizacoes para:
   - `updates['scripts.directory']`;
   - `updates['scripts.log_directory']`.
4. Em `src/models/Settings.js`, remover os defaults de `Settings.initialize()` para:
   - `scripts.directory`;
   - `scripts.log_directory`.
5. Revisar `docs/patterns.md` e remover ou ajustar a mencao dessas chaves se ela passar a ser enganosa.
6. Procurar residuos com:

```powershell
rg -n "scripts\.directory|scripts\.log_directory|Diretório de Scripts|Diretório de Logs"
```

7. Validar que apenas mencoes historicas aceitaveis, se houver, permanecem.

## Criterios de aceite

- `/settings` nao mostra mais Diretorio de Scripts nem Diretorio de Logs.
- O HTML renderizado da tela nao contem os nomes `scripts.directory` ou `scripts.log_directory`.
- Salvar configuracoes continua funcionando para os demais campos.
- `Settings.initialize()` nao cria novamente defaults para essas chaves.
- O controller nao valida nem persiste essas chaves a partir do formulario.
- A busca por residuos nao encontra referencias ativas aos campos removidos.
- Nenhum arquivo SQLite local e editado diretamente.
- A execucao de scripts continua restrita ao diretorio `scripts-ps/`.

## Testes sugeridos

- Rodar `node --check src\controllers\settingsController.js`.
- Rodar `node --check src\models\Settings.js`.
- Renderizar `views/settings.ejs` com dados simulados, se pratico, e confirmar que nao ha erro de template.
- Abrir `/settings` com a aplicacao em execucao e confirmar visualmente que a secao Diretórios foi removida.
- Salvar a tela de configuracoes e confirmar que os demais parametros persistem normalmente.
- Rodar a busca por residuos:

```powershell
rg -n "scripts\.directory|scripts\.log_directory|Diretório de Scripts|Diretório de Logs"
```

## Validacao esperada

- `node --check src\controllers\settingsController.js`
- `node --check src\models\Settings.js`
- Validacao visual de `/settings` com usuario autenticado.
- Busca por residuos com `rg`.

Se a validacao visual exigir login, usar os dados do `.env` apenas localmente e nunca imprimir seu conteudo em logs, respostas ou arquivos de documentacao.
