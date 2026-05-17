# Task: Visualizar codigo fonte do script PowerShell em popup

## Contexto

A tela principal do sistema lista os scripts PowerShell disponiveis para execucao a partir da pasta `scripts-ps`. Atualmente, o usuario consegue selecionar um script e executa-lo, mas nao ha uma acao direta para consultar o codigo fonte do arquivo antes da execucao.

## Objetivo

Adicionar uma funcionalidade na lista de scripts da tela principal para permitir que o usuario visualize o codigo fonte de um script PowerShell em uma nova janela popup.

## Escopo

- Incluir uma acao de visualizacao de codigo fonte em cada item da lista de scripts da tela principal.
- Abrir o codigo fonte em uma nova janela popup, separada da tela principal.
- Exibir o conteudo completo do arquivo `.ps1` selecionado.
- Manter a funcionalidade atual de selecionar e executar scripts sem regressao.
- Restringir a leitura apenas a arquivos `.ps1` existentes dentro da pasta `scripts-ps`.

## Fora de escopo

- Edicao do codigo fonte do script.
- Download do arquivo `.ps1`.
- Destaque de sintaxe avancado, salvo se for simples de aplicar sem ampliar muito o escopo.
- Visualizacao de scripts fora da pasta `scripts-ps`.

## Requisitos funcionais

1. Na tabela/lista de scripts da tela principal, cada script deve ter uma acao visivel para abrir seu codigo fonte.
2. Ao clicar na acao, o sistema deve abrir uma nova janela popup.
3. A popup deve exibir:
   - nome do script;
   - conteudo do arquivo em area monoespacada;
   - indicacao amigavel caso o arquivo nao possa ser lido.
4. O usuario deve conseguir fechar a popup usando os controles nativos da janela.
5. A acao de visualizar codigo nao deve disparar a selecao ou execucao do script.

## Requisitos tecnicos

- Criar uma rota autenticada para leitura do codigo fonte do script, por exemplo:

```text
GET /scripts/:scriptName/source
```

- A rota deve validar o nome do arquivo recebido:
  - aceitar somente arquivos com extensao `.ps1`;
  - bloquear `..`, barras, contrabarras ou qualquer tentativa de path traversal;
  - confirmar que o arquivo resolvido permanece dentro de `scripts-ps`.
- Ler o arquivo como texto, preferencialmente em `utf8`.
- Escapar o conteudo renderizado na view para evitar injecao de HTML.
- Reaproveitar os padroes existentes em `src/routes/mainRoutes.js` e `views/index.ejs`.
- A rota deve estar protegida pelo middleware de autenticacao, assim como a tela principal.

## Sugestao de implementacao

- Backend:
  - adicionar uma rota `GET` em `src/routes/mainRoutes.js`;
  - criar uma pequena funcao auxiliar para validar nomes de scripts, se ainda nao houver uma adequada para reutilizar;
  - renderizar uma view EJS dedicada, por exemplo `views/script-source-popup.ejs`.

- Frontend:
  - adicionar um botao/icone de visualizacao em cada linha da tabela de scripts em `views/index.ejs`;
  - usar `window.open()` para abrir a popup com dimensoes adequadas;
  - impedir a propagacao do clique do botao para nao selecionar a linha automaticamente.

Exemplo de comportamento esperado no clique:

```js
window.open('/scripts/NomeDoScript.ps1/source', 'scriptSource', 'width=1000,height=700,scrollbars=yes,resizable=yes');
```

## Criterios de aceite

- A tela principal exibe uma acao para visualizar o codigo fonte em cada script listado.
- Ao clicar na acao, uma nova janela popup e aberta com o codigo fonte do script selecionado.
- Scripts com nomes invalidos ou inexistentes nao sao lidos e retornam erro adequado.
- A rota nao permite acessar arquivos fora de `scripts-ps`.
- O conteudo do script e exibido como texto, sem ser interpretado como HTML.
- A selecao e execucao de scripts continuam funcionando como antes.

## Testes sugeridos

- Abrir a tela principal autenticado e clicar na acao de visualizar codigo de um script valido.
- Confirmar que a popup mostra o nome e o conteudo completo do `.ps1`.
- Confirmar que clicar no botao de visualizar nao seleciona nem executa o script.
- Testar acesso manual a nomes invalidos, como:

```text
/scripts/../.env/source
/scripts/test.txt/source
/scripts/subpasta/script.ps1/source
```

- Confirmar que esses acessos sao bloqueados.
