# TASK-018 - Unificar parametros de scripts entre painel e agendamentos

## Contexto

A tela principal do Painel de Scripts ja extrai metadados do bloco `param(...)` dos arquivos `.ps1`, renderiza campos individuais para parametros e bloqueia a execucao quando faltam parametros obrigatorios. Esse comportamento foi implementado no fluxo manual de `src/routes/mainRoutes.js`.

A tela de Agendamentos (`/schedules`) ainda usa um campo livre `parameters` em `views/schedule-form.ejs` e o controller apenas salva o texto informado. Na execucao agendada, `src/models/Schedule.js` separa esses parametros por espacos simples antes de chamar o PowerShell.

Com isso, e possivel criar ou alterar um agendamento para um script com parametros obrigatorios sem informar valores. Quando o worker executa o job, o PowerShell pode ficar parado aguardando digitacao na CLI. Um exemplo para validar o problema e o script `scripts-ps/ProvaConceito.ps1`.

## Objetivo

Fazer a tela de Agendamentos tratar parametros de script da mesma forma segura que a tela principal do Painel de Scripts, impedindo salvar agendamentos ativos ou futuros sem os parametros obrigatorios conhecidos e evitando execucoes PowerShell interativas por falta de parametro.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Reaproveitar ou extrair para codigo compartilhado o parser de parametros hoje existente em `src/routes/mainRoutes.js`.
- Reaproveitar ou extrair para codigo compartilhado as funcoes de:
  - leitura do bloco `param(...)`;
  - identificacao de parametros obrigatorios;
  - `ValidateSet`, quando ja suportado pelo painel principal;
  - parsing de parametros nomeados informados em texto livre;
  - montagem de argumentos PowerShell;
  - formatacao/resumo dos parametros.
- Ajustar a tela `/schedules/new` para exibir campos de parametros quando o script selecionado possuir parametros declarados.
- Ajustar a tela `/schedules/:id/edit` para preservar e exibir parametros ja salvos.
- Bloquear no frontend o salvamento quando faltarem parametros obrigatorios do script selecionado.
- Bloquear no backend `create` e `update` de agendamentos quando faltarem parametros obrigatorios.
- Garantir que o worker execute com os mesmos argumentos normalizados pelo fluxo de criacao/edicao.
- Manter compatibilidade com scripts sem parametros e com agendamentos antigos sempre que possivel.

## Fora de escopo

- Criar parser completo da linguagem PowerShell.
- Alterar a assinatura de scripts `.ps1`.
- Modificar arquivos em `scripts-ps/` como efeito colateral desta melhoria.
- Alterar schema SQLite salvo se a implementacao justificar claramente uma migracao compativel.
- Executar automaticamente a implementacao desta task apos criar o arquivo.
- Alterar regras de autenticacao, sessao ou permissao das rotas.
- Criar prompt interativo no navegador durante a execucao agendada.

## Arquivos provaveis

```text
src/routes/mainRoutes.js
src/controllers/scheduleController.js
src/models/Schedule.js
views/schedule-form.ejs
```

Se for criado codigo compartilhado, usar preferencialmente um service em:

```text
src/services/powerShellParameters.js
```

ou outro nome equivalente alinhado ao padrao do projeto.

## Requisitos funcionais

1. Ao abrir `/schedules/new`, a tela deve carregar a lista de scripts com metadados basicos de parametros.
2. Ao selecionar um script com parametros declarados, a tela deve exibir campos individuais para preenchimento, seguindo a experiencia do Painel de Scripts.
3. Parametros obrigatorios devem aparecer marcados visualmente e usar validacao no navegador.
4. `ValidateSet` deve continuar gerando campo de selecao quando ja houver suporte equivalente no painel principal.
5. Ao criar um agendamento para script com parametros obrigatorios vazios, o sistema deve bloquear o salvamento e exibir mensagem amigavel, por exemplo:

```text
Informe os parametros obrigatorios: Nome, Ambiente.
```

6. A mesma validacao deve ocorrer em `POST /schedules` e `POST /schedules/:id`, mesmo que a requisicao seja feita manualmente.
7. A edicao de um agendamento existente deve preencher os campos estruturados a partir dos parametros salvos.
8. Agendamentos de scripts sem parametros obrigatorios devem continuar podendo ser criados sem parametros.
9. O worker nao deve iniciar PowerShell para um job cujo script possua parametros obrigatorios ausentes.
10. Em caso de agendamento antigo invalido, o worker deve registrar falha controlada e reagendar/desativar conforme o padrao atual, sem ficar preso aguardando input.

## Requisitos tecnicos

- Evitar duplicar o parser de parametros entre `mainRoutes.js` e `scheduleController.js`.
- Manter CommonJS (`require`, `module.exports`).
- Manter mensagens ao usuario em portugues.
- Validar nome de script com as mesmas protecoes exigidas pelo projeto:
  - termina com `.ps1`;
  - nao contem `..`;
  - nao contem `/` nem `\`;
  - existe dentro de `scripts-ps/`.
- Usar `spawn` com array de argumentos; nao montar comando concatenado com entrada do usuario.
- Preservar separacao entre `stdout` e `stderr` no worker.
- Evitar registrar senhas, tokens ou parametros potencialmente sensiveis em novos logs.
- Se parametros continuarem persistidos no campo textual `schedules.parameters`, salvar uma forma normalizada compatível com o worker, por exemplo `-Nome valor -Ambiente PROD`.
- Se for necessario salvar formato estruturado, justificar e implementar migracao compativel/idempotente.

## Sugestao de implementacao

1. Criar `src/services/powerShellParameters.js` contendo as funcoes hoje locais em `mainRoutes.js`:
   - `parseScriptParametersFromContent`;
   - `parseRawNamedParameters`;
   - `getMissingRequiredParameters`;
   - `buildPowerShellArgs`;
   - `formatProvidedParams`;
   - helpers internos como `findParamBlock`, `splitTopLevelParameterDeclarations`, `parseValidateSetOptions`.
2. Ajustar `src/routes/mainRoutes.js` para importar esse service, mantendo o comportamento atual do Painel de Scripts.
3. Ajustar `scheduleController.js` para:
   - listar scripts com metadados de parametros ao renderizar `schedule-form.ejs`;
   - aceitar `paramValues` alem de `parameters`;
   - validar obrigatorios antes de chamar `Schedule.create` ou `Schedule.update`;
   - salvar `parameters` normalizado por `formatProvidedParams`.
4. Ajustar `views/schedule-form.ejs` para:
   - armazenar os metadados dos scripts em atributos `data-*` ou JSON seguro;
   - renderizar campos individuais quando o script muda;
   - preencher campos na edicao usando os parametros salvos;
   - manter o campo livre apenas como complementar/avancado, se necessario para compatibilidade.
5. Ajustar `Schedule.executeDueJobs` para usar o parser compartilhado ao montar `argList` a partir de `row.parameters`, evitando apenas `split(/\s+/)` quando houver aspas ou parametros conhecidos.
6. Incluir uma barreira adicional no worker: reler metadados do script antes de executar e registrar erro controlado se obrigatorios estiverem ausentes.

## Criterios de aceite

- `/schedules/new` exibe campos de parametros ao selecionar `ProvaConceito.ps1` ou outro script com bloco `param(...)`.
- Nao e possivel salvar novo agendamento com parametro obrigatorio vazio.
- Nao e possivel atualizar agendamento deixando parametro obrigatorio vazio.
- O backend bloqueia `POST /schedules` e `POST /schedules/:id` sem parametros obrigatorios, independentemente do frontend.
- O Painel de Scripts continua funcionando como antes apos extrair o codigo compartilhado.
- O worker nao fica aguardando input interativo do PowerShell por falta de parametros obrigatorios conhecidos.
- Agendamentos existentes sem parametros obrigatorios continuam executando.
- Agendamentos antigos para scripts com parametros obrigatorios ausentes falham de forma controlada, com historico/auditoria, sem travar a fila.

## Testes sugeridos

- Abrir `/schedules/new`, selecionar `ProvaConceito.ps1` e tentar salvar sem preencher o parametro obrigatorio.
- Confirmar que a mensagem informa o nome do parametro ausente.
- Preencher o parametro obrigatorio e confirmar que o agendamento e salvo.
- Editar o agendamento criado e confirmar que o valor do parametro aparece preenchido.
- Remover o valor obrigatorio na edicao e confirmar que o salvamento e bloqueado.
- Enviar requisicao manual para `POST /schedules` sem parametros obrigatorios e confirmar bloqueio no backend.
- Rodar `node --check` nos arquivos JavaScript alterados.
- Quando seguro, executar o worker para um agendamento valido e confirmar que o PowerShell recebe os argumentos corretos.
- Confirmar que um script sem parametros obrigatorios ainda pode ser agendado sem preenchimento adicional.

## Validacao esperada

- `node --check src\routes\mainRoutes.js`
- `node --check src\controllers\scheduleController.js`
- `node --check src\models\Schedule.js`
- `node --check src\services\powerShellParameters.js`, se criado
- `node --check scripts-js\schedule-worker.js`, se o worker for alterado
- Validacao visual de `/schedules/new` e `/schedules/:id/edit` com usuario autenticado.

Se a validacao visual exigir login, usar os dados do `.env` apenas localmente e nunca imprimir seu conteudo em logs ou respostas.
