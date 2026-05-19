# TASK-014 - Coluna e filtro por script na auditoria de agendamentos

## Contexto

A tela de Auditoria de agendamentos (`/schedules/audit`) lista registros da tabela `schedule_audit` com data, acao, ID do agendamento, usuario e detalhes.

A TASK-013 deve criar e preencher a coluna `schedule_audit.script_name` nos novos eventos de auditoria. Com esse campo persistido, a tela pode exibir o script e filtrar os registros por ele sem depender de `JOIN` com `schedules` nem de parsing do JSON textual de `details`.

Para investigar eventos de um script especifico, o usuario deve conseguir usar um filtro direto em `/schedules/audit`.

## Objetivo

Adicionar uma coluna `Script` na tela `/schedules/audit`, exibindo `schedule_audit.script_name` quando disponivel, e permitir filtrar opcionalmente os registros pelo nome do script.

## Escopo

- Exibir uma nova coluna `Script` na tabela de `views/schedule-audit.ejs`.
- Obter `script_name` da coluna `schedule_audit.script_name`.
- Permitir filtro opcional por nome de script na tela `/schedules/audit`.
- Manter a listagem atual funcionando quando nenhum filtro for informado.
- Preservar limite de resultados da auditoria, hoje chamado como `Schedule.listAudit(300)`.
- Manter textos visiveis em portugues.
- Preservar a exibicao de `Detalhes` como conteudo escapado.

## Fora de escopo

- Criar a coluna `schedule_audit.script_name`; isso pertence a TASK-013.
- Alterar worker de agendamentos.
- Recriar ou limpar dados existentes em `database/`.
- Migrar historico antigo para preencher `script_name`.
- Criar paginacao completa na auditoria.
- Criar busca por periodo, usuario, acao ou ID do agendamento.
- Alterar a estrutura visual global do painel.
- Transformar `details` em HTML ou JSON interativo.

## Arquivos provaveis

```text
src/models/Schedule.js
src/controllers/scheduleController.js
views/schedule-audit.ejs
```

Possivelmente tambem:

```text
public/styles.css
```

Somente se houver estilo reutilizavel que faca sentido fora da view. Caso contrario, manter CSS local em `views/schedule-audit.ejs`, seguindo o padrao existente.

## Situacao atual relevante

Rota:

```text
src/routes/scheduleRoutes.js
router.get('/audit', scheduleController.audit);
```

Controller:

```text
src/controllers/scheduleController.js
exports.audit = async (req, res) => {
    const entries = await Schedule.listAudit(300);
    res.render('schedule-audit', { user, entries, messages });
};
```

Model:

```text
src/models/Schedule.js
Schedule.listAudit(limit = 200)
SELECT * FROM schedule_audit ORDER BY datetime(created_at) DESC LIMIT ?
```

View:

```text
views/schedule-audit.ejs
```

Colunas atuais:

```text
Quando
Ação
Agend. #
Usuário
Detalhes
```

## Requisitos funcionais

1. A tabela de `/schedules/audit` deve exibir uma coluna `Script`.
2. A coluna `Script` deve mostrar `entry.script_name` quando a informacao estiver disponivel.
3. Quando o nome do script nao puder ser determinado, a coluna deve exibir fallback visual, por exemplo `—`.
4. A tela deve ter um filtro opcional por nome de script.
5. Quando o filtro estiver vazio, a tela deve exibir a auditoria recente como hoje.
6. Quando o filtro for preenchido, a tela deve exibir apenas registros relacionados ao script informado.
7. O valor selecionado/digitado no filtro deve permanecer visivel apos a busca.
8. Deve existir uma forma simples de limpar o filtro, por exemplo um link/botao para voltar a `/schedules/audit`.
9. A ordenacao deve continuar por `created_at` descendente.
10. O limite de registros deve continuar existindo para evitar listagens grandes demais.

## Requisitos tecnicos

- Preferir implementar o filtro como query string:

```text
/schedules/audit?script_name=Backup-Fortigate.ps1
```

- Atualizar `scheduleController.audit` para ler `req.query.script_name`.
- Passar `script_name` ou um objeto `filters` para a view.
- Atualizar `Schedule.listAudit` para aceitar filtros opcionais sem quebrar chamadas existentes.
- Usar placeholders `?` em todas as queries SQLite.
- Nao concatenar `script_name` diretamente no SQL.
- Usar `schedule_audit.script_name` como fonte primaria do filtro.
- Considerar fallback de `details` somente para exibir registros antigos sem `script_name`, se isso for util e simples.
- Se extrair de `details`, tratar JSON invalido com seguranca e sem derrubar a tela.
- Nao modificar dados locais do banco como parte da implementacao.
- Usar `<%= ... %>` na view para escapar `script_name` e demais valores.
- Manter o formulario de filtro com `method="GET"`.
- Validar ou normalizar o filtro no controller/model de forma simples:
  - `trim()`;
  - limite razoavel de tamanho;
  - valor vazio deve equivaler a sem filtro.
- O filtro pode ser por igualdade exata ou busca parcial, mas a decisao deve ficar clara na implementacao.
- Se usar busca parcial, usar `LIKE ?` com parametro montado fora do SQL, por exemplo `%${scriptName}%`.

## Sugestao de implementacao

1. Alterar `Schedule.listAudit(limit = 200)` para aceitar um segundo parametro opcional:

```js
static async listAudit(limit = 200, filters = {})
```

2. Consultar `schedule_audit` usando alias, por exemplo `schedule_audit a`.
3. Selecionar os campos de auditoria incluindo `a.script_name`.
4. Aplicar filtro por script no SQL usando `a.script_name`.
5. Para registros antigos sem `script_name`, avaliar fallback complementar em memoria somente se necessario.
6. Se extrair fallback de `details`, tratar JSON invalido com seguranca e sem derrubar a tela.
7. Em `scheduleController.audit`, ler `req.query.script_name`, normalizar e chamar:

```js
const entries = await Schedule.listAudit(300, { script_name: scriptNameFilter });
```

8. Renderizar a view com `filters: { script_name: scriptNameFilter }`.
9. Em `views/schedule-audit.ejs`, adicionar um formulario GET acima da tabela:
   - label `Script`;
   - input ou select para `script_name`;
   - botao `Filtrar`;
   - link `Limpar` quando houver filtro ativo.
10. Adicionar a coluna `Script` entre `Agend. #` e `Usuário`, ou entre `Ação` e `Agend. #`, mantendo boa leitura.

## Observacoes de desenho

- Um input de texto e suficiente para a primeira versao.
- Um select com scripts distintos pode ser melhor para usabilidade, mas exigiria buscar a lista de nomes disponiveis. Implementar apenas se ficar simples e localizado.
- A coluna `Detalhes` deve continuar existindo porque ainda contem informacoes complementares de cada evento.
- Evitar aumentar muito a largura da tabela; aplicar `word-break` ou largura maxima ao nome do script se necessario.

## Criterios de aceite

- `/schedules/audit` exibe uma coluna `Script`.
- Registros com `script_name` conhecido mostram o nome do script nessa coluna.
- Registros sem `script_name` conhecido mostram `—`.
- A tela possui filtro opcional por nome de script.
- Acessar `/schedules/audit` sem query string continua funcionando.
- Acessar `/schedules/audit?script_name=<nome>` filtra os registros pelo script informado.
- O filtro usado permanece preenchido na tela.
- O usuario consegue limpar o filtro facilmente.
- A ordenacao por registros mais recentes permanece.
- A coluna `Detalhes` continua escapando conteudo e nao renderiza HTML nao confiavel.
- A implementacao nao altera execucao, criacao, edicao ou exclusao de agendamentos.

## Testes sugeridos

- Abrir `/schedules/audit` autenticado e confirmar a nova coluna `Script`.
- Confirmar que registros recentes de criacao, atualizacao ou execucao exibem o nome do script.
- Filtrar por um script existente e confirmar que a lista mostra apenas registros relacionados a ele.
- Filtrar por um script inexistente e confirmar que a tela exibe estado vazio sem erro.
- Limpar o filtro e confirmar que a listagem volta ao comportamento normal.
- Confirmar que valores em `Detalhes` continuam aparecendo escapados dentro de `<pre>`.
- Confirmar que a tela nao quebra visualmente com nomes de scripts longos.

## Validacao esperada

- Rodar:

```powershell
node --check src\models\Schedule.js
node --check src\controllers\scheduleController.js
```

- Como a mudanca envolve view, validar visualmente `/schedules/audit` com o servidor em execucao quando possivel.
- Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
