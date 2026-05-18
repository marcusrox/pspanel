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

Em operação Windows, o script `scripts-ps/Invoke-ScheduleWorker.ps1` pode ser usado pelo Agendador de Tarefas para chamar o worker periodicamente.

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

Observação: `npm test` ainda não possui testes automatizados reais e retorna erro por configuração do próprio `package.json`.

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