# TASK-055 - Configurar politica de retentativas dos agendamentos

## Contexto

O worker de agendamentos executa os registros vencidos de `schedules` e, quando
uma execucao falha, substitui `next_run_at` por um instante calculado como
`agora + 5 minutos`. Esse intervalo e definido pela constante
`RETRY_AFTER_FAIL_MIN` em `src/models/Schedule.js`.

Atualmente nao existe limite para a quantidade de retentativas. Enquanto o
agendamento permanecer habilitado e a causa da falha continuar presente, cada
erro agenda uma nova tentativa. Isso pode produzir execucoes e registros de
historico indefinidamente, mesmo quando a recorrencia cron normal do
agendamento acontece apenas uma vez por dia.

O problema fica especialmente visivel em falhas permanentes ou operacionais,
como script inexistente, parametros obrigatorios ausentes, dependencia externa
indisponivel ou acesso negado a uma automacao COM.

## Objetivo

Permitir que um administrador configure na tela `/settings`:

1. o intervalo, em minutos, antes de uma nova tentativa;
2. a quantidade maxima de retentativas por ocorrencia agendada.

Persistir a contagem da ocorrencia atual, interromper o ciclo quando o limite
for atingido e preservar a recorrencia cron para as ocorrencias futuras.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes de produto

### Configuracoes globais

Adicionar as configuracoes persistidas:

| Chave | Padrao | Limites | Descricao |
| --- | ---: | ---: | --- |
| `schedules.retry_interval_minutes` | `5` | `1` a `1440` | Minutos entre uma falha e a proxima tentativa |
| `schedules.max_retry_attempts` | `3` | `0` a `20` | Numero maximo de retentativas depois da tentativa original |

Os valores sao globais e se aplicam a todos os agendamentos executados pelo
worker. Configuracao especifica por agendamento fica fora desta primeira
versao.

O valor `0` em `schedules.max_retry_attempts` desativa novas retentativas. Por
exemplo, o valor `3` representa no maximo quatro execucoes para uma mesma
ocorrencia: a tentativa original e ate tres retentativas.

Alteracoes de configuracao devem ser usadas nas decisoes tomadas depois que os
novos valores forem salvos. Uma retentativa que ja esteja materializada em
`next_run_at` nao precisa ser cancelada retroativamente nesta versao; ao
terminar, o worker deve aplicar o limite vigente para decidir se agenda outra.

### Limite por ocorrencia

O limite pertence a uma ocorrencia do agendamento, e nao ao tempo de vida do
registro. Ao encerrar a ocorrencia por sucesso ou esgotamento, o contador deve
voltar a zero antes da proxima ocorrencia cron.

Adicionar em `schedules`:

| Campo | Tipo | Uso |
| --- | --- | --- |
| `retry_attempt_count` | `INTEGER NOT NULL DEFAULT 0` | Numero da retentativa atualmente materializada em `next_run_at`; zero indica uma ocorrencia normal |

Aplicar restricao para impedir valores negativos. Nao reutilizar
`last_run_exit_code` como contador e nao inferir a quantidade consultando o
historico, pois o estado operacional deve permanecer deterministico mesmo que
registros antigos sejam removidos futuramente.

### Fluxo depois de falha

Para qualquer falha controlada pelo worker, incluindo script invalido,
validacao de parametros, falha ao iniciar o processo e codigo de saida sem
sucesso:

1. ler a politica global validada;
2. considerar `retry_attempt_count = 0` como falha da tentativa original;
3. se `retry_attempt_count < max_retry_attempts`:
   - incrementar o contador;
   - manter o agendamento habilitado;
   - definir `next_run_at` como `agora + retry_interval_minutes`;
   - registrar que uma nova retentativa foi agendada;
4. caso contrario, considerar a ocorrencia esgotada e nao agendar outra
   retentativa para ela.

Exemplo com limite `3`:

| Execucao que falhou | Contador antes da falha | Resultado |
| --- | ---: | --- |
| Tentativa original | `0` | Agenda retentativa `1` |
| Retentativa 1 | `1` | Agenda retentativa `2` |
| Retentativa 2 | `2` | Agenda retentativa `3` |
| Retentativa 3 | `3` | Esgota a ocorrencia |

O intervalo e contado a partir do termino da tentativa que falhou. A execucao
real continua ocorrendo na primeira passagem do worker posterior a
`next_run_at`; portanto, a precisao depende da frequencia e disponibilidade da
tarefa externa que aciona `scripts-js/schedule-worker.js`.

### Fluxo depois de sucesso

Depois de qualquer sucesso, inclusive sucesso em uma retentativa:

- zerar `retry_attempt_count`;
- para `cron`, calcular a proxima ocorrencia futura pela expressao cron;
- para `once`, desabilitar o agendamento e manter a sentinela operacional ja
  utilizada pelo projeto;
- preservar historico e auditoria existentes.

### Fluxo ao esgotar o limite

Para agendamento `cron`:

- nao desabilitar definitivamente o agendamento;
- zerar `retry_attempt_count`;
- calcular a primeira ocorrencia cron estritamente posterior ao instante
  atual;
- nao tentar recuperar novamente a ocorrencia que falhou;
- nao executar uma rajada de ocorrencias perdidas.

Para agendamento `once`:

- zerar `retry_attempt_count`;
- desabilitar o agendamento;
- manter a sentinela de proxima execucao usada no fluxo atual;
- deixar claro na auditoria que a execucao unica terminou com o limite de
  retentativas esgotado.

Execucoes manuais de scripts nao devem usar essa politica nem alterar o
contador dos agendamentos.

## Centralizacao da politica

Centralizar defaults, limites, conversao e leitura da politica em um helper ou
service, por exemplo:

```text
src/services/scheduleRetryPolicy.js
```

Esse componente deve:

- expor os nomes das duas chaves;
- expor defaults e limites em um unico lugar;
- converter valores persistidos como texto para inteiros;
- rejeitar valores de formulario fora dos limites;
- fornecer fallback seguro para os defaults se um valor persistido legado for
  invalido;
- carregar a politica para o worker sem duplicar regras no controller e no
  model.

Uma configuracao invalida no banco nao deve derrubar todo o worker nem liberar
retentativas ilimitadas. Nesse caso, usar o default seguro e registrar aviso
objetivo, sem dados sensiveis.

## Configuracoes e controller

Atualizar `src/models/Settings.js` para criar os dois valores padrao com
`setDefault`, preservando configuracoes ja existentes.

Atualizar `src/controllers/settingsController.js` para:

- incluir somente as duas novas chaves na allowlist de configuracoes aceitas;
- converter os valores em base decimal;
- exigir numeros inteiros dentro dos limites definidos;
- persistir a representacao textual normalizada;
- manter mensagens de validacao em portugues;
- nao aceitar chaves arbitrarias enviadas pelo navegador.

Salvar configuracoes nao deve modificar diretamente linhas de `schedules`,
executar o worker nem criar registros de historico.

## Tela de configuracoes

Adicionar em `views/settings.ejs` uma secao recolhivel chamada
**Agendamentos e retentativas**, seguindo o accordion e o estilo existentes.

Campos:

- **Intervalo entre retentativas (minutos)**;
- **Maximo de retentativas por ocorrencia**.

Usar `input type="number"` com `min`, `max`, `step="1"` e valores padrao
coerentes. Exibir textos auxiliares informando que:

- o intervalo real depende da frequencia do worker;
- `0` desativa novas retentativas;
- a tentativa original nao entra na quantidade configurada;
- ao esgotar o limite, uma recorrencia cron segue para sua proxima ocorrencia.

Os valores devem ser escapados com `<%= ... %>`. A validacao do navegador e
apenas auxiliar; o servidor continua sendo a fonte de verdade.

Incluir a nova secao no estado do accordion salvo pelo JavaScript existente,
sem reescrever a tela inteira.

## Migration e persistencia

Adicionar uma migration posterior a `004_add_users_and_audit_trails` para criar
`retry_attempt_count` em `schedules`.

A migration deve:

- preservar todos os agendamentos e auditorias existentes;
- inicializar registros atuais com contador `0`;
- ser atomica e idempotente pelo mecanismo de `schema_migrations`;
- manter `idx_schedules_due` e todas as colunas atuais;
- nao alterar manualmente `database/pspanel.sqlite`.

Como o SQLite possui limitacoes para adicionar `CHECK` a uma tabela existente,
a implementacao deve avaliar uma reconstrucao atomica da tabela ou garantir a
invariante no model e na migration de forma testada. Nao descartar nem
renumerar agendamentos para simplificar a alteracao.

Atualizar tambem o schema-base de `001_create_core_tables` para que uma
instalacao nova ja nasca com a coluna. A migration posterior continua
necessaria para bancos existentes.

## Model e worker

Refatorar de forma localizada `src/models/Schedule.js` para remover a constante
fixa `RETRY_AFTER_FAIL_MIN` e aplicar uma unica funcao de decisao de retry em
todos os caminhos de falha.

Evitar manter blocos independentes calculando retry, pois hoje existem varios
caminhos que gravam `agora + 5 minutos`. A funcao compartilhada deve receber o
agendamento, a politica e o resultado da falha, e devolver o estado a persistir
sem duplicar a semantica.

`recordRunResult` deve persistir `retry_attempt_count` junto com os demais
campos operacionais. Toda transicao deve limpar `worker_lock_until`, inclusive
ao esgotar o limite.

Manter as protecoes existentes:

- scripts restritos a `scripts-ps/`;
- validacao de nome e existencia do `.ps1`;
- validacao de parametros obrigatorios;
- `spawn` com array de argumentos;
- separacao e limite de output;
- historico com `Agendamento (worker)`;
- lock contra execucoes concorrentes.

O bootstrap `scripts-js/schedule-worker.js` deve continuar pequeno e delegar a
execucao ao model. Nao criar timer interno, daemon ou nova tarefa do Windows.

## Auditoria e diagnostico

Os eventos de conclusao ou erro do worker devem registrar, quando aplicavel:

- `retry_attempt_count`;
- `max_retry_attempts`;
- `retry_interval_minutes`;
- se uma nova retentativa foi agendada;
- `next_run_at` calculado;
- se o limite foi esgotado;
- se o destino seguinte foi a proxima ocorrencia cron ou a desativacao de um
  agendamento unico.

Pode-se adicionar acoes explicitas `RETRY_SCHEDULED` e `RETRY_EXHAUSTED` se
isso melhorar a consulta, desde que os eventos existentes
`EXECUTE_START`, `EXECUTE_ERROR` e `EXECUTE_FINISH` continuem compativeis.

Nao incluir parametros do script, credenciais, tokens ou conteudo integral do
output nos novos detalhes de auditoria.

Na lista `views/schedules.ejs`, mostrar de forma compacta quando
`retry_attempt_count > 0`, por exemplo **Retentativa 2 de 3**, junto da proxima
execucao. Nao alterar a expressao cron exibida nem fazer o usuario confundir o
instante temporario de retry com a recorrencia permanente.

## Arquivos previstos

```text
src/database/schema.js
src/database/migrations/addScheduleRetryAttemptCount.js
src/models/Settings.js
src/services/scheduleRetryPolicy.js
src/controllers/settingsController.js
src/models/Schedule.js
views/settings.ejs
views/schedules.ejs
docs/architecture.md
src/config/release.js
```

Alterar `scripts-js/schedule-worker.js` somente se uma integracao minima for
necessaria. Nao alterar rotas nem `app.js`, pois os fluxos atuais de
configuracao e agendamentos ja estao registrados e autenticados.

Ao concluir a implementacao, atualizar `src/config/release.js`, incrementando o
numero sequencial global em 1 e usando a data atual do ambiente, conforme
`AGENTS.md`.

## Seguranca e compatibilidade

- Validar os dois campos no servidor, independentemente dos atributos HTML.
- Usar placeholders nas operacoes SQLite.
- Nao aceitar valores negativos, fracionarios, vazios, `NaN` ou acima dos
  limites.
- Nao transformar falha de leitura de configuracao em retry ilimitado.
- Nao remover agendamentos, historicos ou auditorias existentes.
- Nao alterar `.env`, arquivos SQLite reais, WAL, SHM, backups,
  `package-lock.json` ou dependencias.
- Nao enfraquecer autenticacao, sessao, validacao de scripts ou locks.
- Preservar mensagens de usuario em portugues.
- Preservar CommonJS.

## Fora de escopo

- Configuracao individual de retry por agendamento.
- Backoff exponencial, jitter ou calendarios diferentes por tipo de erro.
- Retry de execucoes manuais.
- Cancelamento retroativo de uma retentativa ja materializada em
  `next_run_at`.
- Alteracao automatica da frequencia da Tarefa Agendada do Windows.
- Criacao de daemon ou fila externa.
- Notificacao por email a cada falha ou ao esgotar o limite.
- Correcao da causa funcional dos scripts que estao falhando.
- Implementar esta task neste momento.

## Criterios de aceite

- A tela de configuracoes permite definir intervalo e limite global de
  retentativas.
- Os valores padrao sao respectivamente `5` minutos e `3` retentativas.
- O controller aceita somente inteiros nos limites definidos.
- O valor `0` impede que uma falha agende nova retentativa.
- O banco persiste `retry_attempt_count` com default `0` sem perder dados
  existentes.
- O worker nao possui mais intervalo de retry fixo espalhado nos caminhos de
  falha.
- Script invalido, parametros ausentes e falha do PowerShell usam a mesma
  politica.
- Com limite `3`, nunca sao agendadas mais de tres retentativas para uma
  ocorrencia.
- Sucesso zera o contador e retoma o fluxo normal do tipo de agendamento.
- Esgotamento em `cron` preserva o agendamento e avanca para a proxima
  ocorrencia futura.
- Esgotamento em `once` desabilita o agendamento.
- A lista diferencia uma proxima retentativa da recorrencia cron permanente.
- Historico e auditoria permitem identificar retentativa agendada e limite
  esgotado sem expor dados sensiveis.
- Execucoes manuais permanecem inalteradas.
- O controle de release e atualizado somente quando a implementacao for
  concluida.

## Testes sugeridos

### Politica de retry

Adicionar testes focados com `node:test` ou estrutura equivalente, sem novo
framework, cobrindo:

- leitura dos defaults `5` e `3`;
- limites minimo e maximo de cada configuracao;
- rejeicao de vazio, decimal, negativo, texto e valores acima do limite;
- fallback seguro diante de valor persistido invalido;
- limite `0` sem nova retentativa;
- limite `1` com exatamente uma retentativa;
- limite `3` com exatamente tres retentativas;
- calculo de `next_run_at` a partir do termino da falha;
- mudanca de configuracao durante uma sequencia de retry.

### Migration

Em banco temporario, nunca no banco real do workspace:

- criar o schema anterior com agendamentos de exemplo;
- executar a migration e confirmar preservacao dos registros e IDs;
- confirmar `retry_attempt_count = 0` nos registros existentes;
- confirmar default e protecao contra contador negativo;
- executar a inicializacao novamente e confirmar idempotencia;
- simular falha intermediaria e confirmar rollback integral;
- criar banco vazio e confirmar que o schema-base ja inclui a coluna.

### Model e worker

- simular falha de script inexistente ate esgotar o limite;
- simular parametros obrigatorios ausentes ate esgotar o limite;
- simular codigo de saida de erro ate esgotar o limite;
- confirmar que cada falha agenda `agora + intervalo configurado`;
- simular sucesso na primeira e na ultima retentativa;
- confirmar reset do contador depois de sucesso;
- confirmar retorno ao cron depois de sucesso e depois de esgotamento;
- confirmar desativacao de `once` depois de esgotamento;
- confirmar limpeza do lock em todas as saidas;
- confirmar que duas instancias concorrentes nao duplicam uma retentativa;
- confirmar historico e detalhes de auditoria sem parametros sensiveis.

### Validacao sintatica e de templates

```powershell
node --check src\database\schema.js
node --check src\database\migrations\addScheduleRetryAttemptCount.js
node --check src\models\Settings.js
node --check src\services\scheduleRetryPolicy.js
node --check src\controllers\settingsController.js
node --check src\models\Schedule.js
node --check src\config\release.js
```

Compilar `views/settings.ejs` e `views/schedules.ejs` com EJS para detectar
erros de template.

### Validacao HTTP e visual

Usar `PORT=3100` ou a proxima porta livre, nunca a porta `3000`, conforme
`AGENTS.md`:

- abrir `/settings` e confirmar valores padrao e persistencia;
- validar mensagens para valores fora dos limites;
- conferir a nova secao em desktop e viewport mobile;
- navegar por teclado e verificar labels, hints e estado do accordion;
- confirmar a indicacao de retentativa na lista de agendamentos;
- capturar o PID do servidor temporario e encerrar somente esse processo.

## Validacao esperada na implementacao

- Executar os testes focados da politica, migration e model em banco
  temporario.
- Executar `node --check` em todos os JavaScript alterados.
- Compilar as duas views EJS alteradas.
- Executar `git diff --check`.
- Fazer validacao funcional e visual autenticada na porta autorizada.
- Confirmar que nenhum `.env`, banco real, WAL, SHM, backup ou `node_modules`
  foi incluido no diff.
- Nao executar `npm test`, pois o script atual nao possui testes reais.

---

## Assinatura da LLM

- Data: 2026-08-17 10:44:23 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
