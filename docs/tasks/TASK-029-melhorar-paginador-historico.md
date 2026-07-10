# TASK-029 - Melhorar paginador do Historico de Execucoes

## Contexto

A tela de Historico de Execucoes (`/history`) lista registros de `script_history` com busca por script, parametros ou usuario.

Hoje o paginador em `views/history.ejs` e bastante simples:

- mostra apenas a pagina atual;
- exibe seta para voltar quando `currentPage > 1`;
- sempre exibe seta para avancar, mesmo quando nao ha proxima pagina;
- nao informa total de paginas nem total de registros;
- nao permite pular diretamente para paginas proximas ou distantes.

Isso dificulta navegar por historicos maiores, especialmente quando ha muitas execucoes ou quando a busca retorna varios resultados.

## Objetivo

Melhorar o paginador da tela `/history`, tornando a navegacao mais flexivel e clara para o usuario.

O usuario deve conseguir entender em qual pagina esta, quantas paginas existem, navegar para paginas proximas e nao ver acoes impossiveis como "proxima pagina" quando ja estiver no fim.

## Escopo

- Melhorar a paginacao da tela `/history`.
- Calcular total de registros e total de paginas para listagem normal e busca.
- Exibir controles de paginacao mais completos na view.
- Preservar o termo de busca durante a navegacao.
- Manter limite atual de 20 itens por pagina, salvo se houver motivo simples para parametrizar.
- Manter textos visiveis em portugues.
- Manter implementacao pequena e localizada.

## Fora de escopo

- Alterar estrutura da tabela `script_history`.
- Criar filtros avancados por periodo, status ou usuario.
- Alterar o modal de detalhes da execucao.
- Refatorar toda a view `views/history.ejs`.
- Criar nova biblioteca de componentes ou paginacao global.
- Alterar execucao de scripts ou registro de historico.
- Modificar dados SQLite em `database/`.

## Arquivos provaveis

```text
src/models/History.js
src/routes/historyRoutes.js
views/history.ejs
```

Possivelmente tambem:

```text
public/styles.css
```

Somente se o estilo do paginador fizer sentido como regra global. Caso contrario, manter CSS local em `views/history.ejs`, seguindo o padrao atual da tela.

## Situacao atual relevante

Rota:

```text
src/routes/historyRoutes.js
router.get('/', isAuthenticated, async (req, res) => { ... })
```

Paginacao atual:

```text
page = parseInt(req.query.page) || 1
limit = 20
offset = (page - 1) * limit
```

Model:

```text
History.getHistory(limit, offset)
History.searchHistory(query, limit, offset)
```

View:

```text
views/history.ejs
```

O paginador atual renderiza:

```text
Anterior, pagina atual, Proxima
```

sem saber se existe proxima pagina.

## Requisitos funcionais

1. A rota `/history` deve calcular o total de registros da consulta atual.
2. O total deve respeitar a busca quando `search` estiver preenchido.
3. A tela deve receber `totalItems` e `totalPages` ou estrutura equivalente.
4. A pagina atual deve ser normalizada:
   - valores ausentes, invalidos ou menores que 1 devem virar pagina 1;
   - valores maiores que o total de paginas devem ser tratados de forma previsivel, preferencialmente usando a ultima pagina disponivel quando houver resultados.
5. O paginador deve ocultar ou desabilitar "Anterior" na primeira pagina.
6. O paginador deve ocultar ou desabilitar "Proxima" na ultima pagina.
7. O paginador deve exibir numeros de pagina proximos da pagina atual.
8. Para muitas paginas, o paginador deve usar reticencias (`...`) para evitar uma lista enorme.
9. O usuario deve conseguir ir para a primeira e a ultima pagina quando houver muitas paginas.
10. O termo de busca deve ser preservado em todos os links do paginador.
11. Quando nao houver resultados, a tela nao deve exibir navegacao inutil.
12. A tabela deve continuar exibindo os mesmos dados e o botao de detalhes deve continuar funcionando.

## Requisitos tecnicos

- Adicionar metodos de contagem em `src/models/History.js`, por exemplo:

```js
static async countHistory()
static async countSearchHistory(query)
```

- Usar placeholders `?` nas queries SQLite.
- Nao concatenar o termo de busca diretamente no SQL.
- Manter a busca parcial atual usando `LIKE ?` em `script_name`, `parameters` e `username`.
- Normalizar `search` com `trim()`.
- Montar links da paginacao usando query string segura, preservando `search`.
- Evitar duplicar regras complexas de URL na view se isso puder ser calculado de forma simples na rota.
- Usar `<%= ... %>` para saida escapada.
- Se criar lista de paginas no backend, passar para a view como array simples, por exemplo:

```js
paginationPages: [1, 'ellipsis', 4, 5, 6, 'ellipsis', 20]
```

- Se criar a lista na view, manter o bloco pequeno e legivel.

## Sugestao de desenho do paginador

Para poucas paginas, exibir todas:

```text
< 1 2 3 4 5 >
```

Para muitas paginas, exibir primeira, ultima e uma janela ao redor da pagina atual:

```text
< 1 ... 8 9 [10] 11 12 ... 30 >
```

Em telas pequenas, os controles devem continuar cabendo sem sobreposicao. Pode usar quebra de linha com `flex-wrap`.

## Sugestao de implementacao

1. Em `History.js`, adicionar metodo para contar todos os registros.
2. Em `History.js`, adicionar metodo para contar registros filtrados pela busca.
3. Em `historyRoutes.js`, normalizar `page` e `search`.
4. Buscar `totalItems` antes de calcular o offset definitivo.
5. Calcular:

```js
const totalPages = Math.max(1, Math.ceil(totalItems / limit));
const currentPage = Math.min(page, totalPages);
const offset = (currentPage - 1) * limit;
```

6. Buscar os registros com `currentPage` ja normalizada.
7. Passar para a view:

```js
currentPage
totalPages
totalItems
limit
search
```

8. Atualizar `views/history.ejs` para renderizar:
   - resumo curto, por exemplo `Pagina X de Y`;
   - links de primeira/anterior/proximas/ultima quando aplicavel;
   - numeros de pagina com estado ativo;
   - reticencias quando houver saltos.
9. Ajustar CSS do paginador para suportar botoes numericos, estado desabilitado e responsividade.

## Criterios de aceite

- `/history` sem busca exibe paginador com total de paginas correto.
- `/history?search=<termo>` exibe paginador baseado apenas nos resultados filtrados.
- A busca permanece preenchida ao navegar entre paginas.
- A pagina atual aparece destacada.
- Na primeira pagina, "Anterior" nao fica clicavel.
- Na ultima pagina, "Proxima" nao fica clicavel.
- Quando ha muitas paginas, o paginador exibe reticencias em vez de todos os numeros.
- Quando ha poucas paginas, todos os numeros sao exibidos.
- Quando nao ha resultados, a tela mostra estado vazio ou tabela vazia sem controles de pagina desnecessarios.
- Links invalidos como `/history?page=-10` ou `/history?page=abc` nao quebram a tela.
- A tabela, badges de status e modal de detalhes continuam funcionando.

## Testes sugeridos

- Abrir `/history` autenticado com historico suficiente para mais de uma pagina.
- Confirmar que pagina 1 mostra pagina atual, total e botao "Proxima".
- Avancar para pagina 2 e confirmar preservacao dos dados.
- Ir para a ultima pagina e confirmar que "Proxima" fica indisponivel.
- Buscar por um termo com muitos resultados e confirmar que a paginacao respeita a busca.
- Buscar por termo sem resultados e confirmar que a tela nao quebra.
- Acessar manualmente:

```text
/history?page=abc
/history?page=-1
/history?page=999999
```

- Confirmar comportamento previsivel e sem erro.
- Redimensionar para largura mobile e confirmar que o paginador nao sobrepoe outros elementos.

## Validacao esperada

Rodar:

```powershell
node --check src\models\History.js
node --check src\routes\historyRoutes.js
```

Como a mudanca envolve view, validar visualmente `/history` com o servidor em execucao quando possivel.

Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
