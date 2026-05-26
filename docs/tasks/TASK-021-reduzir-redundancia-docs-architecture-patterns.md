# TASK-021 - Reduzir redundancia entre architecture e patterns

## Contexto

Os arquivos `docs/architecture.md` e `docs/patterns.md` possuem informacoes parcialmente sobrepostas. Ambos falam sobre estrutura de diretorios, rotas, controllers, models, services, execucao PowerShell, workers, configuracoes e cuidados de evolucao.

Essa duplicidade aumenta o risco de documentacao divergente quando o sistema muda. O ideal e cada documento ter uma responsabilidade clara:

- `docs/architecture.md`: descrever como o sistema esta organizado e como os fluxos atuais funcionam.
- `docs/patterns.md`: orientar como implementar mudancas seguindo os padroes do projeto.

## Objetivo

Reorganizar os dois documentos para remover redundancias, mantendo cada informacao no arquivo mais pertinente e preservando a utilidade dos dois arquivos para manutencao e para agentes de IA.

## Escopo

- Revisar `docs/architecture.md` e `docs/patterns.md`.
- Identificar blocos redundantes ou muito parecidos entre os dois arquivos.
- Manter em `docs/architecture.md` informacoes sobre:
  - visao geral do sistema;
  - componentes principais;
  - pontos de entrada;
  - estrutura de diretorios em alto nivel;
  - camadas e responsabilidades atuais;
  - fluxos principais;
  - persistencia;
  - rotas HTTP existentes;
  - configuracao operacional;
  - seguranca atual e pontos de atencao;
  - operacao e recomendacoes de evolucao.
- Manter em `docs/patterns.md` informacoes sobre:
  - como organizar novas mudancas;
  - padroes de CommonJS;
  - padroes de rotas, controllers, models e services;
  - padroes de views EJS, formularios e flash messages;
  - padroes de execucao PowerShell;
  - padroes de agendamentos e workers;
  - validacoes esperadas;
  - estilo de codigo;
  - cuidados praticos ao evoluir.
- Adicionar uma nota curta no topo de cada arquivo explicando a responsabilidade do documento e apontando para o outro quando apropriado.
- Remover exemplos ou explicacoes duplicadas quando um link textual para o outro documento for suficiente.

## Fora de escopo

- Alterar codigo da aplicacao.
- Alterar rotas, controllers, models, services ou views.
- Alterar arquivos SQLite, `.env`, `.env.example`, `package.json` ou `package-lock.json`.
- Reescrever toda a documentacao do projeto.
- Criar nova estrutura ampla de documentacao.
- Remover informacoes uteis apenas por estarem citadas nos dois arquivos, quando a repeticao for necessaria por contexto.
- Executar automaticamente a implementacao desta task apos criar o arquivo.

## Arquivos provaveis

```text
docs/architecture.md
docs/patterns.md
```

## Diretriz editorial

Usar esta divisao como regra principal:

- Se a informacao responde "como o sistema funciona hoje?", ela pertence principalmente a `docs/architecture.md`.
- Se a informacao responde "como devo implementar uma mudanca?", ela pertence principalmente a `docs/patterns.md`.

Quando uma informacao for necessaria nos dois contextos, manter uma versao completa em apenas um arquivo e uma referencia curta no outro.

## Redundancias conhecidas

1. Estrutura de diretorios:
   - manter a arvore e descricao geral em `docs/architecture.md`;
   - manter em `docs/patterns.md` apenas orientacoes praticas sobre onde criar novos arquivos.
2. Rotas, controllers, models e services:
   - manter mapa de responsabilidades atuais em `docs/architecture.md`;
   - manter padroes de implementacao e exemplos curtos em `docs/patterns.md`.
3. Execucao PowerShell:
   - manter fluxo narrativo em `docs/architecture.md`;
   - manter regras de seguranca e padrao de `spawn` em `docs/patterns.md`.
4. Agendamentos e worker:
   - manter fluxo completo de agendamento em `docs/architecture.md`;
   - manter regras praticas de worker, lock e auditoria em `docs/patterns.md`.
5. Configuracoes:
   - manter configuracoes existentes e persistencia em `docs/architecture.md`;
   - manter orientacao para adicionar e validar configuracoes em `docs/patterns.md`.
6. Cuidados e pontos de atencao:
   - manter riscos arquiteturais e recomendacoes em `docs/architecture.md`;
   - manter cuidados de implementacao em `docs/patterns.md`.

## Sugestao de implementacao

1. Adicionar em `docs/architecture.md`, logo apos o titulo, uma nota curta:

```md
Este documento descreve a estrutura e os fluxos atuais do sistema. Regras de implementacao ficam em `docs/patterns.md`.
```

2. Adicionar em `docs/patterns.md`, logo apos o titulo, uma nota curta:

```md
Este documento descreve padroes para implementar mudancas. Descricao arquitetural e fluxos completos ficam em `docs/architecture.md`.
```

3. Em `docs/architecture.md`, remover ou reduzir exemplos de codigo e orientacoes detalhadas que pertencam a padroes de implementacao.
4. Em `docs/patterns.md`, remover ou reduzir descricoes longas do estado atual que ja estejam cobertas por `docs/architecture.md`.
5. Substituir blocos removidos por referencias curtas quando a navegabilidade ficar melhor.
6. Preservar informacoes de seguranca em ambos os documentos apenas quando a repeticao tiver papel diferente:
   - arquitetura: riscos e controles existentes;
   - patterns: regras obrigatorias para novas mudancas.
7. Fazer uma leitura final dos dois arquivos para confirmar que nenhum deles ficou dependente demais do outro para ser entendido.

## Criterios de aceite

- `docs/architecture.md` continua explicando claramente a organizacao e os fluxos atuais do PS Panel.
- `docs/patterns.md` continua sendo suficiente para orientar implementacoes pequenas e seguras no projeto.
- Informacoes duplicadas sobre estrutura, camadas, PowerShell, worker e configuracoes foram reduzidas.
- Cada documento possui uma nota inicial indicando seu papel e apontando para o outro documento.
- Nao ha mudancas em codigo da aplicacao.
- Nao ha mudancas em arquivos SQLite, `.env`, `.env.example`, `package.json` ou `package-lock.json`.
- A documentacao resultante nao contradiz a implementacao atual do projeto.

## Testes sugeridos

- Revisar manualmente `docs/architecture.md`.
- Revisar manualmente `docs/patterns.md`.
- Rodar uma busca por termos-chave para confirmar que informacoes essenciais ainda existem no documento adequado:

```powershell
rg -n "scripts-ps|schedule-worker|Settings|getAll|spawn|isAuthenticated|schema_migrations" docs\architecture.md docs\patterns.md
```

- Conferir `git diff -- docs\architecture.md docs\patterns.md` para validar que as remocoes sao editoriais e nao apagam regras importantes.

## Validacao esperada

- Revisao manual dos dois documentos alterados.
- `git diff -- docs\architecture.md docs\patterns.md`
- Busca por termos-chave relevantes com `rg`.

Se alguma informacao parecer pertencer aos dois arquivos, manter a versao completa no documento mais pertinente e deixar apenas uma referencia curta no outro.
