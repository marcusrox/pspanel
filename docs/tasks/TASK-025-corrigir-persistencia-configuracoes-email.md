# TASK-025 - Corrigir persistencia das configuracoes de email

## Contexto

A `TASK-024` adicionou a secao **Email - Resumo diario** na tela de Configuracoes (`/settings`) para configurar o envio de resumo diario dos scripts agendados.

Ao usar a tela para preencher os dados de email e salvar, os campos aparecem vazios ao abrir `/settings` novamente. Isso indica que os valores podem nao estar sendo persistidos ou nao estao sendo carregados corretamente na renderizacao da view.

Revisao inicial do codigo:

- `views/settings.ejs` usa nomes de campos pontuados, como `email.smtp_host`, `email.from_address` e `email.daily_summary_recipient`.
- `src/controllers/settingsController.js` filtra `req.body` esperando essas mesmas chaves planas.
- `app.js` usa `bodyParser.urlencoded({ extended: true })`.
- Dependendo de como o parser entregar o body, os campos pontuados podem chegar como objeto aninhado (`req.body.email.smtp_host`) em vez de chave plana (`req.body['email.smtp_host']`), fazendo o filtro atual descartar os valores.
- A senha SMTP tambem e intencionalmente renderizada vazia, com placeholder `Senha configurada`; isso nao deve ser confundido com falha de persistencia, mas os demais campos devem voltar preenchidos.

## Objetivo

Corrigir o fluxo de salvamento/carregamento das configuracoes de email para que os valores preenchidos em `/settings` sejam persistidos e exibidos corretamente ao abrir a tela novamente.

## Escopo

- Revisar `src/controllers/settingsController.js`.
- Revisar `views/settings.ejs`.
- Revisar `src/models/Settings.js`, se necessario.
- Confirmar como `req.body` chega ao controller para campos com ponto no nome.
- Corrigir o controller para aceitar tanto formato plano quanto formato aninhado, se aplicavel.
- Preservar o comportamento seguro da senha SMTP:
  - nao exibir o valor real no input;
  - manter senha existente quando o campo vier vazio;
  - atualizar senha somente quando o usuario preencher novo valor.

## Fora de escopo

- Alterar o envio de email no `schedule-worker.js`.
- Alterar regras de SMTP ou `nodemailer`.
- Criar criptografia/secret manager para a senha SMTP.
- Alterar `.env`.
- Alterar arquivos SQLite manualmente.
- Implementar a correcao automaticamente ao criar esta task.

## Arquivos provaveis

```text
src/controllers/settingsController.js
views/settings.ejs
src/models/Settings.js
```

## Diagnostico esperado

1. Instrumentar temporariamente ou reproduzir localmente o POST de `/settings/update` para verificar o formato de `req.body`.
2. Confirmar se os campos chegam como:

```js
{
    'email.smtp_host': '...',
    'email.smtp_port': '587'
}
```

ou como:

```js
{
    email: {
        smtp_host: '...',
        smtp_port: '587'
    }
}
```

3. Confirmar se `Settings.set` esta sendo chamado para as chaves `email.*`.
4. Confirmar se `Settings.getAll()` retorna `settings.email.smtp_host`, `settings.email.smtp_port`, etc.
5. Confirmar que a senha SMTP pode estar preservada mesmo quando o campo aparece visualmente vazio.

## Sugestao de correcao

Criar uma normalizacao no controller antes de montar `updates`, por exemplo:

```js
function flattenSettingsBody(body) {
    return {
        ...body,
        'email.smtp_host': body['email.smtp_host'] ?? body.email?.smtp_host,
        'email.smtp_port': body['email.smtp_port'] ?? body.email?.smtp_port,
        'email.smtp_user': body['email.smtp_user'] ?? body.email?.smtp_user,
        'email.smtp_pass': body['email.smtp_pass'] ?? body.email?.smtp_pass,
        'email.smtp_secure': body['email.smtp_secure'] ?? body.email?.smtp_secure,
        'email.from_address': body['email.from_address'] ?? body.email?.from_address,
        'email.daily_summary_recipient': body['email.daily_summary_recipient'] ?? body.email?.daily_summary_recipient,
        'email.daily_summary_enabled': body['email.daily_summary_enabled'] ?? body.email?.daily_summary_enabled
    };
}
```

Depois disso, usar o objeto normalizado no filtro `allowedSettings`.

Alternativa: alterar os `name` dos inputs em `views/settings.ejs` para notacao com colchetes, como `email[smtp_host]`, e ajustar o controller para ler `req.body.email`. Essa alternativa e mais invasiva e deve ser usada apenas se fizer mais sentido apos confirmar o formato real do body.

## Requisitos funcionais

1. Ao preencher host SMTP, porta, usuario, remetente e destinatario, salvar e abrir `/settings` novamente, os campos devem manter os valores.
2. O checkbox de resumo diario deve manter o estado marcado/desmarcado.
3. O checkbox SSL/TLS deve manter o estado marcado/desmarcado.
4. A senha SMTP nao deve ser exibida em texto claro ao reabrir a tela.
5. Se a senha SMTP ja existir e o usuario salvar com o campo de senha vazio, a senha existente deve ser preservada.
6. Se o usuario preencher uma nova senha, a senha armazenada deve ser atualizada.
7. Validacoes atuais de porta e email devem continuar funcionando.
8. Configuracoes de Execucao e Aparencia devem continuar salvando normalmente.

## Requisitos de seguranca

- Nao logar `email.smtp_pass`.
- Nao imprimir `req.body` completo em console se ele puder conter senha.
- Se precisar logar diagnostico temporario, mascarar/remover senha e remover o log antes de concluir.
- Nao ler ou exibir valores reais de `.env`.
- Nao alterar dados SQLite diretamente durante a correcao.

## Criterios de aceite

- O problema de campos vazios apos salvar esta corrigido para todos os campos de email, exceto a senha que deve continuar ocultada.
- A view mostra placeholder indicando senha configurada quando houver senha salva.
- O controller persiste corretamente os campos `email.*`.
- `Settings.getAll()` continua retornando estrutura agrupada compatível com `settings.email.*`.
- Nenhum segredo aparece em logs, console ou resposta da aplicacao.

## Validacao esperada

- `node --check src/controllers/settingsController.js`
- `node --check src/models/Settings.js`, se alterado
- Abrir `/settings`, preencher dados de email e salvar.
- Reabrir `/settings` e confirmar que os campos nao sensiveis permanecem preenchidos.
- Confirmar que a senha aparece apenas como placeholder `Senha configurada`.
- Salvar novamente sem preencher senha e confirmar que o placeholder continua aparecendo.
- Alterar a senha e confirmar que a nova senha e preservada sem ser exibida.
- Confirmar que `scripts.max_execution_time` e `ui.font_scale` continuam persistindo.
