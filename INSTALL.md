# Instalação do PS Panel em produção

Este guia descreve a instalação homologada do PS Panel em uma VM Windows Server 2022.

Arquitetura adotada:

- Windows Server 2022 em VM;
- PowerShell 7.6.3;
- Node.js 24.18.0 LTS x64;
- Git for Windows;
- código instalado em `C:\Apps\PSPanel` por clone público do GitHub;
- aplicação web executada como serviço Windows pelo WinSW;
- conta de serviço de domínio criada especificamente para o PS Panel;
- worker executado pelo Agendador de Tarefas a cada cinco minutos;
- acesso inicial por HTTP na porta 3000;
- SQLite e configurações operacionais armazenados localmente na VM.

> Não grave usuários, senhas, tokens, chaves privadas ou o conteúdo do `.env` neste documento, no Git ou nos arquivos XML do WinSW.

## 1. Pré-requisitos

Antes da instalação, providencie:

- VM Windows Server 2022 atualizada;
- PowerShell 7.6.3 instalado em `C:\Program Files\PowerShell\7`;
- resolução DNS e sincronização de horário funcionando;
- uma conta de serviço, por exemplo `DOMINIO\svc_pspanel`;
- acesso da VM ao Active Directory/LDAP, SMTP, Fortigate e demais destinos usados pelos scripts;
- autorização de entrada na porta 3000 somente para as redes internas necessárias;
- permissão para clonar o repositório público no GitHub.

Configure o fuso horário de Brasília quando aplicável:

```powershell
Set-TimeZone -Id 'E. South America Standard Time'
w32tm.exe /resync
```

### Conta de serviço

Foi adotada uma conta de serviço convencional, e não uma gMSA. A conta deve:

- não ser administradora local nem administradora de domínio;
- não permitir logon interativo, salvo durante uma homologação controlada;
- possuir o direito **Logon como serviço**;
- possuir o direito **Logon como trabalho em lotes**;
- ter somente os acessos de rede necessários às automações;
- ter leitura e execução no código do PS Panel;
- ter modificação em `database`, `log` e nos diretórios de saída dos scripts.

A senha será informada interativamente ao configurar o serviço e ao instalar a tarefa agendada. Não coloque a senha no repositório ou no XML do WinSW.

## 2. Instalar o Node.js homologado

A versão homologada é o Node.js `24.18.0` LTS x64.

Baixe o MSI oficial:

```text
https://nodejs.org/dist/v24.18.0/node-v24.18.0-x64.msi
```

Instale em PowerShell administrativo:

```powershell
msiexec.exe /i C:\Temp\node-v24.18.0-x64.msi /qn /norestart
```

Abra uma nova sessão do PowerShell e valide:

```powershell
node --version
npm --version
where.exe node
```

O resultado do Node deve ser exatamente:

```text
v24.18.0
```

O executável deve estar em:

```text
C:\Program Files\nodejs\node.exe
```

Não atualize automaticamente a versão principal do Node no servidor. Uma nova versão deve ser homologada antes da atualização.

## 3. Instalar o Git for Windows

Baixe e instale o Git for Windows pelo site oficial:

```text
https://git-scm.com/download/win
```

Habilite o uso do Git pela linha de comando e valide em uma nova sessão:

```powershell
git --version
where.exe git
```

O repositório é público; não é necessário configurar chave SSH, PAT ou credencial do GitHub para cloná-lo.

## 4. Clonar o repositório

Crie somente a pasta pai:

```powershell
New-Item -ItemType Directory -Path C:\Apps -Force
```

Clone pela URL pública HTTPS:

```powershell
git clone https://github.com/marcusrox/pspanel.git C:\Apps\PSPanel
```

Valide o clone e registre o commit implantado:

```powershell
Set-Location C:\Apps\PSPanel
git status
git branch --show-current
git rev-parse HEAD
```

O hash retornado por `git rev-parse HEAD` deve ser guardado no controle de mudança ou registro de implantação.

## 5. Instalar as dependências da aplicação

Use `npm ci` para instalar exatamente as versões registradas no `package-lock.json`:

```powershell
Set-Location C:\Apps\PSPanel
npm ci --omit=dev
```

Não copie `node_modules` de outra máquina e não use `npm update` no servidor.

Valide a sintaxe dos pontos de entrada:

```powershell
node --check app.js
node --check scripts-js\schedule-worker.js
```

## 6. Instalar o Posh-SSH

Alguns scripts, como o backup do Fortigate, dependem do Posh-SSH 4.x. Instale o módulo para todos os usuários para que ele também fique disponível à conta do serviço:

```powershell
pwsh.exe -NoProfile -Command "Install-Module -Name Posh-SSH -AllowPrerelease -Force -AllowClobber -Scope AllUsers"
```

Valide:

```powershell
pwsh.exe -NoProfile -Command "Get-Module -ListAvailable Posh-SSH | Sort-Object Version -Descending | Select-Object -First 1 Name,Version,Path"
```

A versão encontrada deve ser `4.0.0` ou superior.

## 7. Criar diretórios operacionais

```powershell
New-Item -ItemType Directory -Path C:\Apps\PSPanel\database -Force
New-Item -ItemType Directory -Path C:\Apps\PSPanel\log -Force
New-Item -ItemType Directory -Path C:\Apps\PSPanel\service -Force
New-Item -ItemType Directory -Path C:\FortiGate-Backup -Force
```

A conta de serviço precisa de:

- leitura e execução em `C:\Apps\PSPanel`;
- modificação em `C:\Apps\PSPanel\database`;
- modificação em `C:\Apps\PSPanel\log`;
- modificação em `C:\FortiGate-Backup`;
- acesso aos demais diretórios utilizados pelos scripts PowerShell.

Confira as permissões:

```powershell
icacls.exe C:\Apps\PSPanel
icacls.exe C:\Apps\PSPanel\database
icacls.exe C:\Apps\PSPanel\log
icacls.exe C:\FortiGate-Backup
```

Não conceda acesso de modificação para `Everyone` ou `Users`.

## 8. Configurar o ambiente

Crie o arquivo local a partir do exemplo:

```powershell
Copy-Item C:\Apps\PSPanel\.env.example C:\Apps\PSPanel\.env
notepad.exe C:\Apps\PSPanel\.env
```

Configuração mínima para o acesso inicial por HTTP:

```dotenv
PORT=3000
NODE_ENV=production
SESSION_SECRET=SUBSTITUIR_POR_SEGREDO_ALEATORIO
SESSION_COOKIE_SECURE=false

ADMIN_USER=SUBSTITUIR
ADMIN_PASSWORD=SUBSTITUIR

LDAP_URL=SUBSTITUIR
LDAP_BIND_DN=SUBSTITUIR
LDAP_BIND_PASSWORD=SUBSTITUIR
LDAP_SEARCH_BASE=SUBSTITUIR
LDAP_SEARCH_FILTER=SUBSTITUIR
```

Gere um segredo de sessão forte:

```powershell
[Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(48))
```

Copie o resultado para `SESSION_SECRET`. Não reutilize senhas de usuário como segredo de sessão.

Confirme que o `.env` não será versionado:

```powershell
Set-Location C:\Apps\PSPanel
git check-ignore .env
```

O comando deve imprimir `.env` ou seu caminho. Restrinja a leitura do arquivo `.env` à conta de serviço, administradores autorizados e `SYSTEM`.

### HTTP interno temporário

Enquanto o acesso ocorrer diretamente por HTTP na porta 3000, mantenha:

```dotenv
SESSION_COOKIE_SECURE=false
```

Essa configuração permite o login em `http://servidor:3000`, mas credenciais e cookie de sessão trafegam sem criptografia. Restrinja a porta por firewall às redes administrativas necessárias.

Ao implantar HTTPS com proxy reverso, configure corretamente a confiança no proxy e altere para:

```dotenv
SESSION_COOKIE_SECURE=true
```

## 9. Teste inicial da aplicação

Antes de criar o serviço, valide:

```powershell
Set-Location C:\Apps\PSPanel
node app.js
```

Em outra estação autorizada, acesse:

```text
http://NOME-OU-IP-DO-SERVIDOR:3000/login
```

Teste o login local e o login pelo Active Directory. Finalize o processo manual com `Ctrl+C` antes de continuar.

## 10. Instalar a aplicação como serviço com WinSW

Baixe uma versão estável e homologada do WinSW pelo projeto oficial:

```text
https://github.com/winsw/winsw/releases
```

Coloque o executável em:

```text
C:\Apps\PSPanel\service\PSPanelWeb.exe
```

Crie ao lado o arquivo `C:\Apps\PSPanel\service\PSPanelWeb.xml`:

```xml
<service>
  <id>PSPanelWeb</id>
  <name>PS Panel Web</name>
  <description>Interface web e execução interativa do PS Panel.</description>

  <executable>C:\Program Files\nodejs\node.exe</executable>
  <arguments>app.js</arguments>
  <workingdirectory>C:\Apps\PSPanel</workingdirectory>

  <startmode>Automatic</startmode>
  <delayedAutoStart>true</delayedAutoStart>

  <logpath>C:\Apps\PSPanel\log\service</logpath>
  <log mode="roll-by-size">
    <sizeThreshold>10485760</sizeThreshold>
    <keepFiles>10</keepFiles>
  </log>

  <onfailure action="restart" delay="10 sec"/>
  <resetfailure>1 hour</resetfailure>
  <stoptimeout>30 sec</stoptimeout>
  <hidewindow>true</hidewindow>
</service>
```

Não coloque a conta ou senha de serviço nesse XML.

Instale o serviço em PowerShell administrativo:

```powershell
Set-Location C:\Apps\PSPanel\service
.\PSPanelWeb.exe install
```

Ainda não inicie o serviço. Abra:

```powershell
services.msc
```

Localize **PS Panel Web**, abra **Propriedades > Logon**, selecione **Esta conta** e informe:

```text
DOMINIO\svc_pspanel
```

Digite e confirme a senha da conta. Essa foi a forma adotada na instalação homologada. Verifique também o tipo de inicialização automático e as ações de recuperação.

Depois inicie e valide:

```powershell
Start-Service PSPanelWeb
Get-Service PSPanelWeb
```

Teste a resposta HTTP:

```powershell
Invoke-WebRequest -Uri http://127.0.0.1:3000/login -UseBasicParsing
```

Consulte os logs em:

```text
C:\Apps\PSPanel\log
C:\Apps\PSPanel\log\service
```

## 11. Instalar o worker no Agendador de Tarefas

O worker não chama `Invoke-ScheduleWorker.ps1`. A tarefa criada no ambiente homologado executa diretamente:

```text
C:\Program Files\nodejs\node.exe scripts-js/schedule-worker.js
```

Com o diretório de trabalho:

```text
C:\Apps\PSPanel
```

O repositório fornece o instalador:

```text
deploy\windows\Install-PSPanelScheduleWorker.ps1
```

Execute em PowerShell administrativo:

```powershell
Set-Location C:\Apps\PSPanel

pwsh.exe -NoProfile -File `
    .\deploy\windows\Install-PSPanelScheduleWorker.ps1 `
    -RunAsUser 'DOMINIO\svc_pspanel'
```

Será solicitado o usuário e a senha da conta de serviço. A credencial não é gravada no script; o Agendador de Tarefas a armazena pelo mecanismo do Windows.

O instalador cria a tarefa **PSPanel Schedule Worker** com:

- repetição a cada cinco minutos;
- execução sem usuário conectado;
- início assim que possível após um horário perdido;
- limite de uma hora por execução;
- política `IgnoreNew`, que impede duas instâncias simultâneas.

Para substituir uma tarefa existente:

```powershell
pwsh.exe -NoProfile -File `
    .\deploy\windows\Install-PSPanelScheduleWorker.ps1 `
    -RunAsUser 'DOMINIO\svc_pspanel' `
    -Force
```

Valide e teste:

```powershell
Get-ScheduledTask -TaskName 'PSPanel Schedule Worker' |
    Select-Object TaskName,State,@{Name='Execute';Expression={$_.Actions.Execute}},@{Name='Arguments';Expression={$_.Actions.Arguments}},@{Name='WorkingDirectory';Expression={$_.Actions.WorkingDirectory}}

Start-ScheduledTask -TaskName 'PSPanel Schedule Worker'
Start-Sleep -Seconds 10

Get-ScheduledTaskInfo -TaskName 'PSPanel Schedule Worker' |
    Select-Object LastRunTime,LastTaskResult,NextRunTime
```

`LastTaskResult` deve ser `0`.

## 12. Configurar SMTP

O arquivo real de SMTP não vem pelo Git porque contém senha. Depois do primeiro login, acesse:

```text
Configurações > Email - Servidor SMTP
```

Preencha:

- host SMTP;
- porta `587` para STARTTLS ou `465` para TLS implícito;
- usuário;
- senha;
- endereço do remetente.

Ao salvar, a aplicação cria:

```text
C:\Apps\PSPanel\database\email-settings.json
```

Confirme a existência sem imprimir o conteúdo:

```powershell
Test-Path C:\Apps\PSPanel\database\email-settings.json
Get-Item C:\Apps\PSPanel\database\email-settings.json | Select-Object FullName,Length,LastWriteTime
```

Restrinja esse arquivo à conta de serviço, administradores autorizados e `SYSTEM`.

Teste a conectividade antes de diagnosticar autenticação SMTP:

```powershell
Test-NetConnection SMTP.EXEMPLO.LOCAL -Port 587
```

## 13. Preparar o backup do Fortigate

Garanta que:

- a conta de serviço possa gravar em `C:\FortiGate-Backup`;
- a VM esteja autorizada no Fortigate para acesso administrativo SSH;
- a porta 22 esteja liberada entre a VM e o equipamento;
- o usuário informado ao script tenha permissão para executar os comandos necessários.

Teste a rede:

```powershell
Test-NetConnection IP-DO-FORTIGATE -Port 22
```

O script mantém atualmente `-AcceptKey -Force`, portanto o Posh-SSH exibe um aviso informando que a chave do host não está sendo validada. Essa é uma pendência de segurança conhecida e deve ser tratada futuramente com uma store de hosts confiáveis.

Se o Fortigate aceitar a autenticação e encerrar a sessão por restrição do host de origem, o script encerra com código diferente de zero e informa que os hosts confiáveis e o acesso administrativo SSH devem ser verificados.

Como `C:\FortiGate-Backup` também é inicializado como repositório Git local, configure uma identidade de commit visível à conta de serviço, conforme o padrão da organização. Exemplo de configuração no escopo do sistema:

```powershell
git config --system user.name 'PSPanel Service'
git config --system user.email 'pspanel@empresa.local'
```

Substitua o endereço pelo valor institucional aprovado.

## 14. Firewall e conectividade

Libere somente o necessário:

| Origem | Destino | Porta | Uso |
|---|---|---:|---|
| redes internas autorizadas | VM PS Panel | TCP 3000 | acesso HTTP inicial |
| VM PS Panel | controladores LDAP | conforme ambiente | autenticação AD |
| VM PS Panel | servidor SMTP | TCP 587 ou 465 | envio de email |
| VM PS Panel | Fortigate | TCP 22 e APIs utilizadas | backup e relatórios |
| VM PS Panel | servidores e compartilhamentos autorizados | conforme scripts | automações PowerShell |

Não publique a porta 3000 na internet.

## 15. Atualização da aplicação

Na estação de desenvolvimento, depois de concluir, commitar e enviar a release
para `origin/main`, valide e crie a tag correspondente ao valor de
`src/config/release.js`:

```powershell
Set-Location C:\Projects\PSPanel

.\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf
.\deploy\windows\New-PSPanelReleaseTag.ps1
```

O script recusa uma árvore de trabalho com alterações, confirma que o commit
atual já está publicado em `origin/main` e consulta tags locais e remotas. Se
existir uma release igual ou posterior, nenhuma tag será criada. Em caso de
sucesso, ele cria uma tag anotada e a envia ao `origin`.

Prefira implantar uma tag de release ou um hash de commit imutável com o script
semi-automático. Abra o PowerShell 7 como administrador e faça primeiro uma
simulação:

```powershell
Set-Location C:\Apps\PSPanel

.\deploy\windows\Update-PSPanel.ps1 `
    -Version 'HASH_OU_TAG' `
    -WhatIf
```

Se o plano e as verificações preliminares estiverem corretos, execute sem
`-WhatIf`:

```powershell
.\deploy\windows\Update-PSPanel.ps1 -Version 'HASH_OU_TAG'
```

O script:

- exige execução como administrador e a versão homologada do Node.js;
- recusa alterações locais em arquivos versionados;
- atualiza as referências Git antes de interromper a aplicação;
- para o serviço e desabilita o worker;
- salva `.env`, `database` e a configuração local do WinSW em
  `C:\Apps\PSPanel-Backups`;
- executa `npm ci --omit=dev` e valida a sintaxe dos arquivos JavaScript e
  PowerShell versionados;
- inicia o serviço, testa `http://127.0.0.1:3000/login` e reativa o worker;
- tenta voltar automaticamente ao commit e aos dados anteriores se o deploy
  falhar.

Os logs ficam em `C:\Apps\PSPanel\log\deploy`. Por padrão, os dez snapshots
mais recentes são mantidos. O teste imediato do worker pode executar jobs
vencidos; quando isso não for desejado, use `-SkipWorkerTest`. A versão é
implantada em modo detached HEAD para que o servidor permaneça exatamente no
commit escolhido.

Para rollback manual, informe o nome do snapshot mostrado no resumo ou na pasta
de backups:

```powershell
.\deploy\windows\Update-PSPanel.ps1 `
    -Rollback '2026-07-22_103000-12345'
```

O rollback cria antes um novo snapshot do estado corrente. Branches móveis não
são aceitos por padrão; para atualizar diretamente de `origin/main`, é
necessário optar explicitamente por esse risco:

```powershell
.\deploy\windows\Update-PSPanel.ps1 -Version 'origin/main' -Force
```

Se o script não puder ser usado, o procedimento manual de contingência é:

```powershell
Stop-Service PSPanelWeb
Disable-ScheduledTask -TaskName 'PSPanel Schedule Worker'
Stop-ScheduledTask -TaskName 'PSPanel Schedule Worker' -ErrorAction SilentlyContinue

Set-Location C:\Apps\PSPanel
git status
git fetch origin --tags --prune
git switch --detach HASH_OU_TAG
npm ci --omit=dev

node --check app.js
node --check scripts-js\schedule-worker.js

Enable-ScheduledTask -TaskName 'PSPanel Schedule Worker'
Start-Service PSPanelWeb
```

Não use `git reset --hard`, não sobrescreva o `.env` e não substitua os arquivos SQLite durante uma atualização normal.

## 16. Backup operacional

Inclua no backup da VM ou da aplicação:

```text
C:\Apps\PSPanel\database\pspanel.sqlite
C:\Apps\PSPanel\database\email-settings.json
C:\Apps\PSPanel\.env
C:\Apps\PSPanel\scripts-ps
C:\Apps\PSPanel\log
C:\FortiGate-Backup
```

Considere os arquivos `-wal` e `-shm` ao realizar backup de um SQLite em uso. Prefira uma cópia consistente ou uma janela com o serviço e o worker parados.

Proteja os backups porque eles podem conter dados operacionais, resultados de scripts e segredos.

## 17. Verificação final

- [ ] Windows Server atualizado e com horário correto.
- [ ] PowerShell 7.6.3 disponível.
- [ ] Node.js retorna `v24.18.0`.
- [ ] Git disponível no `PATH` do sistema.
- [ ] Repositório clonado em `C:\Apps\PSPanel`.
- [ ] `npm ci --omit=dev` concluído.
- [ ] `.env` criado, protegido e ignorado pelo Git.
- [ ] Serviço `PSPanelWeb` executando com a conta dedicada.
- [ ] Serviço configurado para início automático e reinício após falha.
- [ ] Login local e Active Directory validados.
- [ ] Tarefa `PSPanel Schedule Worker` executando `schedule-worker.js`.
- [ ] `LastTaskResult` do worker igual a `0`.
- [ ] Conta de serviço com acesso a `database`, `log` e diretórios dos scripts.
- [ ] SMTP salvo e testado pela interface.
- [ ] Acesso SSH da VM autorizado no Fortigate.
- [ ] Porta 3000 restrita às redes internas necessárias.
- [ ] Backup operacional configurado.

## 18. Limitações e pendências conhecidas

- O acesso HTTP na porta 3000 não criptografa credenciais nem cookies.
- O `MemoryStore` padrão do `express-session` ainda não é adequado para produção: as sessões são perdidas ao reiniciar o serviço e não há suporte seguro a múltiplos processos Node.
- O login local ainda utiliza `ADMIN_PASSWORD` do ambiente; trate o `.env` como segredo.
- O backup do Fortigate ainda usa `-Force` no Posh-SSH e não valida a chave do equipamento.
- A instalação descrita é de instância única, com SQLite local, sem alta disponibilidade.

As pendências devem ser avaliadas antes de ampliar a exposição, o número de usuários ou os privilégios das automações.
