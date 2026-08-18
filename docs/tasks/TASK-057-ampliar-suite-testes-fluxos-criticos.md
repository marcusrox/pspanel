# TASK-057 - Ampliar suite de testes dos fluxos criticos

## Contexto

A suite atual cobre recorrencia, retentativas, migrations, algumas views, a
montagem dos argumentos do executor e um fluxo especifico do WAHA. Ainda nao
existe cobertura suficiente dos comportamentos basicos que conectam as camadas
do PS Panel: painel, execucao manual, historico, agendamentos, worker,
configuracoes e protecao de acesso.

Antes de usar `npm test` como barreira para publicacao de uma release, a suite
deve detectar regressao nesses fluxos sem executar PowerShell, sem depender de
infraestrutura corporativa e sem acessar os dados locais do ambiente.

## Objetivo

Ampliar a suite `node:test` com uma matriz funcional minima das funcionalidades
basicas do PS Panel, priorizando os fluxos:

```text
painel -> execucao manual -> historico
agendamento -> worker -> historico e auditoria
```

Os testes devem validar a orquestracao implementada em Node.js com filesystem,
processos e integracoes simulados. Nenhum script PowerShell deve ser executado,
lido, analisado ou validado por esta task.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Proibicao de executar ou testar scripts PowerShell

Esta task nao deve:

- iniciar `powershell.exe` ou `pwsh.exe`;
- executar qualquer arquivo `.ps1`;
- ler ou analisar o conteudo dos arquivos em `scripts-ps/`;
- validar sintaxe, help, parametros ou resultado de scripts PowerShell;
- usar os scripts reais do repositorio como fixtures;
- depender de PowerShell instalado na maquina de teste.

Quando um fluxo da aplicacao normalmente iniciaria PowerShell, substituir o
executor por mock ou fake controlado. O teste deve verificar que a aplicacao
solicitou a execucao com os dados esperados e tratou o resultado simulado, sem
criar processo externo.

A cobertura ja existente de `src/services/powerShellRunner.js` pode permanecer,
pois testa apenas funcoes JavaScript puras de montagem de argumentos e
classificacao do resultado. Esta task nao deve ampliar essa cobertura para
executar ou inspecionar scripts `.ps1`.

## Matriz funcional minima

### 1. Painel e catalogo de scripts

Testar o comportamento da aplicacao com o filesystem simulado:

- usuario autenticado recebe a listagem esperada;
- somente entradas representando scripts `.ps1` sao apresentadas;
- outras extensoes e diretorios sao ignorados;
- ausencia ou falha de leitura do diretorio produz resposta controlada;
- a listagem nao permite que caminhos fora do catalogo sejam selecionados.

Nao criar, ler nem analisar um arquivo PowerShell real. Nomes, metadados e
retornos do filesystem devem ser fixtures em memoria.

### 2. Execucao manual

Testar o fluxo Node.js da solicitacao ate o historico, com executor simulado:

- requisicao sem sessao e negada ou redirecionada;
- nome ausente, invalido ou inexistente e rejeitado antes do executor;
- solicitacao valida chama o executor fake uma unica vez;
- argumentos com espacos e acentos chegam ao executor sem perda;
- uma entrada de historico e criada inicialmente como `running`;
- sucesso simulado atualiza o historico para `success` com horario de termino;
- erro simulado atualiza para `error` e preserva diagnostico controlado;
- `stdout` e `stderr` simulados recebem tratamento coerente;
- saida nao confiavel e escapada antes de ser inserida em HTML.

O teste deve falhar se o codigo tentar iniciar processo real.

### 3. Agendamentos

Testar controller, regras e persistencia isolada para:

- listar agendamentos;
- criar agendamento de execucao unica;
- criar agendamento recorrente;
- editar agendamento existente;
- excluir agendamento;
- rejeitar dados obrigatorios ausentes ou invalidos;
- calcular e persistir `next_run_at` de forma coerente;
- registrar auditoria de criacao, atualizacao e exclusao;
- manter mensagens em portugues e redirects esperados.

Usar banco SQLite temporario quando a persistencia real fizer parte do teste.
Nao usar `database/pspanel.sqlite` nem arquivos `-wal` ou `-shm` locais.

### 4. Worker de agendamentos

Testar `Schedule.executeDueJobs()` ou a unidade de orquestracao equivalente,
substituindo completamente o executor externo:

- selecionar somente jobs vencidos, habilitados e sem lock vigente;
- aplicar lock antes de solicitar a execucao;
- registrar `EXECUTE_START` e historico `running`;
- sucesso simulado atualiza historico, auditoria e proxima execucao;
- falha simulada atualiza historico e aplica a politica de retentativas;
- esgotamento da retentativa preserva cron ou desabilita `once` conforme a
  regra existente;
- todos os caminhos finais limpam `worker_lock_until`;
- uma falha em um job nao deixa o worker inteiro em estado inconsistente.

Nenhum teste deve chamar `scripts-js/schedule-worker.js` de forma que ele
execute jobs reais ou abra o banco do ambiente.

### 5. Historico

Testar:

- criacao da entrada inicial;
- atualizacao para sucesso e erro;
- listagem paginada ou consulta usada pela tela;
- detalhe de uma entrada existente;
- resposta controlada para ID inexistente ou invalido;
- preservacao de usuario, origem da execucao, horarios, saida e erro;
- protecao das rotas para usuario sem sessao.

### 6. Configuracoes

Testar:

- carregamento das configuracoes para a tela;
- atualizacao de uma chave permitida com valor valido;
- rejeicao de valor fora dos limites;
- rejeicao de chave arbitraria enviada pelo cliente;
- persistencia da representacao normalizada;
- mensagem amigavel e ausencia de alteracao parcial quando a validacao falha.

### 7. Autenticacao e autorizacao de rotas

Testar, sem conectar ao Active Directory:

- rotas de execucao, historico, configuracoes e agendamentos negam acesso sem
  sessao;
- usuario autenticado alcanca as rotas operacionais permitidas;
- area administrativa continua restrita ao administrador local;
- falha simulada da autenticacao produz resposta controlada e nao cria sessao.

LDAP, grupos AD e credenciais devem ser mocks. Nao fazer bind nem busca real.

## Estrategia de implementacao dos testes

- Permanecer no modulo nativo `node:test` e `node:assert`.
- Preferir testes de comportamento em services, models, controllers e
  middlewares antes de iniciar um servidor HTTP completo.
- Permitir pequenas injecoes de dependencia para filesystem, executor, relogio
  e conexao SQLite quando isso for necessario para isolar o fluxo.
- Evitar alterar contratos publicos das rotas e views apenas para facilitar
  teste.
- Usar diretorios e bancos temporarios exclusivos por teste.
- Restaurar mocks, timers e variaveis de processo em `t.after()`.
- Usar datas fixas ou relogio injetado para evitar testes intermitentes.
- Simular filesystem, LDAP, SMTP, Fortigate, WAHA e processos externos.
- Nao ler nem imprimir o conteudo de `.env`.
- Nao iniciar servidor na porta `3000`.
- Se um teste HTTP for indispensavel, usar porta `3100` ou proxima livre,
  capturar o PID e encerrar somente o processo criado pelo teste.
- Nao instalar um novo framework de testes nesta task.

## Arquivos previstos

```text
test/*.test.js
src/routes/mainRoutes.js
src/middleware/authMiddleware.js
src/routes/historyRoutes.js
src/controllers/scheduleController.js
src/controllers/settingsController.js
src/models/History.js
src/models/Schedule.js
src/models/Settings.js
src/services/powerShellRunner.js
src/config/release.js
```

Os arquivos de producao listados sao possibilidades, nao obrigacoes. Alterar
somente os pontos necessarios para expor dependencias ou regras de forma
testavel, preservando contratos existentes.

## Fora de escopo

- Testes end-to-end contra Active Directory, SMTP ou equipamentos reais.
- Execucao, leitura, parsing ou validacao de arquivos `.ps1`.
- Inicio de `powershell.exe`, `pwsh.exe` ou qualquer processo externo real.
- Alteracao funcional dos scripts mantidos em `scripts-ps/`.
- Medicao ou meta obrigatoria de cobertura percentual.
- Adocao de novo framework.
- Correcao oportunista de todos os riscos descritos em `docs/architecture.md`.
- Testes de carga, alta disponibilidade ou multiplas instancias.
- Alteracao do processo de criacao de tags ou deploy.

## Validacao obrigatoria

```powershell
npm test
node --check app.js
node --check src\routes\mainRoutes.js
```

Executar `node --check` apenas nos arquivos JavaScript efetivamente alterados,
alem do bootstrap quando ele for tocado.

Durante a validacao, confirmar tambem que:

- nenhum processo `powershell.exe` ou `pwsh.exe` foi iniciado pela suite;
- nenhum arquivo de `scripts-ps/` foi lido ou modificado;
- nenhum arquivo em `database/` foi criado ou alterado;
- nenhuma conexao de rede foi realizada.

## Criterios de aceite

- Existe ao menos um cenario de sucesso e um de erro para execucao manual.
- O fluxo manual cobre criacao e conclusao do historico com executor fake.
- O CRUD basico de agendamentos possui cobertura de sucesso e validacao.
- O worker possui cobertura de sucesso, falha, retentativa e limpeza de lock.
- Historico possui cobertura de criacao, atualizacao, listagem e detalhe.
- Configuracoes possuem cobertura de valor valido, invalido e chave nao
  permitida.
- Rotas operacionais negam acesso sem sessao.
- Nenhum teste executa ou analisa scripts PowerShell.
- Nenhum teste inicia `powershell.exe` ou `pwsh.exe`.
- A suite nao depende de rede, credenciais reais ou dados persistentes locais.
- Arquivos temporarios sao removidos ao final dos testes.
- Todos os testes podem ser executados com um unico `npm test`.
- Nenhum banco em `database/` e modificado.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-056 concluida.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-08-18 11:40:41 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Resultado da implementacao

Status: implementada em 2026-08-18.

A suite automatizada passou de 25 para 47 testes. O teste integrado do WAHA,
que iniciava `pwsh.exe`, executava um `.ps1` e abria um servidor HTTP local,
foi preservado como verificacao manual opt-in em
`manual-tests/wahaScript.integration.js` e deixou de fazer parte de
`npm test`.

Foram adicionados 23 cenarios automatizados cobrindo:

- catalogo do painel com filesystem simulado;
- execucao manual em sucesso, erro, validacao de nome, argumentos, historico e
  escape de HTML, sempre com processo fake;
- autenticacao das rotas e restricao da area administrativa;
- criacao, conclusao, listagem e detalhe do historico com banco em memoria;
- listagem, criacao `once`, criacao `cron`, validacao, edicao, exclusao e
  contexto de auditoria dos agendamentos;
- selecao de jobs vencidos, lock, sucesso, falha, retentativa, continuidade do
  worker e limpeza de `worker_lock_until`;
- carregamento e atualizacao de configuracoes, allowlist, normalizacao e
  ausencia de persistencia parcial em erro.

Alteracoes pequenas de producao:

- `Schedule.executeDueJobs()` passou a aceitar dependencias opcionais para
  filesystem, executor, historico, politica, parser e relogio; os defaults
  preservam integralmente o fluxo operacional existente;
- o detalhe do historico passou a rejeitar identificadores invalidos com HTTP
  400 antes de consultar o model.

Validacoes executadas:

- `npm test`: 47 aprovados, 0 falhas;
- `node --test`: 47 aprovados, 0 falhas;
- `node --check app.js` e em todos os JavaScript alterados;
- comparacao dos metadados de `database/` e `scripts-ps/` antes e depois da
  suite, sem qualquer alteracao;
- `git diff --check`.

Nenhuma dependencia, lockfile, credencial, banco local ou script PowerShell
foi alterado. A validacao automatizada final nao iniciou PowerShell nem realizou
conexao de rede.

O release foi atualizado para `v2026.08.18-058`.

---

## Assinatura da LLM

- Data: 2026-08-18 12:00:26 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
