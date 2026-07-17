# TASK-045 - Substituir repeticao por minutos por recorrencia cron

## Contexto

O cadastro de agendamentos em `/schedules` permite atualmente informar uma
primeira/proxima execucao e, opcionalmente, `repeat_interval_minutes`. Depois de
uma execucao bem-sucedida, o model calcula o proximo horario somando esse
intervalo ao instante em que o worker terminou.

Esse modelo nao representa regras de calendario, como:

- executar toda segunda e sexta-feira as 08:00;
- executar todos os dias, a cada hora;
- executar somente as segundas-feiras, a cada 5 minutos.

Esta task substitui integralmente a repeticao por minutos por recorrencia cron.
Nao e necessario preservar os agendamentos existentes. A migration pode
descartar os registros atuais da tabela `schedules` e remover definitivamente a
coluna `repeat_interval_minutes`.

## Objetivo

Permitir dois tipos de agendamento:

1. **Execucao unica**, em uma data e hora informadas pelo usuario;
2. **Recorrencia cron**, configurada por um formulario visual de dias e
   frequencia, sem exigir que o usuario conheca a sintaxe cron.

Persistir uma expressao cron de cinco campos como fonte de verdade da
recorrencia e continuar materializando a proxima ocorrencia em `next_run_at`, em
UTC, para que o worker mantenha a busca simples por trabalhos vencidos.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

A futura implementacao contem uma migration destrutiva e deve deixar isso
visivel antes de sua execucao:

- todos os registros existentes de `schedules` serao descartados;
- `repeat_interval_minutes` sera removida do schema;
- nao havera conversao dos intervalos atuais para cron;
- os eventos existentes de `schedule_audit` devem ser preservados, mas seus
  `schedule_id` antigos devem ser definidos como `NULL` para impedir associacao
  acidental com IDs reutilizados por novos agendamentos.

Nao alterar arquivos SQLite manualmente. A mudanca deve ocorrer exclusivamente
pela migration versionada em `src/database/schema.js`.

## Decisoes de produto

- Nao manter modo legado de intervalo.
- Nao manter compatibilidade de payload com `repeat_interval_minutes`.
- Cron sera o unico mecanismo de repeticao.
- O formulario principal sera visual; a expressao cron sera gerada pela
  aplicacao.
- Nao oferecer editor de cron livre nesta primeira versao.
- Usar cron padrao de cinco campos: minuto, hora, dia do mes, mes e dia da
  semana. Nao aceitar campo de segundos nem macros como `@daily`.
- A primeira versao cobirira recorrencias semanais com dias selecionados,
  horario fixo, intervalo regular em minutos ou intervalo regular em horas.
- `next_run_at` continuara sendo o indice operacional usado pelo worker.
- Horarios persistidos em `next_run_at` continuarao sendo strings ISO UTC.
- A regra cron sera interpretada no fuso `America/Sao_Paulo`, persistido no
  agendamento para nao depender do fuso configurado no servidor.
- Ocorrencias perdidas enquanto o worker estiver parado serao consolidadas em
  uma unica execucao ao retornar. Nao executar uma rajada de ocorrencias
  atrasadas.
- A precisao real depende da frequencia do Task Scheduler que chama o worker.

## Exemplos obrigatorios

O formulario deve conseguir gerar, salvar, editar, descrever e executar pelo
menos estas configuracoes:

| Configuracao | Expressao persistida |
| --- | --- |
| Segunda e sexta-feira as 08:00 | `0 8 * * 1,5` |
| Todos os dias, a cada hora | `0 * * * *` |
| Segunda-feira, a cada 5 minutos | `*/5 * * * 1` |

Na convencao adotada, domingo e `0`, segunda-feira e `1` e sabado e `6`.

## Experiencia do formulario

Atualizar `views/schedule-form.ejs` para substituir os campos atuais de tempo e
repeticao por uma secao **Quando executar**.

### Tipo de agendamento

Oferecer duas opcoes mutuamente exclusivas:

- **Uma vez**;
- **Recorrente**.

Para **Uma vez**:

- exibir `datetime-local` obrigatorio;
- ocultar e desabilitar os controles de recorrencia;
- persistir `schedule_type = 'once'` e `cron_expression = NULL`.

Para **Recorrente**:

- ocultar e desabilitar o `datetime-local` de execucao unica;
- exibir os sete dias da semana como checkboxes;
- oferecer atalho **Todos os dias**;
- exigir pelo menos um dia selecionado;
- exibir o fuso `America/Sao_Paulo` de forma clara;
- permitir escolher uma das cadencias abaixo.

### Cadencias suportadas

1. **Em um horario especifico**
   - campo de hora `HH:mm`;
   - gerar `<minuto> <hora> * * <dias>`.

2. **A cada N minutos**
   - oferecer somente valores que dividam 60 exatamente, inicialmente:
     `1`, `2`, `3`, `4`, `5`, `6`, `10`, `12`, `15`, `20` e `30`;
   - gerar `*/N * * * <dias>`;
   - isso evita representar como regular um intervalo que reiniciaria de forma
     irregular a cada virada de hora.

3. **A cada N horas**
   - oferecer somente valores que dividam 24 exatamente, inicialmente:
     `1`, `2`, `3`, `4`, `6`, `8` e `12`;
   - gerar `0 */N * * <dias>`;
   - `1 hora` deve ser normalizado para `0 * * * <dias>`.

Quando todos os dias estiverem selecionados, normalizar o campo de dia da
semana para `*`. Nos demais casos, ordenar e remover duplicidades antes de
persistir, por exemplo `1,5`.

### Previa e edicao

Antes de salvar, mostrar:

- descricao em portugues, por exemplo `Toda segunda e sexta-feira as 08:00`;
- expressao cron gerada em uma area somente leitura;
- as proximas tres ocorrencias, formatadas em `pt-BR` e no fuso do agendamento.

A previa do navegador e apenas informativa. O controller deve reconstruir e
validar a expressao a partir dos campos enviados, sem confiar no cron calculado
no cliente.

Ao editar, o servidor deve decompor as expressoes suportadas e preencher o
formulario visual. Como esta versao nao aceita cron livre, toda expressao criada
pela aplicacao deve ser reversivel para os controles do formulario.

Usar JavaScript com APIs de DOM seguras, sem inserir dados dinamicos por
`innerHTML`.

## Schema e migration

Adicionar uma nova migration, posterior a `002_add_script_name_to_schedule_audit`.

A tabela final `schedules` deve remover `repeat_interval_minutes` e adicionar:

| Campo | Tipo | Uso |
| --- | --- | --- |
| `schedule_type` | `TEXT NOT NULL` | `once` ou `cron` |
| `cron_expression` | `TEXT` | Expressao cron de cinco campos para recorrencias |
| `schedule_timezone` | `TEXT NOT NULL` | Fuso IANA, inicialmente `America/Sao_Paulo` |

Manter os demais campos operacionais atuais, incluindo `next_run_at`, locks,
ultimo resultado e metadados.

Como a coluna antiga deve ser fisicamente removida e os dados nao precisam ser
preservados, preferir reconstruir a tabela dentro da transacao da migration:

1. definir `schedule_id = NULL` nos registros existentes de `schedule_audit`;
2. criar uma tabela substituta com o schema final;
3. nao copiar os registros da tabela antiga;
4. remover a tabela antiga;
5. renomear a tabela substituta para `schedules`;
6. recriar `idx_schedules_due` em `(enabled, next_run_at)`.

Aplicar restricoes de consistencia equivalentes a:

- `schedule_type IN ('once', 'cron')`;
- tipo `once` exige `cron_expression IS NULL`;
- tipo `cron` exige `cron_expression IS NOT NULL`;
- `schedule_timezone` nao pode ser vazio.

A migration deve ser atomica pelo mecanismo existente de
`schema_migrations`. Se qualquer etapa falhar, a tabela antiga e seus dados nao
podem ser parcialmente removidos.

## Service de recorrencia

Criar:

```text
src/services/scheduleRecurrence.js
```

Centralizar nesse service:

- constantes dos tipos, fuso e cadencias permitidas;
- normalizacao dos dias da semana;
- geracao de cron a partir do formulario;
- validacao estrita da expressao gerada;
- decomposicao das expressoes suportadas para o formulario de edicao;
- calculo da proxima ocorrencia em UTC;
- calculo das proximas tres ocorrencias para previa;
- descricao amigavel em portugues.

Nao duplicar calculo de recorrencia no controller, model, view ou worker.

Adicionar uma biblioteca dedicada de parser cron com suporte a timezone e
horario de verao, preferencialmente `cron-parser`, em versao compativel com o
Node.js e CommonJS usados pelo projeto. Atualizar `package.json` e
`package-lock.json` somente durante a implementacao desta task.

Antes de instalar, confirmar a versao minima de Node.js exigida pela biblioteca
contra o ambiente suportado pelo PS Panel. Nao introduzir ESM no projeto.

## Controller

Atualizar `src/controllers/scheduleController.js` para:

- remover leitura e envio de `repeat_interval_minutes`;
- aceitar e validar `schedule_type`;
- para `once`, validar o `datetime-local` e converter para ISO UTC;
- para `cron`, validar dias, tipo de cadencia e valor permitido;
- gerar a expressao exclusivamente pelo service;
- calcular `next_run_at` pelo service a partir do instante atual;
- rejeitar cron vazio, invalido, fora dos formatos suportados ou com proxima
  ocorrencia incalculavel;
- enviar ao model somente valores normalizados;
- ao editar ou reativar uma recorrencia, recalcular `next_run_at` a partir do
  instante atual;
- manter validacao do nome do script e dos parametros PowerShell;
- manter mensagens ao usuario em portugues;
- incluir tipo, cron, timezone e proxima ocorrencia nos detalhes da auditoria.

O controller nao deve aceitar uma expressao cron arbitraria enviada diretamente
pelo navegador como fonte de verdade.

## Model e worker

Atualizar `src/models/Schedule.js` para persistir os novos campos e remover toda
referencia a `repeat_interval_minutes`.

Depois de uma execucao bem-sucedida:

- `once`: gravar a sentinela operacional ja utilizada, desabilitar o
  agendamento e manter `cron_expression = NULL`;
- `cron`: calcular pelo service a primeira ocorrencia estritamente posterior ao
  instante atual e manter o agendamento habilitado.

Depois de uma falha:

- manter a tentativa em 5 minutos ja existente;
- nao modificar `cron_expression`, `schedule_type` ou `schedule_timezone`;
- quando uma tentativa posterior terminar com sucesso, voltar a calcular a
  proxima ocorrencia pela regra cron a partir daquele instante;
- se a tentativa coincidir com uma ocorrencia cron, executar somente uma vez.

Quando o worker encontrar uma recorrencia muito atrasada, executar uma vez e
calcular a proxima ocorrencia futura. Nao iterar por todas as ocorrencias
perdidas.

Manter as protecoes existentes de script, parametros, lock, historico, limite
de output e auditoria. Nao ampliar `ExecutionPolicy Bypass` alem do fluxo atual.

O bootstrap `scripts-js/schedule-worker.js` nao deve receber logica de cron; ele
deve continuar delegando ao model/service.

## Lista de agendamentos

Atualizar `views/schedules.ejs`:

- substituir a coluna **Repetir (min)** por **Recorrencia**;
- mostrar `Uma vez` para `once`;
- mostrar a descricao amigavel para `cron`;
- manter **Proxima execucao** com data/hora local;
- mostrar o fuso da regra em texto auxiliar ou nos detalhes;
- manter os parametros e outputs mascarados conforme o fluxo atual;
- nao renderizar cron ou descricoes com HTML nao escapado.

Se `next_run_at` representar uma tentativa apos falha, a tela pode continuar
mostrando esse instante como proxima execucao; o detalhe da ultima execucao deve
deixar o erro visivel pelo fluxo existente.

## Frequencia do worker

O worker e atualmente pensado para ser acionado pelo Task Scheduler, por
exemplo, a cada 5 minutos. A aplicacao nao garante execucao no segundo exato: um
job fica elegivel em `next_run_at` e roda na primeira passagem posterior do
worker.

Para suportar de forma coerente a menor cadencia oferecida pelo formulario,
documentar e recomendar a execucao de
`scripts-ps/Invoke-ScheduleWorker.ps1` a cada **1 minuto**.

Nao criar daemon, timer interno, novo processo permanente nem alterar o Task
Scheduler do Windows automaticamente nesta task.

## Auditoria e diagnostico

Nos eventos `CREATE`, `UPDATE` e `EXECUTE_FINISH`, registrar quando aplicavel:

- `schedule_type`;
- `cron_expression`;
- `schedule_timezone`;
- `next_run_at`;
- `enabled`.

Atualizar `src/services/dataEnvironmentService.js` para substituir o indicador
baseado em `repeat_interval_minutes` por contagens seguras de:

- execucoes unicas;
- recorrencias cron;
- habilitados e desabilitados;
- locks ativos.

Atualizar `docs/architecture.md` para remover a explicacao do intervalo em
minutos e documentar os novos campos e o calculo cron.

## Arquivos provaveis

```text
package.json
package-lock.json
src/database/schema.js
src/services/scheduleRecurrence.js
src/services/dataEnvironmentService.js
src/controllers/scheduleController.js
src/models/Schedule.js
views/schedule-form.ejs
views/schedules.ejs
docs/architecture.md
src/config/release.js
```

Alterar `scripts-js/schedule-worker.js` somente se um ajuste de integracao for
realmente necessario. Nao alterar rotas nem `app.js`, pois as rotas atuais ja
cobrem o CRUD e estao protegidas.

Ao concluir a implementacao, atualizar `src/config/release.js`, incrementando o
numero sequencial em 1 e usando a data/hora atual do ambiente, conforme
`AGENTS.md`.

## Seguranca e validacao

- Manter nomes de scripts restritos a arquivos `.ps1` dentro de `scripts-ps/`.
- Manter rejeicao de `..`, `/` e `\\` no nome do script.
- Continuar usando `spawn` com array de argumentos.
- Nao registrar parametros sensiveis no log ou na auditoria.
- Validar todo campo novamente no servidor.
- Usar placeholders nas operacoes SQLite.
- Nao usar `eval` para cron, datas ou previa.
- Limitar a expressao aos formatos gerados pelo service.
- Tratar datas invalidas, timezone invalido e ausencia de proxima ocorrencia.
- Escapar descricoes, cron e valores dinamicos nas views com `<%= ... %>`.
- Nao alterar `.env`, arquivos SQLite, `node_modules` ou dados fora da migration.

## Fora de escopo

- Preservar ou converter agendamentos existentes.
- Manter `repeat_interval_minutes` no schema ou no codigo.
- Editor livre de expressoes cron.
- Campo de segundos, macros cron, ano ou sintaxe Quartz.
- Regras mensais, ultimo dia util ou excecoes de calendario.
- Janelas intradiarias com horario inicial/final.
- Fuso configuravel pelo usuario.
- Executar todas as ocorrencias perdidas durante indisponibilidade.
- Criar daemon ou alterar o Task Scheduler automaticamente.
- Alterar autenticacao, execucao PowerShell ou parsing de parametros.
- Implementar esta task neste momento.

## Criterios de aceite

- A tabela `schedules` nao possui mais `repeat_interval_minutes`.
- A tabela possui `schedule_type`, `cron_expression` e `schedule_timezone` com
  as restricoes definidas.
- A migration descarta os agendamentos existentes de forma atomica.
- Auditorias existentes sao preservadas com `schedule_id = NULL`.
- O formulario oferece somente **Uma vez** e **Recorrente**.
- O formulario recorrente exige dias e uma cadencia valida.
- Os tres exemplos obrigatorios geram exatamente as expressoes documentadas.
- O usuario nao precisa escrever cron manualmente.
- A previa mostra descricao e proximas tres ocorrencias.
- O servidor ignora qualquer cron calculado no cliente e reconstrui a regra a
  partir dos campos validados.
- Criacao, edicao e reativacao calculam `next_run_at` em ISO UTC.
- A interpretacao usa `America/Sao_Paulo`, independentemente do fuso do
  processo Node.js.
- Execucao unica e desabilitada depois do primeiro sucesso.
- Recorrencia bem-sucedida calcula a proxima ocorrencia futura pelo cron.
- Falha mantem retry em 5 minutos sem perder a regra cron.
- Ocorrencias atrasadas sao consolidadas, sem rajada de execucoes.
- A lista mostra uma descricao amigavel no lugar do intervalo em minutos.
- Auditoria e diagnostico deixam de depender de `repeat_interval_minutes`.
- `docs/architecture.md` descreve o novo comportamento.
- Nenhuma rota autenticada, protecao de script ou mascaramento e enfraquecido.
- O controle de release e atualizado somente ao concluir a implementacao.

## Testes sugeridos

### Service de recorrencia

Adicionar testes focados com `node:test` ou estrutura equivalente, sem introduzir
um framework adicional, cobrindo:

- geracao de `0 8 * * 1,5` para segunda e sexta as 08:00;
- geracao de `0 * * * *` para todos os dias a cada hora;
- geracao de `*/5 * * * 1` para segunda a cada 5 minutos;
- ordenacao e remocao de dias duplicados;
- normalizacao de todos os dias para `*`;
- rejeicao de lista de dias vazia;
- rejeicao de minutos e horas fora das listas permitidas;
- rejeicao de campo de segundos, macro e expressao arbitraria;
- calculo da proxima ocorrencia antes, durante e depois do horario esperado;
- virada de dia, semana, mes e ano;
- calculo no fuso `America/Sao_Paulo` com processo executado em outro fuso;
- decomposicao de cada expressao suportada para o formulario de edicao;
- descricao em portugues e previa de tres ocorrencias.

### Migration

Em banco temporario, nunca no banco real do workspace:

- criar o schema anterior com agendamentos e auditorias de exemplo;
- executar a migration;
- confirmar que `schedules` ficou vazia;
- confirmar ausencia de `repeat_interval_minutes` via `PRAGMA table_info`;
- confirmar novos campos e restricoes;
- confirmar preservacao da auditoria com `schedule_id = NULL`;
- confirmar recriacao de `idx_schedules_due`;
- simular falha intermediaria e confirmar rollback integral;
- executar a inicializacao novamente e confirmar idempotencia.

### Model e worker

- criar e executar um job `once` vencido, confirmando desativacao apos sucesso;
- criar e executar cada cron obrigatorio, confirmando o proximo horario;
- simular worker atrasado e confirmar apenas uma execucao;
- simular falha e confirmar retry em 5 minutos sem alterar a regra;
- simular sucesso no retry e confirmar retorno ao calendario cron;
- confirmar lock, historico e auditoria;
- confirmar rejeicao de script invalido e de parametros obrigatorios ausentes.

### Validacao sintatica e de templates

```powershell
node --check src\database\schema.js
node --check src\services\scheduleRecurrence.js
node --check src\services\dataEnvironmentService.js
node --check src\controllers\scheduleController.js
node --check src\models\Schedule.js
node --check src\config\release.js
```

Compilar `views/schedule-form.ejs` e `views/schedules.ejs` com EJS para detectar
erros de template.

### Validacao HTTP e visual

Usar `PORT=3100` ou a proxima porta livre, nunca a porta `3000`, conforme
`AGENTS.md`:

- criar, editar e excluir execucao unica;
- criar e editar os tres exemplos recorrentes;
- confirmar descricao, cron somente leitura e proximas ocorrencias;
- confirmar mensagens de validacao em portugues;
- confirmar lista e modal de detalhes sem regressao;
- conferir desktop e viewport mobile;
- navegar por teclado pelos tipos, dias e cadencias;
- confirmar que campos ocultos ficam desabilitados e nao sao enviados;
- capturar o PID do servidor temporario e encerrar somente esse processo.

## Validacao esperada na implementacao

- Executar os testes focados do service, migration e model em banco temporario.
- Executar `node --check` em todos os JavaScript alterados.
- Compilar as views EJS alteradas.
- Executar `git diff --check`.
- Fazer validacao funcional e visual autenticada na porta autorizada.
- Confirmar que `package-lock.json` mudou somente pela dependencia cron.
- Confirmar que nenhum `.env`, banco real, WAL, SHM, backup ou `node_modules` foi
  incluido no diff.
- Nao executar `npm test`, pois o script atual nao possui testes reais.

---

## Assinatura da LLM

- Data: 17/07/2026 17:38:27
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
