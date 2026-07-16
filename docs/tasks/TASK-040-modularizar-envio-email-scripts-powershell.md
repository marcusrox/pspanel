# TASK-040 - Centralizar configuracao SMTP e modularizar email dos scripts PowerShell

## Contexto

O PS Panel ja possui uma area `Email - Resumo diario` na tela `Configuracoes`. Hoje essa area mistura duas responsabilidades diferentes:

- configuracao geral do servidor SMTP;
- configuracao funcional do resumo diario de agendamentos.

As configuracoes SMTP atualmente sao persistidas pelo model `Settings`, junto das chaves do resumo diario. Ao mesmo tempo, alguns scripts em `scripts-ps/` possuem implementacao propria de envio com `System.Net.Mail.MailMessage` e `System.Net.Mail.SmtpClient`, repetindo host, porta, credenciais e opcoes de TLS.

Foram identificados inicialmente estes consumidores PowerShell:

```text
scripts-ps/Monitoramento-VPN.ps1
scripts-ps/Relatorio-VPN-IPSec-Historico.ps1
scripts-ps/Relatorio-VPN-IPSec-SessoesAtuais.ps1
```

O servidor SMTP passara a exigir autenticacao e transporte criptografado. Devem ser suportados exclusivamente:

- porta `587`: SMTP com STARTTLS obrigatorio;
- porta `465`: SMTP sobre TLS implicito.

O projeto ja usa `nodemailer` em `src/services/emailService.js`. A configuracao SMTP deve se tornar geral, ficar em uma secao propria da tela e ser persistida em um arquivo compartilhado, legivel pelas rotinas JavaScript e pelo modulo PowerShell.

## Objetivo

Separar a configuracao geral de email da configuracao do resumo diario e estabelecer uma unica fonte de configuracao SMTP para todo o PS Panel.

O resultado deve permitir que:

1. a tela `Configuracoes` tenha uma secao exclusiva para o servidor SMTP;
2. a secao `Email - Resumo diario` mantenha apenas habilitacao e destinatario;
3. os dados SMTP sejam persistidos em arquivo JSON compartilhado;
4. os envios JavaScript usem esse arquivo;
5. os scripts PowerShell usem um modulo padronizado de envio baseado na mesma configuracao;
6. os modos STARTTLS na porta 587 e TLS implicito na porta 465 funcionem corretamente.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo

- Criar uma secao `Email - Servidor SMTP` ou `Configuracao SMTP` na tela `/settings`.
- Mover para essa secao host, porta, usuario, senha, remetente e modo de conexao segura.
- Deixar na secao `Email - Resumo diario` somente:
  - ativar ou desativar o resumo diario;
  - destinatario do resumo diario;
  - acao existente de envio/teste manual, se aplicavel.
- Persistir a configuracao SMTP em `database/email-settings.json`.
- Criar services pequenos e reutilizaveis para ler, validar e gravar esse arquivo.
- Fazer o envio do resumo diario usar a nova fonte de configuracao.
- Criar um modulo PowerShell compartilhado para os scripts consumidores.
- Fazer o modulo PowerShell ler diretamente o arquivo compartilhado e enviar diretamente com MailKit/MimeKit, sem iniciar processo Node.
- Incluir no projeto as DLLs .NET necessarias em versoes fixadas, sem depender de instalacao global ou download durante a execucao.
- Migrar os tres scripts PowerShell inicialmente identificados.
- Impedir que o arquivo real de configuracao SMTP seja versionado.
- Atualizar o controle de release ao concluir a implementacao, conforme `AGENTS.md`.

## Fora de escopo

- Criar servidor SMTP proprio.
- Continuar usando porta 25 ou envio anonimo.
- Permitir conexao sem TLS.
- Desabilitar validacao de certificado.
- Aceitar certificados invalidos, expirados ou autoassinados por bypass no codigo.
- Armazenar credenciais SMTP dentro dos scripts `.ps1`.
- Armazenar credenciais em argumentos da linha de comando.
- Alterar a regra que decide quando o resumo diario ou cada script envia email.
- Alterar destinatarios especificos dos relatorios sem requisito funcional adicional.
- Adicionar anexos nesta primeira versao.
- Reescrever os scripts consumidores por inteiro.
- Alterar arquivos SQLite manualmente.
- Migrar ou reaproveitar configuracoes SMTP antigas do SQLite; os dados do novo arquivo serao preenchidos manualmente na tela.
- Atualizar `nodemailer` ou outras dependencias sem necessidade demonstrada.

## Arquivos provaveis

```text
views/settings.ejs
src/controllers/settingsController.js
src/models/Settings.js
src/services/emailConfigService.js
src/services/emailService.js
src/services/dailySummaryEmailService.js
scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1
scripts-ps/modules/PSPanel.Email/lib/MailKit.dll
scripts-ps/modules/PSPanel.Email/lib/MimeKit.dll
scripts-ps/modules/PSPanel.Email/lib/<dependencias-transitivas-necessarias>.dll
scripts-ps/modules/PSPanel.Email/THIRD-PARTY-NOTICES.md
scripts-ps/Monitoramento-VPN.ps1
scripts-ps/Relatorio-VPN-IPSec-Historico.ps1
scripts-ps/Relatorio-VPN-IPSec-SessoesAtuais.ps1
database/email-settings.example.json
.gitignore
src/config/release.js
```

O nome `emailConfigService.js` e sugestivo. A implementacao pode adotar outro nome claro sem misturar leitura de arquivo no controller, no worker ou nos scripts consumidores.

## Separacao da tela Configuracoes

### Secao Configuracao SMTP

Criar uma secao visual independente contendo:

- host SMTP;
- porta SMTP;
- usuario SMTP;
- senha SMTP;
- email remetente;
- modo de seguranca, apresentado de forma coerente com a porta.

Textos recomendados:

```text
587 - STARTTLS obrigatorio
465 - TLS implicito
```

Preferir um `select` de porta ou de modo de transporte que ofereca somente combinacoes validas. Evitar manter um checkbox ambiguo que permita selecionar porta 587 com TLS implicito ou porta 465 sem TLS implicito.

A secao deve explicar que essa configuracao e compartilhada pelo resumo diario e pelos scripts PowerShell que enviam email.

### Secao Email - Resumo diario

Remover dessa secao todos os campos de infraestrutura SMTP. Ela deve conter somente:

- checkbox para ativar ou desativar o resumo diario;
- campo de destinatario do resumo;
- botao de envio manual existente, caso ele ja faca parte do fluxo atual.

O destinatario do resumo deve continuar sendo uma configuracao exclusiva dessa funcionalidade. Ele nao deve ser usado automaticamente pelos scripts PowerShell.

## Arquivo compartilhado de configuracao

Usar como arquivo real:

```text
database/email-settings.json
```

Adicionar esse caminho ao `.gitignore`. Opcionalmente manter um exemplo versionado, sem credenciais reais:

```text
database/email-settings.example.json
```

Schema inicial sugerido:

```json
{
  "version": 1,
  "smtp": {
    "host": "smtp.exemplo.local",
    "port": 587,
    "security": "starttls",
    "username": "usuario-smtp",
    "password": "",
    "fromAddress": "pspanel@exemplo.local"
  }
}
```

Regras do schema:

- `version` deve permitir evolucao futura do formato;
- `port` deve ser numero inteiro, nao texto;
- `security` deve aceitar apenas `starttls` ou `tls`;
- porta 587 deve corresponder a `starttls`;
- porta 465 deve corresponder a `tls`;
- `username` e `password` sao obrigatorios para envio;
- `fromAddress` e o remetente unico padrao do PS Panel;
- destinatarios, assuntos e corpos nao pertencem a esse arquivo;
- chaves desconhecidas devem ser ignoradas com seguranca ou rejeitadas conforme uma politica documentada e consistente.

## Seguranca do arquivo

O arquivo contem senha SMTP e deve ser tratado como segredo operacional.

- A senha sera armazenada como texto no JSON; a protecao em repouso dependera das permissoes configuradas externamente no sistema de arquivos.
- Antes de implementar ou testar, substituir qualquer credencial que tenha sido compartilhada fora do cofre operacional; nao reutilizar credencial exposta em conversa, documentacao ou log.
- Nunca versionar `database/email-settings.json`.
- Nunca incluir seu conteudo em logs, historico, mensagens flash ou resposta HTTP.
- Nunca servir o diretorio `database/` como conteudo estatico.
- Criar o arquivo somente quando a configuracao for salva ou migrada.
- Gravar usando arquivo temporario no mesmo diretorio e substituicao atomica.
- Evitar estado parcialmente escrito em queda do processo.
- Nao aplicar, remover ou alterar ACL, `chmod` ou qualquer permissao do arquivo pelo codigo da aplicacao ou pelo modulo PowerShell.
- Assumir que PS Panel, worker e scripts PowerShell executam com identidades que ja possuem o acesso necessario.
- Tratar a configuracao das permissoes do arquivo como responsabilidade operacional externa a aplicacao.
- Nao usar criptografia reversivel com chave fixa gravada no repositorio.
- Documentar que permissoes e identidades de execucao fazem parte do requisito de instalacao, sem automatiza-las no codigo.
- Nunca devolver a senha persistida para `views/settings.ejs`.
- Campo de senha vazio ao salvar deve preservar a senha atual.
- Disponibilizar uma acao explicita para substituir a senha; limpeza total da senha deve exigir intencao explicita e nao acontecer por campo vazio.

O arquivo JSON e a unica fonte de configuracao SMTP do novo fluxo. Configuracoes SMTP antigas eventualmente existentes no SQLite nao devem ser lidas, copiadas ou removidas por esta task.

## Service compartilhado de configuracao

Criar um service Node responsavel por:

- resolver o caminho absoluto a partir da raiz do projeto;
- carregar e interpretar UTF-8;
- validar schema e combinacoes porta/seguranca;
- devolver objeto normalizado sem alterar o arquivo;
- preservar senha quando a tela salvar o campo vazio;
- gravar de forma atomica;
- criar o diretorio somente quando necessario;
- sanitizar erros;
- nunca registrar o objeto completo.

Interface sugerida:

```text
loadEmailConfig(projectRoot)
saveEmailConfig(projectRoot, input)
validateEmailConfig(input)
getPublicEmailConfig(config)
```

`getPublicEmailConfig` deve remover a senha e expor somente um booleano como `passwordConfigured`, alem dos campos nao secretos necessarios para preencher a tela.

Permanecem no `Settings` somente as configuracoes funcionais do resumo:

```text
email.daily_summary_enabled
email.daily_summary_recipient
email.daily_summary_last_sent_date
email.daily_summary_last_sent_at
```

## Transporte SMTP compartilhado

Os dois runtimes devem consumir diretamente a mesma fonte de configuracao, mas cada um deve possuir seu proprio transporte SMTP:

```text
JavaScript -> emailConfigService -> database/email-settings.json -> Nodemailer
PowerShell -> PSPanel.Email.psm1 -> database/email-settings.json -> MailKit/MimeKit
```

Nao deve existir chamada de Node, processo auxiliar ou ponte de linha de comando no fluxo PowerShell. Da mesma forma, o fluxo JavaScript nao deve iniciar PowerShell para ler configuracao ou enviar email.

Generalizar `src/services/emailService.js` para receber configuracao SMTP independente da configuracao funcional do resumo.

Responsabilidades sugeridas:

```text
emailConfigService -> carrega e valida o JSON
emailService -> cria o transporter e envia a mensagem
dailySummaryEmailService -> decide se/quando/para quem enviar o resumo
```

O resumo diario deve carregar o SMTP pelo novo service e continuar carregando habilitacao, destinatario e ultimo envio pelo `Settings`.

Regras obrigatorias:

1. porta 587: `secure: false` e `requireTLS: true` no Nodemailer;
2. porta 465: `secure: true`;
3. exigir usuario e senha;
4. nao fazer fallback para envio anonimo;
5. manter validacao normal do certificado;
6. nao usar `rejectUnauthorized: false`;
7. preferir TLS 1.2 ou superior quando suportado pelo runtime em uso;
8. aplicar timeout de conexao e envio razoavel;
9. usar sempre `fromAddress` do arquivo, sem permitir remetente arbitrario vindo do script.

As validacoes de schema, porta e seguranca devem produzir o mesmo resultado nos dois runtimes. Manter fixtures JSON compartilhadas para verificar configuracoes validas e invalidas sem duplicar interpretacoes divergentes.

## Modulo PowerShell compartilhado

Criar:

```text
scripts-ps/modules/PSPanel.Email/PSPanel.Email.psm1
```

Exportar uma funcao publica de envio, preferencialmente:

```powershell
Send-PSPanelEmail
```

Parametros minimos:

- `To`: um ou mais destinatarios obrigatorios;
- `Subject`: assunto obrigatorio;
- `Body`: conteudo obrigatorio;
- `BodyAsHtml`: switch para corpo HTML.

Parametros opcionais aceitaveis:

- `Cc`;
- `Bcc`;
- `ReplyTo`.

Requisitos:

- localizar a raiz do projeto a partir de `$PSScriptRoot`;
- localizar a configuracao compartilhada sem depender do diretorio corrente;
- ler `database/email-settings.json` diretamente com `Get-Content -Raw` e `ConvertFrom-Json` em UTF-8;
- validar versao do schema, campos obrigatorios, tipos e combinacao de porta/seguranca sem imprimir a senha;
- carregar MailKit, MimeKit e dependencias por caminhos locais absolutos dentro do proprio modulo;
- falhar com mensagem clara se alguma DLL estiver ausente, corrompida ou com versao incompativel;
- nao depender de modulo global, `PSModulePath`, NuGet, acesso de rede, Node ou `npm` durante a execucao;
- construir a mensagem com MimeKit, incluindo UTF-8, corpo texto ou HTML e destinatarios validados;
- conectar com `MailKit.Security.SecureSocketOptions.StartTls` na porta 587;
- conectar com `MailKit.Security.SecureSocketOptions.SslOnConnect` na porta 465;
- autenticar usando usuario e senha lidos do JSON;
- manter validacao normal da cadeia e do nome do certificado;
- desconectar e descartar cliente e mensagem corretamente em `finally`/`Dispose`;
- nao usar `System.Net.Mail.SmtpClient` nem `Send-MailMessage`, pois nao atendem de forma suportada aos dois modos exigidos;
- permitir que cada consumidor decida se falha de email encerra ou nao o script.

Os scripts consumidores nao devem conhecer host, porta, usuario ou senha. Somente o modulo compartilhado pode ler esses dados e transforma-los em configuracao MailKit.

## Distribuicao local do MailKit

Versionar junto ao modulo PowerShell as DLLs necessarias para o envio direto. A implementacao deve:

- fixar explicitamente as versoes de MailKit, MimeKit e dependencias transitivas;
- obter os binarios de fonte oficial e preservar os arquivos de licenca/avisos exigidos;
- registrar origem, versao e hash SHA-256 de cada DLL em `THIRD-PARTY-NOTICES.md` ou manifest equivalente;
- incluir somente assemblies necessarios e compativeis com PowerShell 7.6.3/.NET 10 em Windows x64;
- carregar os assemblies uma unica vez por processo PowerShell;
- verificar se o tipo esperado ja esta carregado antes de chamar `Add-Type`;
- detectar conflito de versao com mensagem clara, sem tentar baixar ou substituir DLL em runtime;
- documentar o procedimento de atualizacao das DLLs para correcoes de seguranca futuras.

Nao criar `scripts-js/send-email.js`: ele deixaria os scripts PowerShell dependentes do runtime Node, contrariando o requisito desta task.

## Migracao dos scripts consumidores

Para cada script inicialmente identificado:

- importar `modules/PSPanel.Email/PSPanel.Email.psm1` por caminho baseado em `$PSScriptRoot`;
- remover funcao SMTP local duplicada;
- remover host, porta, usuario, senha e flags TLS locais;
- remover qualquer opcao de ignorar certificado;
- substituir apenas o transporte pela chamada `Send-PSPanelEmail`;
- preservar a montagem atual do HTML;
- preservar destinatarios, assunto e momento do envio;
- preservar consultas ao FortiGate, filtros, calculos e regras de alerta;
- preservar o tratamento funcional de falhas, salvo ajuste minimo para o erro padronizado.

Durante a implementacao, preservar cuidadosamente alteracoes locais preexistentes nesses arquivos. Nao reescrever os scripts por inteiro.

## Validacao de mensagens

- Validar cada endereco de `To`, `Cc`, `Bcc` e `ReplyTo`.
- Rejeitar quebras de linha em assunto e enderecos.
- Definir limites razoaveis para numero de destinatarios, tamanho do assunto e tamanho do corpo.
- Nao aceitar `from` vindo do PowerShell; usar o remetente central.
- Nao aceitar opcoes arbitrarias do Nodemailer ou MailKit vindas do consumidor.
- Nao registrar corpo HTML em erros.
- Manter acentos e caracteres especiais em UTF-8.

## Tratamento de erros

- Arquivo ausente deve gerar mensagem clara de configuracao SMTP nao realizada.
- JSON invalido deve impedir envio sem derrubar o restante do worker ou do painel.
- Configuracao incompleta deve informar somente nomes dos campos ausentes.
- Combinacao invalida de porta e seguranca deve falhar antes da conexao.
- Falhas de autenticacao, DNS, timeout, conexao e certificado devem ser sanitizadas.
- O resumo diario deve continuar sem derrubar o worker quando o email falhar.
- O envio manual deve mostrar mensagem amigavel em portugues.
- O modulo PowerShell deve produzir erro capturavel, sem stack trace ou segredo por padrao.
- Erro ao carregar DLL ou ler JSON deve acontecer antes de tentar abrir conexao SMTP.

## Criterios de aceite

- `/settings` possui uma secao exclusiva para configuracao SMTP.
- A secao `Email - Resumo diario` exibe somente habilitacao, destinatario e eventual acao manual.
- Host, porta, usuario, senha, remetente e seguranca sao gravados em `database/email-settings.json`.
- O arquivo real esta ignorado pelo Git e nao e servido pela aplicacao.
- A senha nunca volta preenchida para o navegador.
- Salvar senha vazia preserva a senha existente.
- Gravacao interrompida nao deixa JSON parcial como configuracao ativa.
- Nenhum codigo de migracao SMTP do SQLite para JSON permanece no fluxo normal da aplicacao.
- Configuracoes SMTP antigas do SQLite sao ignoradas e o administrador pode preencher novamente os dados pela tela.
- O resumo diario continua funcionando com habilitacao e destinatario vindos do SQLite e SMTP vindo do JSON.
- O envio manual do resumo continua funcionando.
- Os tres scripts usam `Send-PSPanelEmail` e nao possuem configuracao SMTP propria.
- Nenhum dos tres scripts inicia `node`, `npm` ou helper JavaScript para enviar email.
- O modulo PowerShell le o JSON diretamente e envia diretamente por MailKit.
- As DLLs necessarias estao versionadas no projeto, com versao, origem, licenca e hashes documentados.
- Porta 587 usa autenticacao com STARTTLS obrigatorio.
- Porta 465 usa autenticacao com TLS implicito.
- Porta 25, envio anonimo e combinacoes inseguras sao rejeitados.
- Nenhum bypass de certificado permanece no fluxo migrado.
- Assunto, corpo e credenciais nao aparecem na linha de comando nem nos logs.
- Corpo HTML com acentos chega corretamente.
- O release exibido pela aplicacao e atualizado quando a task for implementada.

## Testes sugeridos

- Abrir `/settings` e confirmar a separacao visual das duas secoes.
- Salvar SMTP com porta 587 e confirmar o JSON normalizado com `security: starttls`.
- Salvar SMTP com porta 465 e confirmar o JSON normalizado com `security: tls`.
- Confirmar que a resposta HTML nao contem a senha persistida.
- Salvar novamente com senha vazia e confirmar preservacao da senha anterior sem imprimi-la.
- Tentar porta 25 e combinacoes inconsistentes e confirmar rejeicao.
- Simular escrita interrompida e confirmar que o arquivo valido anterior permanece ativo.
- Simular JSON malformado e confirmar erro controlado.
- Confirmar que configuracoes SMTP antigas do SQLite nao sao lidas, alteradas nem removidas.
- Enviar resumo diario nas portas 587 e 465 em ambiente homologado.
- Executar envio manual do resumo.
- Enviar por cada um dos tres scripts consumidores.
- Executar os scripts com `node.exe` indisponivel no `PATH` e confirmar que o envio PowerShell continua funcional.
- Executar em maquina limpa, sem MailKit instalado globalmente, e confirmar carregamento apenas pelas DLLs locais.
- Remover ou corromper uma DLL em ambiente de teste e confirmar falha clara antes da conexao.
- Conferir os hashes das DLLs versionadas contra o manifest registrado.
- Testar HTML com acentos, multiplos destinatarios e assunto valido.
- Usar senha incorreta e certificado invalido em ambiente controlado, confirmando falha sanitizada.
- Inspecionar argumentos dos processos e logs, confirmando ausencia de credenciais e corpo.
- Confirmar que nenhum arquivo temporario com senha permanece apos sucesso ou falha.
- Confirmar operacionalmente que as identidades do PS Panel, worker e scripts possuem acesso ao arquivo, sem esperar alteracao automatica de permissoes.

## Validacao esperada

Validar todos os JavaScript alterados:

```powershell
node --check src\services\emailConfigService.js
node --check src\services\emailService.js
node --check src\services\dailySummaryEmailService.js
node --check src\controllers\settingsController.js
node --check src\models\Settings.js
node --check src\config\release.js
```

Validar a view:

```powershell
node -e "const fs=require('fs'); const ejs=require('ejs'); ejs.compile(fs.readFileSync('views/settings.ejs','utf8'), {filename:'views/settings.ejs'}); console.log('EJS OK');"
```

Validar o modulo sem executar envio externo:

```powershell
pwsh.exe -NoProfile -Command "Import-Module .\scripts-ps\modules\PSPanel.Email\PSPanel.Email.psm1 -Force; Get-Command Send-PSPanelEmail -ErrorAction Stop | Out-Null; [MailKit.Net.Smtp.SmtpClient].Assembly.FullName; [MimeKit.MimeMessage].Assembly.FullName"
```

Realizar testes controlados contra SMTP homologado nas portas 587 e 465, separadamente pelos fluxos JavaScript e PowerShell. Nao executar `npm test`, pois o projeto ainda nao possui testes reais configurados. Nunca usar credenciais reais em documentacao, fixtures, saidas de teste ou resposta final.

---

## Assinatura da LLM

- Data: 2026-07-16 09:53:41 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 2026-07-16 10:47:36 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-16 11:01:24 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-16 11:37:38 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

---

## Assinatura da LLM

- Data: 2026-07-16 11:47:02 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
