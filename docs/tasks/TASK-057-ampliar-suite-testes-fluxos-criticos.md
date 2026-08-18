# TASK-057 - Ampliar suite de testes dos fluxos criticos

## Contexto

A suite atual cobre recorrencia, retentativas, migrations, algumas views e o
runner de PowerShell. Antes de usar testes como barreira para publicacao de uma
release, e necessario cobrir os contratos de maior risco que ainda possam
permitir uma regressao funcional ou de seguranca.

## Objetivo

Ampliar a suite `node:test` com testes deterministas dos fluxos criticos do PS
Panel, sem acessar infraestrutura corporativa real e sem transformar esta task
em uma refatoracao ampla da aplicacao.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Escopo prioritario

Adicionar testes, quando ainda nao houver cobertura equivalente, para:

1. validacao de nomes de scripts `.ps1`, rejeitando `..`, `/` e `\`;
2. restricao da execucao ao diretorio `scripts-ps/`;
3. protecao das rotas autenticadas de execucao, historico, configuracoes e
   agendamentos;
4. escape de saida nao confiavel renderizada em HTML;
5. parsing e preservacao de argumentos PowerShell com espacos e acentos;
6. execucao manual e agendada sem montar comandos por concatenacao;
7. inicializacao e migrations do SQLite usando banco temporario;
8. compilacao das views EJS operacionais;
9. validacao de configuracoes aceitas pelos controllers;
10. comportamento controlado quando dependencias externas falham.

## Estrategia de teste

- Permanecer no modulo nativo `node:test` e `node:assert`.
- Usar diretorios e bancos temporarios exclusivos por teste.
- Restaurar mocks e variaveis de processo em `afterEach` ou `t.after()`.
- Simular LDAP, SMTP, Fortigate e processos externos; nao usar endpoints reais.
- Nao ler nem imprimir o conteudo de `.env`.
- Nao iniciar servidor na porta `3000`.
- Se um teste HTTP for indispensavel, usar porta `3100` ou proxima livre,
  capturar o PID e encerrar somente o processo criado pelo teste.
- Extrair helpers pequenos apenas quando isso for necessario para testar uma
  regra critica; evitar refatoracoes de arquitetura.

## Arquivos previstos

```text
test/*.test.js
src/routes/mainRoutes.js
src/middleware/authMiddleware.js
src/services/powerShellRunner.js
src/config/release.js
```

Os arquivos de producao listados sao possibilidades, nao obrigacoes. Alterar
somente os pontos necessarios para expor dependencias ou regras de forma
testavel, preservando contratos existentes.

## Fora de escopo

- Testes end-to-end contra Active Directory, SMTP ou equipamentos reais.
- Medicao ou meta obrigatoria de cobertura percentual.
- Adocao de novo framework.
- Correcao oportunista de todos os riscos descritos em `docs/architecture.md`.
- Testes de carga, alta disponibilidade ou multiplas instancias.
- Alteracao do processo de criacao de tags ou deploy.

## Validacao obrigatoria

```powershell
npm test
node --check app.js
node --check src\routes\mainRoutes.js
node --check src\services\powerShellRunner.js
```

Executar `node --check` apenas nos arquivos JavaScript efetivamente alterados,
alem do bootstrap quando ele for tocado.

## Criterios de aceite

- Os fluxos criticos aplicaveis possuem testes automatizados deterministas.
- A suite nao depende de rede, credenciais reais ou dados persistentes locais.
- Arquivos temporarios sao removidos ao final dos testes.
- Falhas de seguranca exercitadas fazem o teste falhar de forma objetiva.
- Todos os testes podem ser executados com um unico `npm test`.
- Nenhum banco em `database/` e modificado.
- O release e atualizado conforme `AGENTS.md` somente ao concluir a task.

## Dependencias

- TASK-056 concluida.

---

## Assinatura da LLM

- Data: 2026-08-18 11:23:31 -03:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
