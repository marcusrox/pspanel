# TASK-026 - Exibir ultimo envio e permitir envio manual do resumo diario

## Contexto

A tela **Configuracoes** (`/settings`) possui o quadro **Email - Resumo diario**, criado para configurar o envio de resumo diario dos scripts agendados.

Hoje a configuracao contempla dados SMTP, remetente, destinatario e habilitacao do resumo diario. O worker `scripts-js/schedule-worker.js` envia o resumo automaticamente e grava a chave `email.daily_summary_last_sent_date` quando o envio automatico e concluido com sucesso.

Falta, no final desse quadro, uma forma operacional de:

- visualizar quando foi o ultimo envio do resumo diario;
- forcar o envio do resumo no momento, pela propria tela de Configuracoes.

Essa acao manual deve reutilizar a logica de montagem/envio do resumo diario, sem criar script PowerShell e sem depender de executar manualmente o `schedule-worker.js`.

## Objetivo

Adicionar ao final do quadro **Email - Resumo diario**:

1. uma exibicao clara do ultimo envio registrado;
2. um botao para forcar o envio do resumo imediatamente;
3. feedback visual por flash message informando sucesso, falha ou configuracao incompleta.

## Escopo

- Atualizar `views/settings.ejs` para exibir status do ultimo envio e botao de envio manual.
- Atualizar `src/routes/settingsRoutes.js` com rota POST para envio manual.
- Atualizar `src/controllers/settingsController.js` com acao para forcar envio.
- Reaproveitar/refatorar logica de resumo hoje em `scripts-js/schedule-worker.js`, se necessario, para evitar duplicacao.
- Se fizer sentido, criar service compartilhado, por exemplo:

```text
src/services/dailySummaryEmailService.js
```

- Preservar o envio automatico do worker.
- Preservar a seguranca da senha SMTP.

## Fora de escopo

- Criar historico completo de todos os emails enviados.
- Criar tela separada para monitoramento de emails.
- Criar novo script PowerShell.
- Alterar o agendamento do Windows Task Scheduler.
- Enviar email individual por execucao.
- Expor dados sensiveis de SMTP.
- Implementar esta task automaticamente ao criar o arquivo.

## Arquivos provaveis

```text
views/settings.ejs
src/routes/settingsRoutes.js
src/controllers/settingsController.js
scripts-js/schedule-worker.js
src/services/emailService.js
src/models/Settings.js
```

Se a logica for extraida do worker:

```text
src/services/dailySummaryEmailService.js
```

## Requisitos funcionais

1. No final do quadro **Email - Resumo diario**, exibir o ultimo envio conhecido.
2. Se nunca houve envio, exibir fallback amigavel, por exemplo `Nunca enviado`.
3. O status deve mostrar a data salva em `email.daily_summary_last_sent_date`.
4. Se for adicionada uma nova chave com timestamp completo, como `email.daily_summary_last_sent_at`, exibir data/hora formatada em `pt-BR`.
5. Adicionar botao `Enviar resumo agora` ou texto equivalente em portugues.
6. O botao deve usar `POST`, com confirmacao simples no submit se fizer sentido.
7. A acao manual deve enviar o resumo imediatamente, mesmo que `email.daily_summary_last_sent_date` ja seja igual a data alvo.
8. A acao manual deve respeitar configuracoes SMTP e destinatario.
9. Se as configuracoes estiverem incompletas, nao tentar SMTP e mostrar mensagem de erro amigavel.
10. Se o envio falhar por SMTP/autenticacao/rede, mostrar mensagem de erro amigavel.
11. Se o envio for bem-sucedido, mostrar flash success.
12. Apos envio manual bem-sucedido, atualizar o registro de ultimo envio.
13. O envio manual nao deve executar scripts agendados; deve apenas montar e enviar o resumo.

## Data alvo do envio manual

Definir explicitamente o comportamento na implementacao.

Sugestao:

- Envio automatico: continua enviando o resumo do dia anterior.
- Envio manual: envia o mesmo tipo de resumo do dia anterior por padrao.

Se houver necessidade futura, pode-se evoluir para escolher a data do relatorio, mas isso fica fora do escopo desta task.

## Requisitos de arquitetura

- Evitar duplicar no controller a montagem de relatorio que ja existe no worker.
- Preferir extrair funcoes do worker para um service compartilhado:
  - calcular data alvo;
  - buscar execucoes em `History`;
  - montar assunto/corpo;
  - validar configuracao de email;
  - enviar email;
  - atualizar settings apos sucesso.
- O worker deve continuar pequeno e chamando esse service.
- O controller deve chamar o mesmo service em modo manual.
- O modo manual deve conseguir ignorar a trava de "ja enviado" usada pelo automatico.

## Sugestao de implementacao

1. Criar service `src/services/dailySummaryEmailService.js` com funcoes como:

```text
sendPendingDailySummary()
sendDailySummaryNow()
getDailySummaryStatus()
```

2. Mover para esse service a logica hoje localizada em `scripts-js/schedule-worker.js`:
   - `getYesterdayLocalDateString`;
   - formatacao de datas;
   - calculo de duracao;
   - resumo/truncamento de output;
   - escape HTML;
   - montagem da mensagem;
   - validacao de configuracao;
   - envio e atualizacao de settings.
3. Ajustar `schedule-worker.js` para chamar `sendPendingDailySummary()` apos `Schedule.executeDueJobs(projectRoot)`.
4. Em `settingsController.showSettings`, preparar um objeto de status para a view, ou usar `settings.email.daily_summary_last_sent_date` diretamente.
5. Criar `SettingsController.sendDailySummaryNow`.
6. Adicionar rota:

```js
router.post('/daily-summary/send-now', SettingsController.sendDailySummaryNow);
```

7. Em `views/settings.ejs`, adicionar no final do quadro:
   - texto de ultimo envio;
   - botao de envio manual em formulario POST separado ou botao com `formaction`, evitando misturar com o submit de salvar configuracoes.
8. Usar flash messages ja existentes (`success` / `error`) para resultado.

## Requisitos de seguranca

- Nao logar `email.smtp_pass`.
- Nao renderizar senha SMTP.
- Nao imprimir configuracoes SMTP completas em console.
- Nao permitir envio manual sem usuario autenticado; a rota sob `/settings` ja deve estar protegida por `isAuthenticated` em `app.js`.
- Nao executar PowerShell durante o envio manual.
- Nao aceitar data arbitraria via request nesta task, para evitar superficie desnecessaria.

## Criterios de aceite

- O quadro **Email - Resumo diario** mostra o ultimo envio ou `Nunca enviado`.
- O botao de envio manual aparece no final do quadro.
- Clicar no botao dispara POST autenticado e tenta enviar o resumo imediatamente.
- Envio manual bem-sucedido atualiza o status exibido.
- Envio manual nao dispara execucao de scripts agendados.
- Falhas de configuracao ou SMTP aparecem como flash error.
- O envio automatico pelo worker continua funcionando.
- Nao ha duplicacao grande entre worker e controller.
- Senha SMTP nao aparece em tela, logs ou mensagens.

## Validacao esperada

- `node --check scripts-js/schedule-worker.js`
- `node --check src/controllers/settingsController.js`
- `node --check src/routes/settingsRoutes.js`
- `node --check src/services/emailService.js`
- `node --check src/services/dailySummaryEmailService.js`, se criado
- Abrir `/settings` e confirmar exibicao do ultimo envio.
- Com configuracao incompleta, clicar em `Enviar resumo agora` e confirmar flash error.
- Com SMTP valido, clicar em `Enviar resumo agora` e confirmar recebimento do email.
- Reabrir `/settings` e confirmar que o ultimo envio foi atualizado.
- Confirmar que o worker ainda passa em sintaxe e continua chamando o envio automatico.

## Observacoes para quem implementar

- Se usar apenas `email.daily_summary_last_sent_date`, o status tera granularidade de data. Para mostrar "quando" com data/hora, adicionar `email.daily_summary_last_sent_at` em `Settings.initialize()` e atualizar no envio automatico e manual.
- Se adicionar `email.daily_summary_last_sent_at`, manter compatibilidade com `email.daily_summary_last_sent_date`, pois ela e usada para evitar reenvio automatico duplicado.
- Ao concluir a implementacao, informar ao usuario que e necessario fazer `git commit`.
