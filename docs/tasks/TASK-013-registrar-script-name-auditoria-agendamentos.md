# TASK-013 - Registrar script_name na auditoria de agendamentos

## Contexto

A auditoria de agendamentos (`schedule_audit`) registra eventos como `CREATE`, `UPDATE`, `DELETE`, `EXECUTE_START`, `EXECUTE_ERROR` e `EXECUTE_FINISH`.

Hoje o nome do script pode aparecer apenas dentro de `details`, dependendo da acao. Isso dificulta criar filtros confiaveis em `/schedules/audit`, especialmente para eventos de erro, fim de execucao ou exclusao, onde o agendamento pode nao existir mais ou o JSON pode nao conter o campo no mesmo formato.

Para que a tela `/schedules/audit` possa filtrar por script de forma simples e consistente, cada registro novo de auditoria deve persistir `script_name` em uma coluna propria.

## Objetivo

Adicionar `script_name` como coluna propria de `schedule_audit` e garantir que todos os novos registros de auditoria de agendamentos gravem esse campo sempre que o script relacionado puder ser determinado.

## Escopo

- Alterar a especificacao/schema de `schedule_audit` para incluir `script_name`.
- Criar migracao idempotente para adicionar `script_name` em bancos existentes.
- Atualizar `Schedule.appendAudit` para receber e gravar `script_name`.
- Atualizar todas as chamadas de auditoria de agendamentos para informar o script relacionado.
- Manter `details` para informacoes complementares, sem depender dele como fonte principal do nome do script.
- Criar indice para consultas por `script_name`, se a implementacao de filtro usar essa coluna.
- Manter compatibilidade com registros antigos que nao terao `script_name` preenchido.

## Fora de escopo

- Migrar dados antigos lendo `details` para preencher `schedule_audit.script_name`.
- Recriar, limpar ou editar arquivos SQLite locais em `database/`.
- Implementar coluna visual ou filtro em `/schedules/audit`; isso pertence a TASK-014.
- Implementar paginacao completa da auditoria.
- Alterar regras de execucao de scripts ou calculo de proxima execucao.
- Remover o campo `details`.

## Arquivos provaveis

```text
src/database/schema.js
src/models/Schedule.js
docs/architecture.md
```

## Especificacao de banco

Tabela `schedule_audit` deve passar a ter:

| Campo | Uso |
| --- | --- |
| `id` | Identificador do evento de auditoria. |
| `schedule_id` | Agendamento relacionado, quando aplicavel. |
| `script_name` | Script `.ps1` relacionado ao evento, quando conhecido. |
| `action` | `CREATE`, `UPDATE`, `DELETE`, `EXECUTE_START`, `EXECUTE_ERROR`, `EXECUTE_FINISH`. |
| `username` | Usuario ou worker. |
| `details` | JSON textual com contexto complementar. |
| `created_at` | Data do evento. |

Migracao sugerida:

```sql
ALTER TABLE schedule_audit ADD COLUMN script_name TEXT;
CREATE INDEX IF NOT EXISTS idx_schedule_audit_script_name ON schedule_audit (script_name);
```

Observacao: `script_name` deve ser `TEXT` e permitir `NULL` para manter compatibilidade com auditorias antigas e eventos excepcionais em que o script nao possa ser determinado.

## Requisitos funcionais

1. Todo novo registro de auditoria criado para `CREATE` deve gravar `script_name`.
2. Todo novo registro de auditoria criado para `UPDATE` deve gravar o novo `script_name`.
3. Todo novo registro de auditoria criado para `DELETE` deve gravar o `script_name` do snapshot antes da exclusao.
4. Todo novo registro de auditoria criado pelo worker para inicio, erro e fim de execucao deve gravar o `script_name` do agendamento executado.
5. Registros antigos sem `script_name` devem continuar aparecendo na auditoria sem erro.
6. A tela `/schedules/audit` deve poder usar `schedule_audit.script_name` como fonte primaria para filtro por script na TASK-014.

## Requisitos tecnicos

- Preferir mudar a assinatura de auditoria para algo explicito, por exemplo:

```js
static async appendAudit(scheduleId, action, username, detailsObj, scriptName = null)
```

- Alternativamente, aceitar objeto de opcoes, desde que as chamadas fiquem legiveis.
- Nao obter `script_name` por `JOIN` com `schedules` como fonte primaria do filtro, porque o agendamento pode ser editado ou excluido depois do evento auditado.
- Para `CREATE`, passar o `script_name` criado.
- Para `UPDATE`, passar o novo `script_name`.
- Para `DELETE`, buscar o agendamento antes de excluir e passar `row.script_name` para a auditoria.
- Para `EXECUTE_START`, passar `row.script_name`.
- Para `EXECUTE_ERROR`, passar `row.script_name` mesmo quando o arquivo for invalido ou inexistente.
- Para `EXECUTE_FINISH`, passar `row.script_name` junto com os detalhes de resultado.
- Usar placeholders `?` nas queries SQLite.
- Preservar `details` como JSON textual usando `JSON.stringify`.
- Nao gravar parametros sensiveis adicionais em auditoria.

## Criterios de aceite

- `schedule_audit` possui coluna `script_name` no schema para novas instalacoes.
- Bancos existentes recebem `script_name` por migracao idempotente.
- Novos eventos `CREATE`, `UPDATE`, `DELETE`, `EXECUTE_START`, `EXECUTE_ERROR` e `EXECUTE_FINISH` gravam `script_name` quando o agendamento possui script.
- `Schedule.listAudit` consegue retornar `script_name` diretamente da tabela de auditoria.
- A futura implementacao do filtro de `/schedules/audit` pode consultar `schedule_audit.script_name` sem depender de parsing de `details`.
- Registros antigos com `script_name` nulo continuam renderizando com fallback visual.

## Validacao esperada

- Rodar:

```powershell
node --check src\database\schema.js
node --check src\models\Schedule.js
```

- Criar, editar e excluir um agendamento em ambiente local e confirmar que as novas linhas em `schedule_audit` recebem `script_name`.
- Executar o worker com um agendamento vencido em ambiente seguro e confirmar que `EXECUTE_START`, `EXECUTE_ERROR` e `EXECUTE_FINISH` recebem `script_name`.
- Abrir `/schedules/audit` e confirmar que registros antigos sem `script_name` nao quebram a tela.
