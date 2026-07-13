# TASK-033 - Corrigir timezone no Historico de Execucoes

## Contexto

Foi identificado um problema de exibicao de horario no `Historico de Execucoes`: uma execucao realizada em `13/07/2026 09:55:56` no horario local foi exibida como `13/07/2026 12:55:56`.

A diferenca de 3 horas indica mistura de UTC com horario local. O campo `script_history.start_time` e criado pelo SQLite com `CURRENT_TIMESTAMP`, que grava UTC no formato `YYYY-MM-DD HH:mm:ss`, sem marcador de timezone. Ao exibir esse valor com `new Date(value).toLocaleString('pt-BR')`, a aplicacao pode interpretar o texto como horario local ou tratar de forma inconsistente, gerando deslocamento visual.

O campo `end_time`, por outro lado, ja tende a ser gravado pelo Node com `new Date().toISOString()`, incluindo `Z`. Isso deixa `start_time` e `end_time` com formatos diferentes dentro da mesma tabela.

## Objetivo

Padronizar o registro e a exibicao de datas do historico para que horarios sejam persistidos com timezone claro e exibidos corretamente no horario local do usuario.

## Escopo

- Ajustar o fluxo de criacao de historico em `src/models/History.js`.
- Fazer `History.addEntry()` gravar `start_time` explicitamente com `new Date().toISOString()`.
- Manter `History.updateEntry()` usando ISO para `end_time`.
- Corrigir a exibicao de `start_time` e `end_time` em `views/history.ejs`.
- Normalizar registros antigos de `start_time` no formato SQLite `YYYY-MM-DD HH:mm:ss` como UTC antes de exibir.
- Revisar locais relacionados onde `script_history.start_time` e formatado ou comparado.

## Fora de escopo

- Migrar dados antigos no SQLite alterando valores ja gravados.
- Alterar arquivos SQLite em `database/`.
- Mudar timezone do servidor, do Windows, do Node ou do SQLite.
- Alterar regras de execucao de scripts PowerShell.
- Refatorar todas as telas de data do sistema fora dos pontos afetados pelo historico.

## Arquivos provaveis

- `src/models/History.js`
- `views/history.ejs`
- `src/services/dailySummaryEmailService.js`
- `src/database/schema.js`
- `docs/patterns.md`

## Diagnostico esperado

- Confirmar que `script_history.start_time` e definido por `CURRENT_TIMESTAMP` no schema atual.
- Confirmar que `History.addEntry()` nao informa `start_time` no `INSERT`.
- Confirmar que `views/history.ejs` usa `new Date(entry.start_time).toLocaleString('pt-BR')` diretamente na tabela.
- Confirmar que o modal de detalhes tambem usa `new Date(data.start_time).toLocaleString('pt-BR')`.
- Confirmar que `dailySummaryEmailService` ja possui normalizacao parecida para valores sem `T`, e avaliar se pode reaproveitar ou alinhar a abordagem.

## Requisitos funcionais

1. Novas execucoes manuais devem gravar `start_time` em ISO com timezone, por exemplo `2026-07-13T12:55:56.000Z`.
2. Novas execucoes agendadas registradas no historico devem seguir o mesmo padrao.
3. A tela de Historico deve exibir `13/07/2026, 09:55:56` para uma execucao local equivalente a `2026-07-13T12:55:56.000Z`.
4. Registros antigos no formato `2026-07-13 12:55:56` devem ser interpretados como UTC e exibidos como horario local.
5. A tabela do historico e o modal de detalhes devem usar a mesma regra de formatacao.
6. `end_time` deve continuar exibindo corretamente para registros ISO com `Z`.
7. Datas invalidas ou ausentes devem manter fallback legivel, sem quebrar a tela.

## Requisitos tecnicos

- Nao depender de `CURRENT_TIMESTAMP` para novos registros de historico.
- Usar placeholders `?` em SQL.
- Evitar conversoes ad hoc duplicadas em varios pontos da view; preferir helper local ou compartilhado.
- Normalizar strings antigas `YYYY-MM-DD HH:mm:ss` para ISO UTC antes de criar `Date`.
- Nao alterar dados reais em `database/*.sqlite`.
- Manter textos visiveis em portugues.
- Se criar helper compartilhado, manter CommonJS.

## Sugestao de implementacao

1. Alterar `History.addEntry(scriptName, parameters, username)` para aceitar ou gerar `startTime = new Date().toISOString()`.
2. Atualizar o `INSERT` para incluir `start_time`.
3. Criar um helper de formatacao de data para historico, por exemplo:
   - se o valor tiver `T` ou terminar com `Z`, usar como esta;
   - se estiver no formato SQLite com espaco entre data e hora, trocar o espaco por `T` e adicionar `Z`;
   - se for invalido, retornar o proprio valor ou `—`.
4. Usar esse helper em `views/history.ejs` na tabela e no modal.
5. Revisar `History.findScheduledRunsByDate()` porque ele usa `date(start_time, 'localtime')`; confirmar que continua retornando o dia local correto para registros antigos e novos.
6. Verificar se `dailySummaryEmailService` pode manter o helper atual ou se deve ser alinhado com o novo helper para evitar divergencia futura.

## Pontos de atencao

- `CURRENT_TIMESTAMP` do SQLite grava UTC sem sufixo `Z`; isso e diferente de `new Date().toISOString()`.
- A string `2026-07-13 12:55:56` nao carrega timezone. Para dados existentes nessa tabela, tratar como UTC e a opcao mais compativel com a origem atual.
- Nao converter duas vezes valores que ja estao em ISO com `Z`.
- Nao usar `toLocaleString('pt-BR')` diretamente em valores de origem mista sem normalizar antes.

## Criterios de aceite

- Uma execucao feita as `09:55:56` em horario local aparece no historico como `09:55:56`, nao `12:55:56`.
- O modal de detalhes mostra o mesmo horario da tabela.
- O campo `end_time` continua correto.
- Registros antigos criados com `CURRENT_TIMESTAMP` tambem passam a aparecer no horario local correto.
- O resumo diario de agendamentos nao sofre regressao de data/hora.
- Nenhum arquivo SQLite e alterado durante a implementacao.

## Testes sugeridos

- Rodar `node --check src\\models\\History.js` se o model for alterado.
- Se criar helper JS separado, rodar `node --check` nesse arquivo.
- Validar a sintaxe do JavaScript embutido em `views/history.ejs`, se houver alteracao no script da view.
- Criar uma entrada de historico em ambiente local e confirmar que `start_time` foi salvo em ISO com `Z`.
- Abrir `/history` autenticado e conferir a tabela.
- Abrir o modal de detalhes da entrada e conferir inicio e termino.
- Verificar um registro antigo com `start_time` no formato `YYYY-MM-DD HH:mm:ss` e confirmar a exibicao local correta.

## Validacao esperada

- Validar sintaxe dos arquivos JavaScript alterados.
- Fazer validacao visual/manual da tela `/history` quando houver servidor disponivel.
- Se a validacao visual exigir login, usar apenas credenciais locais ja autorizadas pelo usuario e nao documentar valores sensiveis.

---

## Assinatura da LLM

- Data: 2026-07-13
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao
