# TASK-044 - Criar pagina de ambiente de dados

## Contexto

O PS Panel ja possui a pagina autenticada **Ambiente de execucao** em
`/runtime-environment`, com informacoes do processo WEB, sistema operacional,
dependencias e configuracoes tecnicas seguras. Ainda nao existe uma visao
equivalente para diagnosticar a persistencia da aplicacao.

Atualmente, a persistencia principal usa SQLite por meio da conexao central em
`src/database/connection.js`, do schema versionado em
`src/database/schema.js` e dos models `History`, `Settings` e `Schedule`. Para
entender arquivos, tabelas, colunas, indices, migracoes, configuracao fisica e
volumetria, o operador precisa consultar codigo, filesystem e banco
separadamente.

Esta task propoe uma pagina interna, autenticada e somente leitura que consolide
essas informacoes sem expor conteudo de registros, configuracoes sensiveis,
saidas de scripts, parametros, usuarios, credenciais ou caminhos absolutos.

## Objetivo

Criar a pagina **Ambiente de dados** para apresentar, de forma organizada e
segura:

- tecnologias e componentes da camada de persistencia;
- arquivos fisicos relacionados a dados e seus metadados nao sensiveis;
- configuracao operacional do SQLite;
- estrutura logica do banco, incluindo tabelas, colunas e restricoes;
- indices e suas colunas;
- migracoes de schema aplicadas;
- relacionamentos declarados e relacionamentos logicos conhecidos;
- volumetria geral e por tabela;
- indicadores agregados de uso, crescimento, espaco livre e saude;
- instante da coleta e falhas parciais de diagnostico.

Adicionar uma navegacao local compartilhada entre **Ambiente de execucao** e
**Ambiente de dados**, visivel nas duas paginas.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes de produto

- A pagina e uma ferramenta de inventario e diagnostico, nao um gerenciador de
  banco de dados.
- A rota deve ser autenticada com o middleware existente.
- Todos os usuarios autenticados terao o mesmo acesso, pois o projeto ainda nao
  possui autorizacao por perfil.
- A coleta deve ser somente leitura e nao pode alterar banco, schema, arquivos,
  PRAGMAs persistentes ou configuracoes.
- A fonte de verdade do schema e o banco aberto pela conexao central, e nao uma
  copia estatica da documentacao.
- Estrutura fisica e estrutura logica devem aparecer em secoes distintas.
- Dados reais das tabelas nao devem ser exibidos. Somente metadados e agregados
  previamente classificados como seguros podem chegar a view.
- A pagina deve funcionar mesmo quando uma metrica opcional nao estiver
  disponivel na versao local do SQLite.
- A implementacao deve usar os recursos ja presentes no projeto, sem novas
  dependencias.

## Rotas e navegacao

Criar uma rota GET protegida:

```text
GET /data-environment
```

Requisitos:

- registrar `/data-environment` na lista protegida por `isAuthenticated` do
  `app.js` da raiz;
- montar um router dedicado na mesma base;
- criar uma navegacao local reutilizavel, preferencialmente no partial
  `views/partials/environment-navigation.ejs`;
- incluir o partial em `views/runtime-environment.ejs` e na nova view;
- mostrar os links **Ambiente de execucao** e **Ambiente de dados** nas duas
  paginas, apontando respectivamente para `/runtime-environment` e
  `/data-environment`;
- indicar a opcao ativa com texto/estilo e `aria-current="page"`, sem depender
  apenas de cor;
- manter o item **Ambiente** existente no rodape da sidebar e deixa-lo ativo em
  ambas as paginas;
- manter **Sair** como o ultimo item da sidebar;
- nao duplicar a sidebar nem criar itens principais separados para as duas
  paginas.

O partial deve receber explicitamente a opcao ativa, por exemplo
`activeEnvironment: 'runtime'` ou `activeEnvironment: 'data'`.

## Organizacao visual

Criar `views/data-environment.ejs` seguindo a identidade visual da pagina de
ambiente de execucao:

- idioma `pt-BR`;
- sidebar compartilhada, recebendo `user` e o menu ativo;
- `main.main-content`;
- exatamente um `h1` visivel com o titulo `Ambiente de dados`;
- subtitulo curto explicando que os dados sao metadados e agregados de
  diagnostico;
- navegacao local das duas paginas logo apos o cabecalho principal;
- alerts por `messages: res.locals.messages`;
- rodape compartilhado, preservando a release;
- estilos globais de `/styles.css` e CSS localizado apenas quando necessario.

Organizar o conteudo em secoes responsivas:

1. **Resumo**;
2. **Tecnologias e componentes**;
3. **Arquivos e armazenamento fisico**;
4. **Configuracao SQLite**;
5. **Tabelas e volumetria**;
6. **Estrutura das tabelas**;
7. **Indices**;
8. **Relacionamentos**;
9. **Migracoes de schema**;
10. **Saude e observacoes**.

Diretrizes visuais:

- usar cards compactos para tamanho total, tabelas, indices, registros e
  versao do SQLite;
- usar paineis com titulo e descricao curta;
- usar tabelas compactas para arquivos, tabelas, colunas, indices e migracoes;
- permitir expandir/recolher o detalhamento de cada tabela sem JavaScript
  complexo, usando elementos semanticos como `details`/`summary`;
- usar badges textuais para estados como `Disponivel`, `Indisponivel`,
  `Aplicada`, `Sem indice`, `Integro` e `Atencao`;
- formatar bytes em B, KiB, MiB ou GiB e datas em `pt-BR`;
- conter tabelas largas em wrappers proprios, sem overflow horizontal da
  pagina;
- manter boa legibilidade em desktop e mobile;
- nao redesenhar a sidebar, o rodape ou a identidade visual global.

## Tecnologias e componentes

Exibir, no minimo:

- mecanismo `SQLite`;
- versao do engine obtida por `SELECT sqlite_version()`;
- driver Node.js `sqlite3` e sua versao resolvida de forma segura;
- conexao central representada apenas pelo caminho relativo
  `src/database/connection.js`;
- schema/migracoes representado apenas por `src/database/schema.js`;
- models consumidores: `History`, `Settings` e `Schedule`;
- tipo de persistencia como `Banco local baseado em arquivo`;
- instante da coleta em ISO no service e formatado em `pt-BR` na interface.

Nao exibir caminho fisico do pacote, caminho absoluto do projeto ou detalhes de
compilacao do driver que revelem informacoes locais desnecessarias.

## Arquivos e armazenamento fisico

Inventariar somente o diretorio conhecido `database/`, sempre usando nomes e
caminhos relativos sanitizados.

Para cada artefato permitido, apresentar quando disponivel:

- nome relativo;
- categoria (`Banco principal`, `WAL`, `Memoria compartilhada`, `Banco legado`,
  `Backup`, `Configuracao de exemplo` ou `Outro artefato conhecido`);
- tamanho;
- data da ultima modificacao;
- estado `Presente` ou `Ausente` para os arquivos esperados.

Regras:

- identificar `pspanel.sqlite`, `pspanel.sqlite-wal` e `pspanel.sqlite-shm`;
- informar a existencia de bancos legados encontrados, como `history.sqlite` e
  `settings.sqlite`, sem abri-los nem inferir que ainda estejam em uso;
- resumir `database/backups/` por quantidade de arquivos e tamanho total, sem
  listar recursivamente subdiretorios ou abrir backups;
- nao ler nem exibir o conteudo de `email-settings.json`, bancos, WAL, SHM,
  backups ou qualquer arquivo de configuracao;
- nao seguir links simbolicos/reparse points para fora de `database/`;
- nao exibir caminhos absolutos, permissao/ACL, proprietario ou nome do usuario
  do sistema;
- aplicar limite explicito de itens e tratar excesso como resumo, para evitar
  pagina ou coleta sem limite;
- considerar o tamanho fisico total como a soma segura dos artefatos
  contabilizados, deixando claro quais categorias entraram no total.

## Configuracao operacional do SQLite

Consultar e apresentar de forma somente leitura:

- `journal_mode`;
- `foreign_keys`;
- `busy_timeout`;
- `synchronous`;
- `page_size`;
- `page_count`;
- `freelist_count`;
- `auto_vacuum`;
- `encoding`;
- quantidade de bancos anexados, sanitizando o resultado de `database_list`.

Calcular e rotular:

- tamanho logico aproximado: `page_size * page_count`;
- espaco livre interno aproximado: `page_size * freelist_count`;
- percentual aproximado de paginas livres, quando o divisor for valido.

Nao executar `VACUUM`, `ANALYZE`, mudanca de PRAGMA, checkpoint do WAL, attach,
detach ou qualquer comando que possa escrever ou bloquear desnecessariamente o
banco. Nao exibir o caminho retornado por `PRAGMA database_list`.

## Estrutura logica

Descobrir tabelas de usuario pelo catalogo SQLite, excluindo objetos internos
como `sqlite_sequence` da contagem principal. Para cada tabela, apresentar:

- nome validado e escapado;
- quantidade de colunas;
- quantidade de indices;
- quantidade de registros;
- tamanho fisico aproximado, quando `dbstat` estiver disponivel;
- participacao aproximada no tamanho mapeado;
- indicador de tabela vazia;
- data minima e maxima apenas para colunas temporais conhecidas e allowlisted,
  quando essa metrica for aplicavel.

Para o detalhamento de colunas, usar metadados estruturados de
`PRAGMA table_info`/`table_xinfo`:

- nome;
- tipo declarado;
- nulabilidade;
- chave primaria e ordem na chave;
- valor default apenas quando for uma expressao estrutural segura;
- indicador de coluna oculta/gerada, quando suportado.

Nao exibir o SQL bruto completo de `sqlite_schema`, triggers ou views. Nao
consultar nem renderizar valores individuais das tabelas.

## Volumetria e agregados seguros

Exibir a contagem total de registros como soma das tabelas de usuario e a
contagem individual por tabela.

Quando as tabelas atuais existirem, adicionar apenas agregados seguros e uteis:

- `script_history`: total por status, registros em execucao e intervalo entre a
  execucao mais antiga e a mais recente;
- `schedules`: total habilitado/desabilitado, com/sem recorrencia e com lock
  ativo;
- `schedule_audit`: quantidade total e intervalo temporal dos eventos;
- `settings`: somente quantidade de chaves, nunca nomes ou valores nesta tela;
- `schema_migrations`: quantidade aplicada e instante mais recente.

Requisitos de desempenho e privacidade:

- montar identificadores SQL apenas a partir de nomes descobertos e validados
  no catalogo, nunca de entrada do usuario;
- usar placeholders para todos os valores de consulta;
- executar contagens de forma sequencial ou com concorrencia pequena e
  controlada;
- degradar a metrica para `Indisponivel` se uma tabela desaparecer ou uma
  consulta falhar durante a coleta;
- nao calcular distribuicoes de `username`, `script_name`, parametros, saida,
  erro, detalhes de auditoria, valores de settings ou qualquer dado pessoal;
- nao criar cache persistente, tabela auxiliar, indice temporario ou arquivo de
  diagnostico;
- registrar na interface que contagens exatas podem refletir um instante
  ligeiramente diferente entre secoes, pois a aplicacao continua em uso.

## Indices e relacionamentos

Inventariar indices por metadados do SQLite (`index_list` e `index_xinfo` ou
equivalentes), exibindo:

- nome;
- tabela;
- colunas na ordem do indice;
- indicador de unicidade;
- origem (`CREATE INDEX`, restricao `UNIQUE` ou chave primaria), quando
  disponivel;
- indicador de indice parcial.

Nao exibir SQL bruto do indice.

Na secao de relacionamentos:

- listar foreign keys realmente declaradas por `PRAGMA foreign_key_list`;
- informar claramente quando nao houver foreign keys declaradas;
- representar separadamente relacoes logicas conhecidas pela aplicacao, como
  `schedules.id -> schedule_audit.schedule_id`, rotuladas como **relacao logica
  nao imposta por foreign key** quando esse continuar sendo o schema real;
- nao afirmar integridade referencial onde o SQLite nao a imponha;
- derivar a estrutura atual do banco e usar mapeamento estatico apenas para
  anotacoes funcionais seguras.

## Migracoes e saude

Apresentar a tabela `schema_migrations` como controle de versao do schema,
mostrando somente:

- ID da migracao;
- data de aplicacao;
- estado `Aplicada`;
- total de migracoes conhecidas no codigo e total aplicado, quando essa
  comparacao puder ser obtida sem duplicar a lista de migracoes.

Nao executar migracoes a partir da requisicao. A inicializacao normal da
aplicacao continua sendo a unica responsavel por aplica-las.

Para saude, apresentar de modo seguro:

- resultado resumido de `PRAGMA quick_check(1)`;
- quantidade agregada de violacoes encontrada por `PRAGMA foreign_key_check`,
  sem exibir valores de rowid ou conteudo de registros;
- alertas quando `foreign_keys` estiver desabilitado, houver paginas livres em
  proporcao relevante, WAL muito maior que o banco principal, migracao
  conhecida ausente ou metrica indisponivel;
- observacoes como diagnostico, sem oferecer botao de correcao automatica.

O service deve limitar resultados, retornar apenas o primeiro estado necessario
e tratar essas verificacoes como falhas parciais. Nao executar
`PRAGMA integrity_check`, por ser mais custoso para uma pagina de consulta.

## Service de coleta

Criar um service dedicado:

```text
src/services/dataEnvironmentService.js
```

Responsabilidades:

- coletar metadados do filesystem e do SQLite;
- usar a conexao central existente, sem abrir uma segunda conexao gravavel;
- validar e delimitar nomes de arquivos, tabelas, colunas e indices;
- aplicar omissao e agregacao antes de devolver dados ao controller;
- formatar bytes, percentuais, estados e estruturas previsiveis;
- separar dados fisicos, logicos, volumetricos e de saude;
- devolver objetos simples e serializaveis, sem handles do banco, SQL bruto,
  caminhos absolutos ou valores de registros;
- representar falhas parciais como `Indisponivel`, preservando as demais
  secoes;
- nunca executar operacao mutavel durante a coleta.

Reutilizar helpers seguros do ambiente de execucao apenas se isso puder ser
feito por uma extracao pequena e sem criar acoplamento circular. Nao duplicar
regras de formatacao extensas entre services.

## Controller e tratamento de erros

Criar controller dedicado com `async/await` para:

- chamar o service de coleta;
- enviar `Cache-Control: no-store`;
- renderizar a view com `user`, `messages`, dados coletados e estados de
  navegacao;
- registrar no console somente mensagem curta em caso de falha geral;
- redirecionar ou renderizar erro amigavel sem stack trace, SQL, caminho interno
  ou dado coletado.

Erros parciais devem aparecer na propria secao, sem derrubar toda a pagina.

## Arquivos provaveis

```text
app.js
src/routes/dataEnvironmentRoutes.js
src/controllers/dataEnvironmentController.js
src/services/dataEnvironmentService.js
views/data-environment.ejs
views/runtime-environment.ejs
views/partials/environment-navigation.ejs
views/partials/sidebar.ejs
src/config/release.js
```

`src/database/connection.js` e `src/database/schema.js` devem permanecer sem
alteracao, salvo necessidade tecnica real identificada durante a implementacao.
Nao alterar models apenas para expor diagnostico.

Nao alterar `package.json`, `package-lock.json`, `.env`, `.env.example`, arquivos
SQLite, WAL, SHM, backups, JSONs operacionais ou dependencias.

Ao concluir a implementacao, atualizar `src/config/release.js`, incrementando o
numero sequencial em 1 e usando a data/hora atual do ambiente, conforme
`AGENTS.md`.

## Seguranca e privacidade

- A rota nunca pode ser publica.
- Nao criar endpoint JSON adicional nesta task.
- Nao incluir editor SQL, console, exportacao, download, backup, restore,
  vacuum, reindexacao, migracao ou botao de manutencao.
- Nao exibir linhas das tabelas, amostras de dados ou SQL bruto.
- Nao exibir nomes/valores de settings, parametros, outputs, erros, detalhes de
  auditoria, usernames ou credenciais.
- Nao abrir bancos legados ou backups.
- Nao ler conteudo de arquivos JSON operacionais.
- Nao exibir caminhos absolutos, usuario do sistema, ACLs ou informacoes do
  ambiente fora da allowlist da task.
- Nao registrar metadados coletados ou resultados de PRAGMAs no log
  operacional.
- Usar `<%= ... %>` para toda saida dinamica; nao usar `<%- ... %>` para dados
  coletados.
- Nao usar `innerHTML` para inserir valores do diagnostico.
- Validar identificadores antes de qualquer interpolacao inevitavel em PRAGMAs
  ou consultas de metadados.
- Informacao nao classificada explicitamente como publica deve ser omitida.

## Acessibilidade e responsividade

- Manter exatamente um `h1` visivel por pagina.
- A navegacao local deve ser um elemento `nav` com rotulo acessivel.
- O link ativo deve usar `aria-current="page"`.
- Titulos de secoes e cabecalhos de tabela devem ser semanticos.
- `details`/`summary`, se usados, devem ser operaveis por teclado.
- Estados devem ser comunicados por texto, nao apenas por cor ou icone.
- Icones decorativos devem usar `aria-hidden="true"`.
- Tabelas largas devem ficar contidas em wrapper rolavel proprio.
- A pagina deve permanecer utilizavel em desktop e mobile.

## Fora de escopo

- Alterar schema, dados, indices, migrations ou configuracoes SQLite.
- Editar ou executar SQL pela interface.
- Exibir dados individuais ou amostras das tabelas.
- Monitoramento em tempo real, polling ou WebSocket.
- Historico de crescimento entre coletas.
- Alertas externos, envio de email ou integracao com ferramenta de observabilidade.
- Gerenciar backup, restore, WAL, vacuum, reindex ou compactacao.
- Abrir ou migrar bancos legados.
- Criar autorizacao por perfil.
- Adicionar dependencias.
- Atualizar `docs/architecture.md` nesta task, salvo pedido separado.
- Implementar esta task neste momento.

## Criterios de aceite

- Existe uma rota GET autenticada em `/data-environment`.
- Acesso sem sessao segue o fluxo atual de redirecionamento para login.
- As duas paginas exibem os links **Ambiente de execucao** e **Ambiente de
  dados** em uma navegacao local compartilhada.
- O link da pagina atual usa estado visual, texto compreensivel e
  `aria-current="page"`.
- O item **Ambiente** da sidebar permanece ativo nas duas paginas e **Sair**
  continua sendo o ultimo item.
- A nova pagina segue os padroes de EJS, sidebar, rodape e identidade visual do
  PS Panel.
- Tecnologias, arquivos, PRAGMAs, tabelas, colunas, indices, relacionamentos,
  migracoes, volumetria e saude aparecem em secoes identificaveis.
- A versao do SQLite e do driver sao exibidas quando disponiveis.
- Arquivos sao mostrados somente por nomes/caminhos relativos e sem leitura de
  conteudo.
- Banco principal, WAL, SHM, bancos legados e backups sao classificados sem
  alterar ou abrir artefatos fora da conexao principal.
- Tamanho logico, tamanho fisico contabilizado, paginas livres e volumetria por
  tabela possuem rotulos que explicam seu significado.
- Tabelas internas do SQLite nao inflam a contagem principal.
- Colunas e indices refletem os metadados reais do banco.
- Foreign keys declaradas e relacoes apenas logicas sao diferenciadas.
- Agregados funcionais nao revelam registros, nomes de usuarios, scripts,
  parametros, saidas, erros, auditoria ou valores de configuracao.
- Migracoes sao apenas consultadas; nenhuma migracao e executada pela pagina.
- Verificacoes de saude nao executam manutencao nem escrita.
- Falha parcial nao derruba a pagina nem revela stack trace, SQL ou caminho.
- A resposta usa `Cache-Control: no-store`.
- Nao ha overflow horizontal da pagina em desktop ou mobile.
- Nenhum banco, WAL, SHM, backup, JSON operacional, `.env`, manifest ou lockfile
  e alterado.
- O controle de release e atualizado somente ao concluir a implementacao.

## Testes sugeridos

### Validacao sintatica

```powershell
node --check app.js
node --check src\routes\dataEnvironmentRoutes.js
node --check src\controllers\dataEnvironmentController.js
node --check src\services\dataEnvironmentService.js
node --check src\config\release.js
```

Compilar `views/data-environment.ejs`, `views/runtime-environment.ejs` e o novo
partial com EJS para detectar erros de template.

### Validacao do service

- confirmar que o resultado e simples e serializavel;
- confirmar que nenhum caminho e absoluto;
- confirmar que o service nao devolve SQL bruto nem valores de registros;
- confirmar que arquivos JSON, backups e bancos legados nao sao abertos;
- confirmar que `page_size * page_count` e os percentuais usam valores validos;
- confirmar que tabelas internas sao separadas das tabelas de usuario;
- comparar colunas e indices retornados com PRAGMAs controlados;
- simular indisponibilidade de `dbstat` e confirmar degradacao segura;
- simular falha em uma contagem e confirmar que as demais secoes permanecem;
- confirmar que `settings` devolve somente quantidade;
- confirmar que violacoes de foreign key nao devolvem rowid ou conteudo;
- instrumentar a conexao em teste para rejeitar `INSERT`, `UPDATE`, `DELETE`,
  `CREATE`, `ALTER`, `DROP`, `VACUUM`, `REINDEX`, `ATTACH`, `DETACH` e mudancas
  de PRAGMA, comprovando que a coleta e somente leitura;
- nunca imprimir dados reais do banco durante os testes.

### Validacao HTTP local

Usar `PORT=3100` ou a proxima porta livre a partir de `3101`, conforme
`AGENTS.md`:

- confirmar que `/data-environment` sem sessao redireciona para login;
- confirmar resposta `200` com sessao autenticada;
- confirmar `Cache-Control: no-store`;
- confirmar exatamente um `h1` em cada pagina de ambiente;
- confirmar os dois links e o `aria-current` correto em ambas;
- confirmar o estado ativo da sidebar;
- confirmar que o HTML nao contem raiz do workspace, SQL bruto, valores de
  settings, parametros, outputs, usernames ou detalhes de auditoria;
- confirmar que `/runtime-environment` continua funcionando;
- nunca iniciar, reutilizar ou encerrar processo na porta `3000`;
- capturar o PID do servidor temporario e encerrar somente esse processo.

### Validacao visual

- conferir as duas paginas em desktop e viewport mobile;
- validar a navegacao local, foco por teclado e estado ativo;
- conferir hierarquia, espacamentos, cards, badges e tabelas;
- abrir e fechar o detalhamento de tabelas pelo teclado;
- testar nomes tecnicos longos, tabelas com muitas colunas e lista extensa de
  indices;
- confirmar legibilidade e ausencia de overflow horizontal;
- confirmar que estados continuam compreensiveis sem considerar as cores.

## Validacao esperada na implementacao

- Executar `node --check` em todos os arquivos JavaScript alterados.
- Compilar todas as views/partials EJS alterados.
- Executar testes focados do service sem imprimir dados reais.
- Executar `git diff --check`.
- Fazer validacao funcional e visual autenticada quando houver credenciais
  locais ja autorizadas.
- Executar `git status --short` e confirmar que bancos, WAL, SHM, backups,
  arquivos JSON operacionais, `.env`, `package.json` e `package-lock.json` nao
  foram alterados.
- Nao executar `npm test`, pois o projeto ainda nao possui testes reais
  configurados.

---

## Assinatura da LLM

- Data: 17/07/2026 14:28:13
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao
