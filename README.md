# PS Panel

Painel web para execução controlada, histórico e agendamento de scripts PowerShell, desenvolvido com Node.js, Express, EJS e SQLite.

## Sobre o projeto

O PS Panel centraliza scripts PowerShell em uma interface web autenticada. Ele permite listar scripts disponíveis, visualizar ajuda e parâmetros, executar scripts manualmente, consultar histórico, configurar opções básicas e criar agendamentos executados por um worker Node.js.

O projeto é voltado para uso operacional por equipes de infraestrutura, automação e DevOps que precisam executar scripts com mais rastreabilidade e controle.

## Funcionalidades

- Autenticação local ou via LDAP/Active Directory.
- Listagem de scripts `.ps1` localizados em `scripts-ps/`.
- Execução manual de scripts PowerShell com parâmetros.
- Visualização de saída e registro de histórico.
- Cadastro e manutenção de agendamentos.
- Worker para execução periódica de jobs vencidos.
- Auditoria de ações relacionadas a agendamentos.
- Interface web em EJS com CSS próprio e HTMX em telas específicas.

## Tecnologias

Backend:

- Node.js
- Express.js
- SQLite
- PowerShell
- LDAP, quando configurado

Frontend:

- EJS
- HTML e CSS
- HTMX em telas específicas
- Font Awesome via CDN em views que usam ícones

## Pré-requisitos

- Node.js 18 ou superior recomendado.
- npm.
- PowerShell 5.1 ou superior no ambiente Windows.
- Permissões adequadas para executar os scripts PowerShell usados pela aplicação.

## Instalação

Clone o repositório e instale as dependências:

```bash
git clone https://github.com/marcusrox/pspanel.git
cd pspanel
npm install
```

Crie o arquivo de ambiente a partir do exemplo:

```bash
cp .env.example .env
```

No Windows PowerShell, se preferir:

```powershell
Copy-Item .env.example .env
```

Edite o `.env` com as configurações do seu ambiente antes de iniciar a aplicação.

## Configuração

As principais variáveis estão documentadas em `.env.example`.

Variáveis essenciais:

```env
PORT=3000
NODE_ENV=development
SESSION_SECRET=sua-chave-secreta-aqui
ADMIN_USER=admin
ADMIN_PASSWORD=123456
```

Variáveis LDAP, quando usar autenticação por Active Directory:

```env
LDAP_URL=ldap://servidor.exemplo.local
LDAP_BIND_DN=usuario_servico@exemplo.local
LDAP_BIND_PASSWORD=senha-da-conta-de-servico
LDAP_SEARCH_BASE=DC=exemplo,DC=local
LDAP_SEARCH_FILTER=(&(objectClass=user)(sAMAccountName={{username}}))
```

Observações:

- Não versione valores reais de `.env`.
- `SESSION_SECRET` deve ser alterado em qualquer ambiente compartilhado ou produtivo.
- O fluxo local atual usa `ADMIN_USER` e `ADMIN_PASSWORD`.
- `ADMIN_PASSWORD_HASH` existe no `.env.example`, mas consulte `docs/ARCHITECTURE.md` para o estado atual da autenticação antes de depender dele.

## Execução

Iniciar a aplicação:

```bash
npm start
```

Iniciar em modo desenvolvimento com `nodemon`:

```bash
npm run dev
```

Executar o worker de agendamentos:

```bash
npm run schedule-worker
```

Em operação Windows, configure o Agendador de Tarefas para executar periodicamente
o Node.js com o argumento `scripts-js/schedule-worker.js` e a raiz do PS Panel
como diretório de trabalho.

## Atualização em produção

O ambiente Windows de produção é atualizado pelo script
`deploy/windows/Update-PSPanel.ps1`, usando uma tag de release ou um hash de
commit Git. O fluxo interrompe temporariamente o serviço web e o worker, cria um
snapshot dos dados locais, instala a versão, valida a aplicação e tenta fazer
rollback automático em caso de falha.

### Pré-requisitos do servidor

Por padrão, o atualizador espera:

- PowerShell executado como administrador;
- projeto instalado como clone Git em `C:\Apps\PSPanel`;
- serviço Windows `PSPanelWeb` já instalado;
- tarefa agendada `PSPanel Schedule Worker` já instalada;
- Git, Node.js e npm disponíveis no `PATH`;
- Node.js `v24.18.0`, salvo se outra versão for informada em
  `-RequiredNodeVersion`;
- `.env`, `package-lock.json` e `database\pspanel.sqlite` presentes;
- nenhum arquivo rastreado pelo Git com alteração local.

O worker pode ser instalado separadamente com
`deploy/windows/Install-PSPanelScheduleWorker.ps1`. O script de atualização não
instala o serviço web nem a tarefa agendada; ele pressupõe que ambos já estejam
configurados.

### Criar e publicar a release

Antes da atualização, incremente `src/config/release.js` no formato
`vAAAA.MM.DD-NNN` e valide a candidata na estação DEV:

```powershell
.\deploy\windows\Test-PSPanelRelease.ps1
```

O validador exige, por padrão, Node.js `v24.18.0`, executa `npm ci`, `npm test`
e confere a sintaxe de todos os arquivos JavaScript e PowerShell rastreados pelo
Git. Ele não inicia a aplicação, o worker nem scripts de `scripts-ps/`, e não
acessa `.env`, bancos, serviços ou tarefas agendadas. Como `npm ci` recria
`node_modules`, encerre antes eventuais processos locais que estejam usando suas
dependências.

Depois da validação, faça commit e envie o branch `main`. Em uma árvore de
trabalho limpa e sincronizada com `origin/main`, valide e publique a tag:

```powershell
.\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf
.\deploy\windows\New-PSPanelReleaseTag.ps1
```

O script cria uma tag Git anotada com o mesmo identificador de `release.js` e a
publica no repositório remoto. A operação é recusada se já existir uma release
igual ou posterior. Antes de qualquer `git tag` ou `git push`, o próprio script
executa obrigatoriamente `Test-PSPanelRelease.ps1`; não existe opção para ignorar
os testes. O `-WhatIf` também executa `npm ci`, a suíte e as validações de
sintaxe, mas não cria nem publica tags. Portanto, encerre processos locais que
estejam usando `node_modules` antes da simulação e da execução efetiva.

### Aplicar a atualização

No servidor de produção, abra o PowerShell como administrador e execute primeiro
uma simulação. Informe a tag que foi efetivamente publicada; `vAAAA.MM.DD-NNN`
representa apenas o formato e não deve ser usado literalmente:

```powershell
Set-Location C:\Apps\PSPanel
$release = Read-Host 'Informe a tag publicada (ex.: v2026.07.22-034)'

.\deploy\windows\Update-PSPanel.ps1 `
    -Version $release `
    -WhatIf
```

Depois, aplique a versão:

```powershell
.\deploy\windows\Update-PSPanel.ps1 `
    -Version $release
```

Na simulação, o script valida o formato da referência e confirma que uma tag de
release existe no `origin`. Quando um hash é informado, ele deve estar disponível
no clone local. Nenhum checkout, instalação ou reinício é realizado pelo
`-WhatIf`.

Durante o deploy, o atualizador:

1. busca tags e referências do `origin` e resolve a versão para um commit;
2. desabilita e encerra o worker e para o serviço web;
3. salva `database/`, `.env` e, quando existente, `service/PSPanelWeb.xml`;
4. aplica o commit em modo `detached HEAD` e executa `npm ci --omit=dev`;
5. valida a sintaxe dos arquivos JavaScript e PowerShell versionados;
6. inicia o serviço e testa `http://127.0.0.1:3000/login`;
7. reativa o worker e executa um teste imediato;
8. mantém, por padrão, os dez snapshots mais recentes.

Os snapshots ficam em `C:\Apps\PSPanel-Backups\<identificador>` e os logs em
`C:\Apps\PSPanel\log\deploy`. Existe uma janela de indisponibilidade entre a
parada do serviço e a aprovação do health check.

### Rollback

Se houver falha após a parada dos componentes, o atualizador tenta restaurar
automaticamente o commit, o banco e as configurações anteriores. Para restaurar
manualmente um snapshot específico, use o nome do diretório de backup:

```powershell
.\deploy\windows\Update-PSPanel.ps1 `
    -Rollback '2026-07-22_103000-12345'
```

Se o deploy e o rollback automático falharem, o worker permanece desabilitado e
o log do deploy deve ser consultado antes da intervenção manual.

## Scripts PowerShell

- Coloque scripts executáveis pela aplicação em `scripts-ps/`.
- Apenas arquivos `.ps1` dentro desse diretório devem ser executados pelo painel.
- Documente os parâmetros no próprio script PowerShell sempre que possível.
- Evite que scripts imprimam dados sensíveis na saída, pois a aplicação registra histórico.

## Estrutura do projeto

```text
pspanel/
├── app.js                    # Bootstrap principal da aplicação web
├── package.json              # Dependências e scripts npm
├── AGENTS.md                 # Instruções para agentes de IA
├── public/                   # CSS, imagens e assets públicos
├── views/                    # Templates EJS
├── src/
│   ├── controllers/          # Fluxos de formulário e telas administrativas
│   ├── middleware/           # Middleware de autenticação
│   ├── models/               # Models SQLite
│   ├── routes/               # Rotas Express
│   └── services/             # Autenticação, LDAP e integrações
├── scripts-js/               # Utilitários Node.js e worker
├── scripts-ps/               # Scripts PowerShell executáveis
├── database/                 # Bancos SQLite locais
└── docs/                     # Arquitetura, padrões e tarefas
```

## Segurança

Este projeto executa scripts PowerShell, então mudanças devem tratar segurança como parte central da implementação.

Controles e cuidados importantes:

- Scripts devem permanecer restritos ao diretório `scripts-ps/`.
- Nomes de scripts devem ser validados para evitar `..`, `/` e `\`.
- Use `spawn` com array de argumentos ao executar processos; não monte comandos concatenando entrada de usuário.
- Rotas operacionais devem exigir autenticação.
- Saídas de scripts renderizadas em HTML devem ser escapadas.
- Segredos de `.env`, LDAP, sessão e autenticação não devem ser impressos em logs.
- Bancos SQLite locais podem conter estado operacional e não devem ser tratados como código fonte comum.

Veja também `docs/ARCHITECTURE.md` para riscos conhecidos e recomendações de evolução.

## Desenvolvimento

Antes de alterar código, leia:

- `AGENTS.md` para regras de trabalho com ferramentas de IA.
- `docs/patterns.md` para padrões de implementação do projeto.
- `docs/ARCHITECTURE.md` para arquitetura, fluxos e pontos de atenção.

Validações úteis:

```bash
node --check app.js
node --check src/routes/mainRoutes.js
node --check scripts-js/schedule-worker.js
```

Execute a suíte automatizada baseada no test runner nativo do Node.js com:

```bash
npm test
```

O comando descobre os arquivos de teste mantidos em `test/` e retorna código
diferente de zero quando qualquer caso falha.

Antes de criar uma tag de release, execute a barreira completa da estação DEV:

```powershell
.\deploy\windows\Test-PSPanelRelease.ps1
```

## Uso com ferramentas de IA

Para Codex e outras ferramentas de geração de código, use este README apenas como visão geral do projeto.

O arquivo principal de instruções para IA é:

```text
AGENTS.md
```

Ordem recomendada de leitura para agentes:

1. `AGENTS.md`
2. `docs/patterns.md`
3. `docs/ARCHITECTURE.md`, quando a tarefa exigir contexto de fluxo, persistência ou segurança

Agentes devem preferir mudanças pequenas, preservar o trabalho local, evitar refatorações amplas sem solicitação explícita e não tocar em `.env`, `node_modules` ou bancos SQLite salvo quando a tarefa exigir.

## Documentação adicional

- `docs/ARCHITECTURE.md`: visão arquitetural, fluxos principais, persistência, rotas e riscos conhecidos.
- `docs/patterns.md`: padrões de código, rotas, controllers, models, views e workers.
- `docs/tasks/`: histórico de tarefas e decisões de implementação.

## Licença

Este projeto está sob a licença ISC conforme definido em `package.json`.

Desenvolvido com ❤️ pela equipe de Infraestrutura
