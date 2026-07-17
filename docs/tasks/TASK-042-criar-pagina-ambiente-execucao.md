# TASK-042 - Criar pagina de ambiente de execucao

## Contexto

O PS Panel possui telas autenticadas para scripts, agendamentos, historico,
logs operacionais e configuracoes, mas ainda nao oferece uma visao consolidada
do ambiente em que o processo WEB esta sendo executado.

Em atividades de suporte, diagnostico e validacao de uma instalacao local,
atualmente e necessario consultar o terminal ou inspecionar arquivos
separadamente para identificar a release da aplicacao, a plataforma, a versao
do Node.js, as dependencias diretas e o estado das configuracoes relevantes.

Esta task propoe uma pagina interna, autenticada e somente leitura que reuna
essas informacoes sem expor senhas, tokens, conteudo do `.env`, caminhos
absolutos, dados de sessao ou outros segredos.

## Objetivo

Criar a pagina **Ambiente de execucao** para apresentar, de forma organizada e
segura:

- identificacao e release atual do PS Panel;
- sistema operacional e arquitetura;
- runtime Node.js e processo WEB atual;
- dependencias diretas declaradas e resolvidas;
- modulos carregados pelo processo;
- estado seguro das variaveis de ambiente conhecidas;
- configuracoes tecnicas uteis para diagnostico.

Adicionar o item **Ambiente** ao rodape do menu lateral compartilhado,
imediatamente acima de **Sair**.

## Importante

Esta task deve ser apenas preparada neste momento. Nao implementar
automaticamente sem nova solicitacao ou confirmacao do usuario.

## Decisoes de produto

- A pagina e uma ferramenta de diagnostico tecnico, nao uma tela de edicao.
- A rota deve ser autenticada com o middleware existente.
- Todos os usuarios autenticados terao o mesmo acesso, pois o projeto ainda nao
  possui autorizacao por perfil.
- Nenhuma acao da pagina deve alterar `process.env`, dependencias, arquivos,
  bancos SQLite ou qualquer outro estado da aplicacao.
- As informacoes devem refletir o processo WEB que atendeu a requisicao, nao o
  worker de agendamentos nem outros processos Node.js.
- Dados potencialmente sensiveis devem ser omitidos ou mascarados no servidor,
  antes da renderizacao.
- A pagina nao deve ler nem exibir o conteudo bruto do arquivo `.env`.
- A implementacao deve usar recursos nativos do Node.js e estruturas ja
  existentes no projeto, sem novas dependencias.

## Rota e navegacao

Criar uma rota GET protegida:

```text
GET /runtime-environment
```

Requisitos:

- registrar a base `/runtime-environment` na lista protegida por
  `isAuthenticated` do `app.js` da raiz;
- montar um router dedicado na mesma base;
- adicionar **Ambiente** no `sidebar-footer` de
  `views/partials/sidebar.ejs`, imediatamente acima do link **Sair**;
- manter as informacoes do usuario acima do novo item;
- manter **Sair** como o ultimo item da sidebar;
- preservar a ordem atual dos itens da navegacao principal, inclusive
  **Logs** e **Configuracoes**;
- usar `activeMenu: 'runtime-environment'` para destacar o item ativo;
- usar um icone Font Awesome coerente com os icones ja utilizados pela sidebar;
- nao criar uma segunda navegacao nem alterar o layout global.

## Organizacao visual

Criar uma view EJS autenticada, seguindo as telas atuais do PS Panel:

- idioma `pt-BR`;
- sidebar por `views/partials/sidebar.ejs`, recebendo `user` e `activeMenu`;
- `main.main-content`;
- exatamente um `h1` visivel com o titulo `Ambiente de execucao`;
- subtitulo curto, por exemplo `Informacoes do processo atual para suporte e diagnostico.`;
- alerts por `messages: res.locals.messages` quando aplicavel;
- rodape compartilhado existente, preservando a exibicao da release;
- estilos globais de `/styles.css` e CSS localizado na view somente quando
  necessario.

Separar o conteudo em secoes ou paineis responsivos:

1. **Aplicacao**;
2. **Sistema operacional**;
3. **Node.js e processo**;
4. **Dependencias diretas**;
5. **Modulos carregados**;
6. **Variaveis de ambiente**;
7. **Configuracoes uteis**.

Diretrizes visuais:

- destacar release, versao do Node.js, plataforma, arquitetura e tempo de
  atividade em cards compactos de resumo;
- usar paineis com titulo e descricao curta para agrupar informacoes;
- usar tabelas compactas para dependencias, modulos e variaveis;
- usar badges textuais para estados como `Resolvido`, `Nao resolvido`,
  `Configurada`, `Nao configurada`, `Mascarado` e `Indisponivel`;
- combinar cor com texto, sem depender apenas de cor para transmitir estado;
- usar fonte monoespacada somente para valores tecnicos que se beneficiem dela;
- conter valores longos e tabelas sem causar overflow horizontal da pagina;
- manter boa legibilidade em desktop e mobile;
- nao redesenhar a sidebar, o rodape ou a identidade visual global.

## Informacoes da aplicacao

Exibir, no minimo:

- nome do pacote a partir de `package.json`;
- versao registrada em `package.json`;
- `label` exportado por `src/config/release.js`;
- ambiente logico, limitado ao valor seguro de `NODE_ENV`;
- instante em que os dados foram coletados, em formato previsivel e exibido em
  `pt-BR`.

Nao duplicar a release em uma nova constante nem inferir versao diferente da
registrada no projeto.

## Sistema operacional

Usar o modulo nativo `os` e propriedades seguras do processo para apresentar:

- plataforma;
- tipo e release do sistema operacional;
- arquitetura;
- quantidade de CPUs disponiveis;
- memoria total e livre, em unidade legivel.

Nao executar comandos PowerShell ou outros comandos de shell. Nao exibir:

- hostname;
- nome do usuario do sistema;
- diretorio pessoal;
- interfaces de rede;
- enderecos IP ou MAC;
- identificadores exclusivos da maquina.

## Node.js e processo

Exibir informacoes nao secretas do processo WEB atual:

- `process.version`;
- versoes relevantes e explicitamente selecionadas de `process.versions`;
- arquitetura e plataforma do processo;
- PID;
- tempo de atividade do processo;
- uso resumido de memoria, com valores formatados.

Nao exibir `process.argv`, `process.execArgv`, `process.execPath`, `process.cwd()`
ou qualquer caminho absoluto. Esses dados possuem baixo beneficio para a tela e
podem conter argumentos ou informacoes locais sensiveis.

## Dependencias diretas

Considerar como dependencias diretas os itens declarados em `dependencies` e,
se existirem, `optionalDependencies` de `package.json`. As `devDependencies`
podem ser apresentadas em grupo separado somente quando `NODE_ENV` for
`development`, sem alterar o criterio das dependencias de runtime.

Para cada dependencia, apresentar:

- nome;
- tipo (`Runtime`, `Opcional` ou `Desenvolvimento`);
- faixa de versao declarada;
- versao efetivamente resolvida quando puder ser obtida com seguranca;
- estado `Resolvido`, `Nao resolvido` ou `Opcional ausente`.

Regras:

- nao varrer `node_modules` recursivamente;
- nao listar dependencias transitivas como diretas;
- nao executar `npm list` durante a requisicao;
- nao instalar, atualizar ou remover pacotes;
- nao expor o caminho fisico de nenhum pacote;
- tratar falha de resolucao individual sem derrubar a pagina;
- ler apenas manifests conhecidos e necessarios para obter a versao resolvida.

## Modulos carregados

Apresentar um retrato sanitizado de `require.cache` no instante da requisicao,
distinguindo:

- modulos internos do PS Panel;
- pacotes externos carregados.

Requisitos:

- normalizar e deduplicar a lista;
- representar modulos internos somente por caminho relativo seguro a raiz do
  projeto, como `src/services/authService.js`;
- representar pacotes externos somente pelo nome do pacote, preservando o
  escopo quando aplicavel;
- excluir qualquer entrada que nao possa ser convertida com seguranca;
- nunca enviar chaves brutas de `require.cache`, caminhos absolutos, nome do
  usuario do sistema ou a arvore de `node_modules` para a view;
- informar na interface que a lista contem apenas os modulos carregados naquele
  processo ate o instante da coleta, e nao todos os modulos instalados.

## Variaveis de ambiente

Usar uma allowlist explicita baseada nas chaves conhecidas e documentadas pelo
PS Panel. Nunca enumerar livremente `process.env`.

Allowlist inicial:

```text
PORT
NODE_ENV
SESSION_SECRET
ADMIN_USER
ADMIN_PASSWORD
ADMIN_PASSWORD_HASH
LDAP_URL
LDAP_BIND_DN
LDAP_BIND_PASSWORD
LDAP_SEARCH_BASE
LDAP_SEARCH_FILTER
```

Para cada chave permitida, apresentar somente:

- nome da variavel;
- estado `Configurada` ou `Nao configurada`;
- valor apenas para `PORT` e `NODE_ENV`, depois de validacao e normalizacao;
- estado `Mascarado`, sem valor, para todas as demais chaves configuradas.

Requisitos obrigatorios:

- qualquer chave cujo nome indique senha, token, segredo, hash, chave, cookie,
  sessao, autorizacao ou credencial deve ser mascarada mesmo se for adicionada a
  allowlist no futuro;
- valores de LDAP, inclusive URL, bind DN, base e filtro, nao devem chegar ao
  HTML, pois podem revelar infraestrutura e estrutura organizacional;
- nao listar variaveis desconhecidas herdadas do sistema operacional;
- nao abrir, analisar ou devolver o arquivo `.env`;
- nao enviar valores sensiveis ao HTML, comentarios, atributos `data-*`, logs
  ou respostas auxiliares;
- aplicar allowlist e mascaramento no service de coleta, nao apenas na view;
- renderizar nomes, rotulos e valores publicos com saida escapada do EJS
  (`<%= ... %>`).

## Configuracoes uteis

Consultar apenas configuracoes previamente classificadas como seguras e
apresentar, no minimo:

- tempo maximo de execucao de scripts, a partir de
  `scripts.max_execution_time`;
- escala de fonte da interface, a partir de `ui.font_scale`;
- status do resumo diario por email (`Habilitado` ou `Desabilitado`);
- status do destinatario do resumo (`Configurado` ou `Nao configurado`), sem
  exibir o endereco;
- ultimo envio registrado do resumo diario, quando houver;
- persistencia como `SQLite local`, sem caminho do banco;
- diretorio de scripts como `scripts-ps/`, somente em formato relativo;
- diretorio de logs como `log/`, somente em formato relativo.

Se a implementacao consultar a configuracao SMTP, deve exibir somente um estado
agregado como `Configurado`, `Incompleto` ou `Nao configurado`. Host, porta,
usuario, remetente, senha e demais valores nao devem ser enviados a view.

Nao realizar teste de rede, bind LDAP, envio de email, escrita em disco ou
consulta mutavel para preencher essa secao.

## Service de coleta

Criar um service dedicado:

```text
src/services/runtimeEnvironmentService.js
```

Responsabilidades:

- coletar e normalizar os dados tecnicos;
- aplicar allowlist, omissao e mascaramento antes de devolver os dados;
- formatar bytes, duracoes e estados em estruturas previsiveis;
- resolver versoes de dependencias com tratamento de erro por item;
- transformar caminhos de modulos em identificadores relativos seguros;
- consultar apenas configuracoes classificadas como seguras;
- devolver objetos simples, sem HTML, sem caminhos absolutos e sem referencias
  mutaveis a `process` ou `require.cache`;
- representar falhas parciais com estado seguro, sem impedir a exibicao das
  demais secoes.

A view deve somente organizar e escapar os dados recebidos. Regras de seguranca
nao devem ficar espalhadas no controller, no `app.js` ou depender de CSS ou
JavaScript do navegador.

## Controller e tratamento de erros

Criar um controller dedicado com `async/await` para:

- chamar o service de coleta;
- enviar `Cache-Control: no-store`;
- renderizar `runtime-environment.ejs` com `user`, `messages`, dados coletados e
  `activeMenu` quando necessario;
- registrar no console somente uma mensagem curta em caso de falha geral, sem
  incluir dados coletados, `process.env` ou objetos potencialmente sensiveis;
- renderizar uma mensagem amigavel ou redirecionar com flash quando a pagina
  nao puder ser carregada.

Erros parciais devem aparecer como `Indisponivel`, sem stack trace, caminho
interno ou valor bruto na interface.

## Arquivos provaveis

```text
app.js
src/routes/runtimeEnvironmentRoutes.js
src/controllers/runtimeEnvironmentController.js
src/services/runtimeEnvironmentService.js
views/runtime-environment.ejs
views/partials/sidebar.ejs
src/config/release.js
```

Alterar `public/styles.css` somente se um ajuste pequeno e reutilizavel for
realmente necessario. Preferir CSS localizado na nova view, conforme o padrao
atual das telas especificas.

Nao alterar `package.json`, `package-lock.json`, `.env`, `.env.example`, bancos
SQLite ou dependencias para implementar esta task.

Ao concluir a implementacao, atualizar `src/config/release.js`, incrementando o
numero sequencial em 1 e usando a data/hora atual do ambiente, conforme
`AGENTS.md`.

## Seguranca e privacidade

- A rota nunca pode ser publica.
- Nao criar endpoint JSON adicional nesta task.
- Nao incluir botao para copiar tudo, exportar ou baixar diagnostico.
- Nao exibir conteudo do `.env`, `process.env` completo ou dump de objetos do
  processo.
- Nao exibir senhas, hashes, tokens, cookies, ID de sessao, headers, URLs de
  infraestrutura, DNs, filtros LDAP ou credenciais.
- Nao exibir caminhos absolutos, hostname, usuario do sistema, IP ou MAC.
- Nao registrar os dados coletados no log operacional.
- Nao usar `<%- ... %>` para dados dinamicos da pagina.
- Nao usar `innerHTML` no navegador para inserir valores coletados.
- Aplicar negacao segura: informacao nao classificada explicitamente como
  publica deve ser omitida.
- Uma falha de coleta deve gerar mensagem curta em portugues, sem stack trace
  ou caminho interno na interface.

## Acessibilidade e responsividade

- Manter exatamente um `h1` visivel.
- Usar titulos semanticos para cada secao.
- Tabelas devem ter cabecalhos de coluna claros.
- Estados devem ser comunicados por texto, nao apenas por cor ou icone.
- Icones decorativos devem usar `aria-hidden="true"`.
- Conteudo longo deve quebrar ou ficar contido em um wrapper rolavel proprio,
  sem causar overflow horizontal da pagina.
- A pagina deve permanecer utilizavel em desktop e mobile.
- Badges e textos devem manter contraste legivel.

## Fora de escopo

- Editar variaveis de ambiente ou configuracoes pela pagina.
- Instalar, atualizar ou remover modulos.
- Exibir todas as dependencias transitivas.
- Executar comandos de sistema, PowerShell ou scripts de diagnostico.
- Testar conectividade LDAP, SMTP ou qualquer servico externo.
- Ler o conteudo de logs, scripts, `.env` ou bancos SQLite para diagnostico.
- Expor metricas continuamente ou atualizar a pagina em tempo real.
- Criar endpoint publico, API JSON, download ou relatorio de diagnostico.
- Criar controle de acesso por funcao ou perfil.
- Alterar models, schema ou dados persistidos.
- Adicionar dependencias.
- Incluir informacoes do worker `scripts-js/schedule-worker.js`.
- Implementar esta task neste momento.

## Criterios de aceite

- Existe uma rota GET autenticada em `/runtime-environment`.
- Um acesso sem sessao segue o fluxo atual de redirecionamento para login.
- O item **Ambiente** aparece no rodape da sidebar, imediatamente acima de
  **Sair** e abaixo das informacoes do usuario.
- **Sair** permanece como o ultimo item da sidebar.
- O item ativo e identificado corretamente ao abrir a pagina.
- A pagina segue os padroes de EJS, sidebar, rodape e identidade visual do PS
  Panel.
- A apresentacao possui hierarquia clara, cards compactos, paineis organizados,
  badges textuais e tabelas legiveis.
- Aplicacao, sistema operacional, Node.js, processo, dependencias, modulos,
  variaveis e configuracoes aparecem em secoes identificaveis.
- A release exibida vem de `src/config/release.js`.
- Dependencias diretas mostram versao declarada e resolvida quando disponivel,
  sem varrer `node_modules` ou executar `npm list`.
- Modulos carregados sao deduplicados e nao expoem caminhos absolutos.
- A interface explica a diferenca entre dependencia declarada e modulo
  carregado.
- Variaveis sao limitadas a allowlist e valores sensiveis nunca chegam ao HTML.
- Nenhum conteudo do `.env` e lido ou exibido pela pagina.
- Configuracoes de email mostram apenas estados seguros, sem destinatario ou
  credenciais.
- Hostname, usuario do sistema, diretorio pessoal, IP, MAC, argumentos e
  caminhos absolutos nao sao expostos.
- Falha parcial de coleta nao derruba a pagina nem revela stack trace.
- A pagina e somente leitura e nao causa efeitos colaterais.
- Nao ha overflow horizontal da pagina em desktop ou mobile.
- Mensagens e rotulos permanecem em portugues.
- Nenhuma dependencia, banco, `.env` ou arquivo operacional e alterado.
- O controle de release e atualizado somente ao concluir a implementacao.

## Testes sugeridos

### Validacao sintatica

```powershell
node --check app.js
node --check src\routes\runtimeEnvironmentRoutes.js
node --check src\controllers\runtimeEnvironmentController.js
node --check src\services\runtimeEnvironmentService.js
node --check src\config\release.js
```

Compilar `views/runtime-environment.ejs` com EJS para detectar erro de template
sem iniciar a aplicacao.

### Validacao do service

- confirmar que a coleta retorna objetos simples e serializaveis;
- definir, em processo de teste isolado, valores ficticios para chaves contendo
  `PASSWORD`, `TOKEN`, `SECRET`, `HASH`, `KEY`, `COOKIE`, `SESSION` e `AUTH` e
  confirmar que nenhum valor aparece no resultado;
- definir uma variavel desconhecida ficticia e confirmar que seu nome e valor
  nao aparecem;
- confirmar que valores de LDAP nunca sao devolvidos;
- confirmar que modulos carregados nao contem raiz do workspace, diretorio do
  usuario ou trechos fisicos de `node_modules`;
- simular falha ao resolver uma dependencia e confirmar o estado seguro;
- confirmar que nenhuma funcao de coleta altera `process.env`, arquivos ou
  configuracoes persistidas.

Nunca imprimir valores reais do ambiente durante os testes.

### Validacao HTTP local

Usar `PORT=3100` ou a proxima porta livre a partir de `3101`, conforme
`AGENTS.md`:

- confirmar que `/runtime-environment` sem sessao redireciona para o login;
- confirmar que `/runtime-environment` autenticado responde `200`;
- confirmar que a resposta usa `Cache-Control: no-store`;
- confirmar que o HTML possui exatamente um `h1`;
- confirmar o item ativo da sidebar;
- confirmar que o HTML nao contem segredos ficticios, caminhos absolutos,
  hostname, dump de `process.env` ou chaves desconhecidas;
- confirmar que `/`, `/history`, `/logs` e `/settings` continuam funcionando;
- nunca iniciar, reutilizar ou encerrar processo na porta `3000`;
- capturar o PID do servidor temporario e encerrar somente esse processo.

### Validacao visual

- conferir a pagina em desktop e viewport mobile;
- verificar que o novo item fica imediatamente acima de **Sair**, tanto na
  apresentacao desktop quanto na responsiva;
- confirmar que **Sair** permanece como o ultimo item da sidebar;
- conferir hierarquia, espacamentos, alinhamento, badges e uso moderado de
  cores;
- validar que os estados continuam compreensiveis sem considerar as cores;
- testar listas curtas e longas de dependencias e modulos;
- confirmar legibilidade das tabelas e ausencia de overflow horizontal.

## Validacao esperada na implementacao

- Executar `node --check` em todos os arquivos JavaScript alterados.
- Compilar a nova view EJS.
- Executar `git diff --check`.
- Fazer validacao funcional e visual autenticada quando houver credenciais
  locais ja autorizadas, sem imprimir ou documentar seus valores.
- Executar `git status --short` e confirmar que `.env`, bancos SQLite, logs,
  `package.json` e `package-lock.json` nao foram alterados pela funcionalidade.

---

## Assinatura da LLM

- Data: 17/07/2026 13:10:57
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: criacao

---

## Assinatura da LLM

- Data: 17/07/2026 13:15:39
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

## Implementacao

- Foi criado `src/services/runtimeEnvironmentService.js` para coletar e
  sanitizar dados da aplicacao, sistema operacional, processo, dependencias
  diretas, cache CommonJS, variaveis permitidas e configuracoes seguras.
- Foram criados o controller, o router e a view EJS da rota autenticada
  `GET /runtime-environment`.
- O item **Ambiente** foi adicionado ao rodape da sidebar, imediatamente acima
  de **Sair**, com estado ativo e comportamento responsivo.
- A pagina utiliza cards de resumo, paineis, tabelas, badges textuais e nomes de
  modulos sanitizados, sem expor caminhos absolutos.
- Variaveis desconhecidas nao sao enumeradas; valores sensiveis e informacoes
  LDAP sao omitidos no service antes da renderizacao.
- O release foi atualizado para `Release 17/07/2026 13:24 - 026`.
- As verificacoes `node --check` dos JavaScript alterados, compilacao EJS,
  teste isolado de sanitizacao e `git diff --check` foram executadas.
- Na validacao HTTP pela porta 3100, a rota sem sessao respondeu `302`, a rota
  autenticada respondeu `200` com `Cache-Control: no-store`, e `/`, `/history`,
  `/logs` e `/settings` continuaram respondendo `200`.
- O HTML validado possui exatamente um `h1`, item ativo correto e ausencia dos
  segredos ficticios e do caminho absoluto do workspace.
- A pagina foi validada visualmente em desktop e em viewport mobile de 390 por
  844, sem overflow horizontal e com **Ambiente** acima de **Sair**.
- A instancia temporaria foi encerrada pelo PID confirmado e seus arquivos de
  saida temporarios foram removidos.

---

## Assinatura da LLM

- Data: 17/07/2026 13:30:00
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao

## Ajuste visual do rodape da sidebar

- As informacoes do usuario foram reorganizadas em um cartao de sessao com
  avatar, indicador de status e hierarquia visual propria.
- As acoes **Ambiente** e **Sair** passaram a usar blocos compactos com icones,
  subtitulos e cores discretas distintas do menu principal.
- O modo responsivo preserva somente os icones das acoes e oculta o cartao de
  sessao, mantendo **Sair** como o ultimo item.
- O release foi atualizado para `Release 17/07/2026 13:40 - 027`.

---

## Assinatura da LLM

- Data: 17/07/2026 13:40:52
- Modelo: GPT-5 Codex
- Versao: nao informado
- Acao: atualizacao
