# TASK-035 - Visualizar log operacional WEB na interface

## Contexto

A aplicacao web do PS Panel ja possui o service `src/services/webLogger.js`, responsavel por espelhar mensagens de `console.log`, `console.info`, `console.warn` e `console.error` em arquivos diarios no diretorio `log/`.

Os arquivos seguem o nome `web-YYYY-MM-DD.log` e registram informacoes operacionais como inicializacao da aplicacao, autenticacao, execucao manual de scripts, saidas do PowerShell e erros do fluxo web. Atualmente, a consulta desses arquivos depende de acesso direto ao servidor.

A `TASK-034` trata da ativacao desse logger no bootstrap principal. Esta task deve partir do comportamento estabelecido por ela e adicionar apenas uma forma segura de consulta pela interface WEB.

## Objetivo

Criar uma tela autenticada para visualizar os arquivos diarios de log operacional WEB, permitindo acompanhar as linhas mais recentes e consultar arquivos anteriores sem expor caminhos arbitrarios do servidor.

## Escopo

- Criar uma tela autenticada em `/logs`.
- Adicionar o item `Logs` ao menu lateral compartilhado.
- Listar todos os arquivos disponiveis com nome no formato `web-YYYY-MM-DD.log`.
- Selecionar inicialmente o arquivo do dia atual ou, se ele nao existir, o arquivo mais recente.
- Exibir as ultimas linhas do arquivo selecionado.
- Atualizar o conteudo automaticamente por polling, com opcao de pausar e atualizar manualmente.
- Permitir filtro textual e filtro visual por nivel `INFO`, `WARN` ou `ERROR` sobre o trecho carregado.
- Implementar leitura limitada do final do arquivo, sem carregar logs grandes integralmente na memoria.
- Proteger a rota com a autenticacao existente.

## Fora de escopo

- Alterar o formato atual dos arquivos de log.
- Registrar ou exibir logs do worker `scripts-js/schedule-worker.js`.
- Consolidar logs de processos diferentes.
- Implementar atualizacao em tempo real com WebSocket ou Server-Sent Events.
- Permitir download, exclusao, edicao, limpeza ou compactacao de logs.
- Criar politica de retencao ou remover arquivos antigos.
- Alterar historico de execucoes ou auditoria de agendamentos no SQLite.
- Criar um novo sistema de papeis ou permissoes.
- Adicionar dependencias externas.

## Arquivos provaveis

- `app.js`
- `src/routes/logRoutes.js`
- `src/controllers/logController.js`
- `src/services/operationalLogService.js`
- `views/logs.ejs`
- `views/partials/sidebar.ejs`

## Situacao atual relevante

- O bootstrap ativo da aplicacao e o `app.js` da raiz.
- `src/services/webLogger.js` grava por padrao em `path.join(process.cwd(), 'log')`.
- O nome do arquivo diario e `web-YYYY-MM-DD.log`.
- Cada linha gerada pelo logger possui timestamp ISO, nivel e mensagem.
- O logger aplica mascaramento basico a nomes e valores associados a `password`, `senha`, `token`, `secret` e `key`.
- O worker de agendamentos nao instala o `webLogger` e permanece fora desta funcionalidade.
- O projeto possui apenas autenticacao de sessao; nao ha atualmente um middleware de autorizacao por perfil.

## Requisitos funcionais

1. Um usuario autenticado deve conseguir acessar `/logs` pelo menu lateral.
2. Um usuario sem sessao deve ser redirecionado para o login.
3. A tela deve listar todos os arquivos validos encontrados no diretorio `log/`, em ordem decrescente de data.
4. O arquivo do dia atual deve ser selecionado inicialmente quando existir.
5. Se o arquivo do dia nao existir, a tela deve selecionar o arquivo mais recente.
6. Se nao houver arquivos, a tela deve apresentar um estado vazio amigavel sem falhar.
7. A consulta deve mostrar por padrao as ultimas 500 linhas.
8. O usuario deve poder escolher entre quantidades predefinidas dentro do intervalo de 50 a 2.000 linhas.
9. A leitura de uma consulta deve ser limitada a no maximo 1 MiB, mesmo que a quantidade solicitada ainda nao tenha sido atingida.
10. Quando o limite de leitura impedir o retorno de todas as linhas solicitadas, a tela deve informar que o conteudo foi truncado.
11. O conteudo deve ser atualizado automaticamente a cada 5 segundos.
12. A tela deve oferecer controles para pausar ou retomar a atualizacao e atualizar imediatamente.
13. A rolagem automatica deve ocorrer apenas quando o usuario estiver no final do conteudo, evitando interromper uma leitura manual.
14. O filtro textual deve atuar somente sobre o trecho atualmente carregado.
15. O filtro por nivel deve permitir visualizar todos os registros ou somente linhas `INFO`, `WARN` ou `ERROR`.
16. A troca de arquivo ou quantidade de linhas deve disparar uma nova consulta.
17. Se um arquivo for removido entre a listagem e a leitura, a tela deve mostrar uma mensagem amigavel e permitir selecionar outro arquivo.

## Interface HTTP esperada

### `GET /logs`

- Renderiza a pagina do visualizador.
- Recebe `user: req.session.user` e `messages: res.locals.messages`.
- Usa `activeMenu: 'logs'` no partial da sidebar.
- Disponibiliza a lista inicial de arquivos validos e o arquivo inicialmente selecionado.

### `GET /logs/content`

Parametros de query:

- `file`: nome simples do arquivo no formato `web-YYYY-MM-DD.log`.
- `lines`: quantidade de linhas solicitada, limitada pelo servidor ao intervalo de 50 a 2.000.

Resposta JSON esperada:

- Nome do arquivo consultado.
- Conteudo textual retornado.
- Quantidade efetiva de linhas.
- Data de ultima alteracao do arquivo.
- Indicador booleano de truncamento.

Erros de entrada devem retornar `400`, arquivo inexistente deve retornar `404` e falhas inesperadas devem retornar `500`, sempre com mensagens amigaveis e sem expor caminhos internos.

## Requisitos tecnicos

- Usar CommonJS (`require` e `module.exports`).
- Usar `async/await` nas rotas, controller e service.
- Resolver o diretorio de log a partir de `process.cwd()`.
- Ler somente a parte final necessaria do arquivo usando `fs`, `stat` e leitura por offset.
- Nao usar `readFile` para carregar integralmente arquivos potencialmente grandes.
- Limitar a leitura a 1 MiB por requisicao.
- Tratar corretamente quebras de linha `CRLF` e `LF`.
- Manter mensagens visiveis em portugues.
- Reaproveitar o estilo global e os padroes visuais das telas autenticadas existentes.
- Nao alterar dependencias ou `package-lock.json`.
- Enviar `Cache-Control: no-store` na pagina e no endpoint de conteudo.

## Requisitos de seguranca

- Proteger `/logs` e `/logs/content` com `isAuthenticated` no `app.js`.
- Aceitar somente o nome base do arquivo, sem diretorios.
- Validar o nome com regra estrita equivalente a `^web-\d{4}-\d{2}-\d{2}\.log$`.
- Rejeitar valores contendo `..`, `/` ou `\`.
- Garantir que o caminho resolvido continue dentro do diretorio `log/`.
- Nao aceitar um caminho absoluto informado pelo cliente.
- Nao devolver o caminho fisico do arquivo nas respostas.
- Renderizar o conteudo do log como texto, usando `textContent` no navegador; nao usar `innerHTML` com o conteudo do arquivo.
- Nao usar `<%- ... %>` para renderizar linhas do log.
- Nao ler, imprimir ou documentar valores reais de `.env`.
- Nao registrar headers, cookies ou dados de sessao no novo fluxo.
- Manter o mascaramento existente do `webLogger`, sem assumir que ele elimina todas as informacoes operacionais sensiveis.

## Sugestao de implementacao

1. Criar um service dedicado para listar arquivos validos e ler o final do arquivo selecionado com limites de linhas e bytes.
2. Criar um controller para renderizar a tela e responder ao endpoint JSON, convertendo erros internos em respostas amigaveis.
3. Criar um router com as rotas `GET /` e `GET /content`, montado em `/logs`.
4. Registrar `/logs` entre as bases protegidas por `isAuthenticated` no `app.js`.
5. Criar `views/logs.ejs` com a sidebar compartilhada, seletores, filtros, controles de atualizacao e area de exibicao monoespacada.
6. No JavaScript da pagina, buscar `/logs/content` a cada 5 segundos enquanto a atualizacao estiver ativa.
7. Aplicar busca e filtro de nivel no navegador sobre o trecho retornado, sempre inserindo as linhas como texto.
8. Adicionar o item `Logs` ao partial da sidebar e destacar o menu quando `activeMenu` for `logs`.

## Pontos de atencao

- O acesso foi definido para todos os usuarios autenticados. Mesmo com mascaramento, o log pode conter nomes, emails, DNs LDAP, caminhos, nomes de scripts e saidas operacionais.
- A listagem deve mostrar todos os arquivos diarios disponiveis, mas nunca aceitar nomes que nao tenham sido validados pelo servidor.
- Um arquivo pode crescer ou ser removido durante a consulta; essas condicoes devem ser tratadas sem derrubar a aplicacao.
- A atualizacao automatica nao deve duplicar timers ao trocar de arquivo, pausar ou retomar.
- Linhas muito longas podem fazer o limite de 1 MiB ser atingido antes da quantidade solicitada; nesse caso, o indicador de truncamento deve ser exibido.
- A funcionalidade nao deve tentar instalar o logger no worker nem mudar o processo de rotacao diaria existente.

## Criterios de aceite

- O menu lateral possui um link `Logs` que abre `/logs`.
- Todas as rotas da funcionalidade exigem sessao autenticada.
- A tela lista somente arquivos `web-YYYY-MM-DD.log` do diretorio `log/`.
- O log atual ou mais recente e selecionado automaticamente.
- As ultimas 500 linhas sao exibidas sem carregar o arquivo inteiro.
- O usuario consegue alterar a quantidade de linhas dentro dos limites permitidos.
- O conteudo e atualizado a cada 5 segundos e pode ser pausado, retomado e atualizado manualmente.
- Busca textual e filtro por nivel funcionam sobre o trecho carregado.
- Conteudo com HTML ou JavaScript aparece como texto e nao e executado pelo navegador.
- Tentativas com `../`, barras, caminhos absolutos ou nomes fora do padrao sao rejeitadas.
- Arquivos vazios, inexistentes, removidos ou maiores que o limite possuem tratamento amigavel.
- Nenhum arquivo de log, `.env`, banco SQLite ou dependencia e alterado pela implementacao.

## Testes sugeridos

- `node --check app.js`
- `node --check src\routes\logRoutes.js`
- `node --check src\controllers\logController.js`
- `node --check src\services\operationalLogService.js`
- Compilar `views/logs.ejs` com EJS para detectar erro de template.
- Acessar `/logs` sem sessao e confirmar o redirecionamento para `/login`.
- Acessar `/logs` autenticado e confirmar a listagem e o arquivo selecionado.
- Testar arquivos vazio, pequeno, grande e removido durante a consulta.
- Testar quantidades abaixo, dentro e acima do intervalo permitido.
- Testar `../`, `%2e%2e`, `/`, `\`, caminho absoluto e nome fora do padrao.
- Inserir em ambiente controlado uma linha contendo tags HTML e confirmar que ela aparece apenas como texto.
- Confirmar pausa, retomada, atualizacao manual, filtros e preservacao da rolagem.
- Confirmar pelo painel de rede do navegador que as respostas usam `Cache-Control: no-store`.

## Validacao esperada

- Validar sintaxe de todos os arquivos JavaScript alterados.
- Validar a compilacao da view EJS.
- Fazer validacao visual e funcional autenticada quando houver servidor disponivel.
- Se a validacao exigir login, usar somente credenciais locais ja autorizadas e nunca registrar ou documentar seus valores.
- Rodar `git status --short` e confirmar que nenhum arquivo do diretorio `log/` foi adicionado ao Git.

---

## Assinatura da LLM

- Data: 2026-07-13
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao
