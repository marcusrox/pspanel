# TASK-027 - Corrigir feedback da tela de Configuracoes

## Contexto

Na tela **Configuracoes** (`/settings`), ao clicar em **Salvar Alteracoes**, o usuario nao recebe feedback visivel da operacao: nem confirmacao de sucesso nem mensagem de erro.

Tambem foi observado que falhas do envio manual do resumo diario aparecem apenas no console, por exemplo:

```text
Erro ao enviar resumo diário manual: 50050100:error:0A00010B:SSL routines:tls_validate_record_header:wrong version number:openssl\ssl\record\methods\tlsany_meth.c:78:
```

Esse erro deveria aparecer para o usuario como flash message amigavel na propria tela.

Revisao inicial do fluxo:

- `app.js` tem middleware global que popula `res.locals.messages` consumindo `req.flash('error')`, `req.flash('success')` e `req.flash('info')`.
- `settingsController.showSettings` chama novamente `req.flash('success')` e `req.flash('error')` e passa `success` / `error` para a view.
- Como as mensagens ja foram consumidas pelo middleware global, essas variaveis chegam vazias.
- `views/settings.ejs` atualmente renderiza `success` e `error`, nao `messages`.

Isso torna plausivel que as operacoes estejam gravando flash corretamente, mas a view nao esteja exibindo porque le a fonte errada.

## Objetivo

Corrigir a exibicao de feedback na tela de Configuracoes para que:

1. salvar configuracoes mostre sucesso ou erro;
2. envio manual do resumo diario mostre sucesso ou erro;
3. erros SMTP, incluindo erro de TLS/porta, aparecam como mensagem amigavel na tela;
4. o padrao fique alinhado ao middleware global de flash messages do projeto.

## Escopo

- Ajustar `views/settings.ejs` para usar `messages` vindo de `res.locals.messages`.
- Ajustar `settingsController.showSettings`, se necessario, para passar `messages: res.locals.messages` ou parar de chamar `req.flash()` novamente.
- Conferir `settingsController.updateSettings` e `settingsController.sendDailySummaryNow` para garantir que gravam `req.flash('success'/'error', ...)` antes do redirect.
- Garantir que erros do envio manual sejam exibidos ao usuario.
- Manter mensagens em portugues.

## Fora de escopo

- Alterar configuracoes SMTP.
- Alterar o envio automatico do worker.
- Alterar a estrutura global de flash do `app.js`, salvo se absolutamente necessario.
- Implementar toast/notificacao frontend nova.
- Alterar dados SQLite manualmente.
- Implementar esta task automaticamente ao criar o arquivo.

## Arquivos provaveis

```text
views/settings.ejs
src/controllers/settingsController.js
```

Se for identificado que o problema e global:

```text
app.js
```

Mas a preferencia e corrigir localmente a tela de Configuracoes para seguir o padrao ja documentado em `docs/patterns.md`.

## Diagnostico esperado

1. Confirmar que `app.js` consome flash messages em `res.locals.messages`.
2. Confirmar que `settingsController.showSettings` esta tentando ler `req.flash()` depois do middleware global.
3. Confirmar que `views/settings.ejs` renderiza `success` / `error` em vez de `messages.success` / `messages.error`.
4. Confirmar que os controllers gravam flash antes de `res.redirect('/settings')`.

## Sugestao de correcao

Atualizar `settingsController.showSettings` para alinhar com o padrao:

```js
res.render('settings', {
    settings,
    dailySummaryStatus: getDailySummaryStatus(settings),
    user: req.session.user,
    messages: res.locals.messages
});
```

E atualizar `views/settings.ejs`:

```ejs
<% if (messages.success && messages.success.length) { %>
    <div class="alert alert-success"><%= messages.success[0] %></div>
<% } %>

<% if (messages.error && messages.error.length) { %>
    <div class="alert alert-danger"><%= messages.error[0] %></div>
<% } %>
```

Opcionalmente, para compatibilidade defensiva, usar fallback:

```ejs
<% const pageMessages = typeof messages !== 'undefined' ? messages : { success: success || [], error: error || [] }; %>
```

Mas a preferencia e padronizar em `messages`.

## Requisitos funcionais

1. Ao salvar configuracoes com sucesso, a tela deve exibir `Configurações atualizadas com sucesso`.
2. Ao salvar configuracoes invalidas, a tela deve exibir a mensagem de erro correspondente.
3. Ao clicar em **Enviar resumo agora** com configuracao incompleta, a tela deve exibir flash error.
4. Ao clicar em **Enviar resumo agora** e ocorrer erro TLS, a tela deve exibir mensagem amigavel sobre SSL/TLS direto e porta 587/465.
5. Ao enviar resumo manual com sucesso, a tela deve exibir flash success.
6. As mensagens devem aparecer apos o redirect para `/settings`.
7. A correcao nao deve quebrar a exibicao de configuracoes existentes.

## Requisitos de seguranca

- Nao exibir senha SMTP.
- Nao imprimir `req.body` completo em log.
- Nao exibir stack trace ou erro OpenSSL bruto para o usuario.
- Continuar logando erro tecnico no console quando util, mas mostrar mensagem amigavel na tela.

## Criterios de aceite

- A tela `/settings` exibe mensagens de sucesso e erro.
- Mensagens gravadas por `settingsController.updateSettings` aparecem corretamente.
- Mensagens gravadas por `settingsController.sendDailySummaryNow` aparecem corretamente.
- O erro OpenSSL/TLS bruto nao e a unica forma de diagnostico; o usuario recebe uma mensagem compreensivel na UI.
- O padrao fica consistente com `res.locals.messages`.

## Validacao esperada

- `node --check src/controllers/settingsController.js`
- Abrir `/settings`, alterar uma configuracao simples e salvar; confirmar alerta de sucesso.
- Forcar erro de validacao, por exemplo porta SMTP invalida, e confirmar alerta de erro.
- Configurar porta `587` com SSL/TLS direto marcado e confirmar que a mensagem amigavel aparece.
- Acionar **Enviar resumo agora** com configuracao SMTP invalida e confirmar alerta de erro na tela.
- Confirmar que senha SMTP nao aparece em tela nem em logs.

## Observacoes para quem implementar

- Esta task deve ser uma correcao pequena e localizada.
- Evitar refatorar o middleware global de flash se a tela puder simplesmente usar `messages`.
- Ao concluir a implementacao, informar ao usuario que e necessario fazer `git commit`.
