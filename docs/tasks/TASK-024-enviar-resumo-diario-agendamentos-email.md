# TASK-024 - Enviar resumo diario de execucao de agendamentos por email

## Contexto

O PS Panel executa scripts PowerShell agendados pelo worker Node `scripts-js/schedule-worker.js`.
Hoje esse worker:

- inicializa `Schedule`;
- chama `Schedule.executeDueJobs(projectRoot)`;
- imprime no console os resultados retornados ou a mensagem `Nenhum agendamento vencido.`.

As execucoes feitas pelo worker ja passam por `src/models/Schedule.js`, que registra historico em `script_history` via `History.addEntry` / `History.updateEntry` usando o usuario `Agendamento (worker)`.

A nova funcionalidade deve enviar um resumo diario dos resultados dos scripts agendados executados no dia anterior. O envio precisa ser feito pelo proprio `schedule-worker.js`, junto das capacidades que ele ja possui, sem criar um novo script PowerShell e sem criar um novo worker separado.

O destinatario do resumo deve ser configurado na tela **Configuracoes** (`/settings`).

## Objetivo

Adicionar ao fluxo do worker de agendamentos uma rotina de resumo diario por email:

1. O worker deve continuar executando scripts agendados normalmente.
2. Em cada execucao do worker, ele deve verificar se existe resumo diario pendente.
3. Quando houver resumo pendente, deve enviar um email com os resultados dos agendamentos executados no dia anterior.
4. O email deve ser enviado para o endereco configurado em `/settings`.
5. Falhas no envio do email nao podem derrubar o worker nem impedir a execucao dos scripts agendados.

## Escopo

- Incorporar a rotina de envio em `scripts-js/schedule-worker.js`.
- Adicionar configuracoes de email em `src/models/Settings.js`.
- Permitir editar essas configuracoes em `views/settings.ejs`.
- Permitir salvar essas configuracoes em `src/controllers/settingsController.js`.
- Usar os registros existentes de `script_history` como fonte preferencial dos resultados do dia.
- Persistir controle de envio para evitar enviar o mesmo resumo mais de uma vez.
- Avaliar a necessidade de criar um service pequeno para envio de email, por exemplo `src/services/emailService.js`, se isso deixar o worker mais legivel.
- Avaliar a necessidade de adicionar uma dependencia SMTP, como `nodemailer`, pois `package.json` atualmente nao possui biblioteca de email.

## Fora de escopo

- Criar novo script `.ps1` para envio de email.
- Criar novo agendamento no Windows Task Scheduler.
- Criar nova tela de historico de emails enviados.
- Enviar email a cada execucao individual de script.
- Reescrever o worker inteiro.
- Alterar a forma atual de execucao de scripts PowerShell.
- Alterar regras de agendamento, lock, retry ou validacao de parametros.
- Implementar esta task automaticamente ao criar o arquivo.

## Arquivos provaveis

```text
scripts-js/schedule-worker.js
src/models/Settings.js
src/controllers/settingsController.js
views/settings.ejs
package.json
package-lock.json
```

Se a implementacao criar um service reutilizavel:

```text
src/services/emailService.js
```

Se a implementacao optar por persistir controle em arquivo:

```text
database/schedule-summary-state.json
```

Preferir nao versionar arquivos de estado gerados automaticamente.

## Configuracoes sugeridas

Adicionar chaves pontuadas no model `Settings`, seguindo o padrao do projeto:

```text
email.smtp_host
email.smtp_port
email.smtp_user
email.smtp_pass
email.smtp_secure
email.from_address
email.daily_summary_recipient
email.daily_summary_enabled
email.daily_summary_last_sent_date
```

Observacoes:

- `email.daily_summary_recipient` e o email que recebera o relatorio.
- `email.daily_summary_enabled` permite ligar/desligar a funcionalidade sem remover dados SMTP.
- `email.daily_summary_last_sent_date` pode ser usado para impedir reenvio duplicado.
- `email.smtp_pass` deve ser tratado como segredo: nao logar, nao imprimir e nao expor em mensagens.
- Se houver receio de sobrescrever senha vazia ao salvar `/settings`, preservar o valor anterior quando o campo vier vazio.

## Fonte dos dados do resumo

Usar preferencialmente `script_history`, filtrando:

- `username = 'Agendamento (worker)'`;
- `start_time` dentro do dia alvo;
- opcionalmente `end_time` para duracao, quando disponivel.

Essa abordagem evita depender de memoria do processo. O worker atual aparenta ser executado periodicamente como comando Node, entao estado em memoria nao deve ser usado como fonte principal do relatorio diario.

Se for necessario adicionar metodo ao model, criar algo pequeno em `src/models/History.js`, por exemplo:

```text
History.findScheduledRunsByDate(date)
```

Esse metodo deve usar placeholders `?` e retornar somente os campos necessarios para montar o email.

## Requisitos funcionais

1. O worker deve executar `Schedule.executeDueJobs(projectRoot)` como hoje.
2. O worker deve verificar o envio do resumo diario sem bloquear permanentemente as execucoes agendadas.
3. O resumo deve considerar o dia anterior em data local do servidor, salvo decisao explicita diferente durante a implementacao.
4. O worker deve enviar no maximo um resumo por data.
5. Se nao houver execucoes no dia anterior, a implementacao deve escolher e documentar uma das opcoes:
   - enviar email informando que nao houve execucoes;
   - nao enviar email e registrar aviso no log.
6. O assunto deve seguir padrao semelhante a:

```text
PS Panel - Resumo de agendamentos - YYYY-MM-DD
```

7. O corpo do email deve incluir:
   - data do relatorio;
   - total de execucoes;
   - script executado;
   - horario de inicio;
   - horario de fim, quando disponivel;
   - status (`success`, `error`, `running` ou equivalente);
   - mensagem de erro, quando existir;
   - trecho resumido da saida.
8. A saida do script deve ser truncada para evitar emails enormes.
9. Configuracoes SMTP incompletas devem fazer o envio ser pulado com log claro e sem exception fatal.
10. Erro de SMTP deve ser capturado e logado, sem `process.exit(1)` por causa do email.
11. O worker deve logar sucesso ou falha do envio de forma objetiva.

## Requisitos de seguranca

- Nao logar `email.smtp_pass`.
- Nao incluir senha SMTP em arquivos de estado.
- Nao imprimir configuracoes sensiveis completas no console.
- Validar formato basico de `email.daily_summary_recipient` antes de enviar.
- Usar biblioteca SMTP com objeto de configuracao; nao montar comando shell com credenciais.
- Manter o uso de CommonJS.
- Manter mensagens de usuario em portugues.
- Nao alterar `.env`.
- Nao alterar arquivos SQLite manualmente.

## Sugestao de implementacao

1. Adicionar defaults em `Settings.initialize()` para as novas chaves `email.*`.
2. Atualizar `settingsController.updateSettings` para aceitar e validar as chaves novas.
3. Atualizar `views/settings.ejs` com uma secao "Email - Resumo diario" contendo:
   - habilitar resumo diario;
   - host SMTP;
   - porta SMTP;
   - usuario SMTP;
   - senha SMTP;
   - conexao segura/TLS;
   - email remetente;
   - email destinatario.
4. Criar helper ou service para envio de email, mantendo o worker pequeno.
5. Criar metodo de consulta no `History` para buscar execucoes do dia anterior feitas por `Agendamento (worker)`.
6. No `schedule-worker.js`, apos executar os agendamentos do ciclo atual, chamar a rotina de resumo diario.
7. A rotina deve:
   - carregar settings;
   - checar se a funcionalidade esta habilitada;
   - determinar a data alvo;
   - verificar se `email.daily_summary_last_sent_date` ja e igual a data alvo;
   - buscar execucoes da data alvo;
   - montar email;
   - enviar email;
   - gravar `email.daily_summary_last_sent_date` somente apos envio bem-sucedido.
8. Se a decisao for enviar tambem relatorio vazio, marcar a data como enviada apos envio bem-sucedido do email vazio.

## Criterios de aceite

- `/settings` permite configurar destinatario e dados SMTP do resumo diario.
- O worker continua executando agendamentos como antes.
- O worker envia um email de resumo diario sem depender de novo script PowerShell.
- O email inclui cada script agendado executado no dia alvo e seu resultado.
- O mesmo resumo nao e enviado mais de uma vez para a mesma data.
- Falhas de SMTP nao derrubam o worker.
- Senha SMTP nao aparece em logs, console, corpo do email ou arquivo de estado.
- Configuracoes incompletas geram aviso e o worker segue normalmente.
- Codigo novo segue CommonJS e padroes do projeto.

## Validacao esperada

- `node --check scripts-js/schedule-worker.js`
- `node --check src/models/Settings.js`
- `node --check src/controllers/settingsController.js`
- `node --check src/models/History.js`, se alterado
- `node --check src/services/emailService.js`, se criado
- Abrir `/settings`, preencher configuracoes de email e salvar.
- Rodar `npm run schedule-worker` com SMTP valido e confirmar envio do resumo.
- Simular data ja enviada e confirmar que o worker nao reenvia o mesmo resumo.
- Simular SMTP invalido e confirmar que o worker loga erro sem encerrar de forma fatal.
- Confirmar que a senha SMTP nao aparece em logs nem em arquivo gerado.

## Observacoes para quem implementar

- Se adicionar `nodemailer`, isso altera `package.json` e `package-lock.json`; fazer apenas se necessario e validar instalacao.
- Como o projeto nao possui testes reais em `npm test`, priorizar `node --check` e validacao manual do fluxo.
- Nao implementar automaticamente esta task apenas por ela existir; aguardar solicitacao explicita do usuario.
