# TASK-009 - Modularizar modal de renomeacao de script

## Contexto

A tela principal `views/index.ejs` concentra HTML, CSS e JavaScript inline. Com a implementacao do modal amigavel de renomeacao de script, a view passou a receber uma quantidade consideravel de codigo adicional para:

- estilos do modal;
- markup do modal;
- estado e funcoes JavaScript de abertura, fechamento, validacao e envio.

O projeto usa Express, EJS server-side, CSS global em `public/styles.css` e JavaScript simples no navegador. Nao ha build step frontend, bundler ou framework SPA. Portanto, a melhor melhoria arquitetural neste momento e modularizar de forma incremental usando recursos ja suportados pela stack atual.

## Objetivo

Reduzir o tamanho e a responsabilidade de `views/index.ejs` extraindo o modal de renomeacao para arquivos dedicados, sem alterar o comportamento da funcionalidade e sem introduzir novas dependencias.

## Escopo

- Extrair o HTML do modal de renomeacao para um partial EJS.
- Extrair os estilos do modal para um arquivo CSS publico especifico.
- Extrair o JavaScript do fluxo de renomeacao para um arquivo JS publico especifico.
- Atualizar `views/index.ejs` para incluir o partial e carregar os novos assets.
- Preservar o comportamento implementado na task do modal amigavel.

## Fora de escopo

- Migrar a tela para React, Vue, Alpine, HTMX adicional ou qualquer framework novo.
- Adicionar Vite, Webpack, Rollup ou outro bundler.
- Criar um sistema completo de componentes frontend.
- Modularizar todos os scripts inline de `views/index.ejs`.
- Modularizar todos os CSS inline da tela principal.
- Alterar o endpoint `POST /scripts/:scriptName/rename`.
- Alterar regras de validacao do backend.
- Refatorar outras telas como historico, agendamentos ou configuracoes.

## Estrutura sugerida

Criar arquivos seguindo uma organizacao por tela/funcionalidade:

```text
views/
  partials/
    rename-script-modal.ejs

public/
  css/
    index/
      rename-script-modal.css
  js/
    index/
      rename-script-modal.js
```

## Requisitos funcionais

1. O clique no icone de renomear script deve continuar abrindo o modal.
2. O modal deve continuar exibindo o nome atual do script.
3. O campo de novo nome deve continuar iniciando preenchido com o nome atual.
4. O usuario deve continuar podendo cancelar ou fechar o modal sem renomear o arquivo.
5. As validacoes amigaveis do frontend devem continuar funcionando.
6. Erros retornados pelo backend devem continuar aparecendo dentro do modal.
7. O estado de carregamento do botao `Salvar` deve continuar funcionando.
8. Apos renomeacao bem-sucedida, a tela deve continuar sendo atualizada.
9. O clique no botao de renomear deve continuar sem selecionar a linha do script.
10. O icone de visualizar codigo fonte deve continuar funcionando sem regressao.

## Requisitos tecnicos

- Manter `views/index.ejs` como view principal da tela.
- Usar partial EJS com:

```ejs
<%- include('partials/rename-script-modal') %>
```

- Carregar CSS dedicado no `<head>` da tela principal, por exemplo:

```html
<link rel="stylesheet" href="/css/index/rename-script-modal.css">
```

- Carregar JS dedicado ao fim do `body`, depois do HTML do modal e antes ou depois do script inline atual conforme dependencia real, por exemplo:

```html
<script src="/js/index/rename-script-modal.js"></script>
```

- Manter os nomes globais chamados pelo HTML existente, especialmente:
  - `renameScript(event, button)`;
  - `handleRenameModalBackdrop(event)`;
  - `closeRenameScriptModal()`;
  - `submitRenameScript(event)`.
- Evitar `type="module"` para manter compatibilidade simples com o padrao atual.
- Nao introduzir ESM, import/export ou dependencias externas.
- Garantir que o JS externo nao dependa de variaveis locais do script inline de `index.ejs`.
- Se possivel, encapsular estado interno em uma IIFE e expor no `window` apenas as funcoes chamadas pelo HTML.
- Preservar IDs e classes usados pelo modal:
  - `renameScriptModal`;
  - `renameScriptInput`;
  - `renameCurrentName`;
  - `renameScriptError`;
  - `renameSubmitBtn`;
  - `.rename-modal`;
  - `.rename-dialog`;
  - `.rename-error`.

## Sugestao de implementacao

- Mover o bloco de HTML do modal de `views/index.ejs` para `views/partials/rename-script-modal.ejs`.
- Mover todo o CSS iniciado em `.rename-modal` e relacionado ao modal para `public/css/index/rename-script-modal.css`.
- Mover o estado e as funcoes relacionadas ao renomear script para `public/js/index/rename-script-modal.js`, incluindo:
  - `renameScriptState`;
  - `renameScript`;
  - `openRenameScriptModal`;
  - `closeRenameScriptModal`;
  - `handleRenameModalBackdrop`;
  - `submitRenameScript`;
  - `showRenameScriptError`;
  - `getRenameScriptValidationError`;
  - `setRenameScriptLoading`;
  - listener de `Escape`, se ele for exclusivo do modal.
- No arquivo JS externo, expor apenas as funcoes usadas por atributos inline:

```js
(function () {
    const state = {
        currentName: '',
        renameUrl: '',
        triggerButton: null,
        isLoading: false
    };

    function renameScript(event, button) {
        // ...
    }

    window.renameScript = renameScript;
    window.closeRenameScriptModal = closeRenameScriptModal;
    window.handleRenameModalBackdrop = handleRenameModalBackdrop;
    window.submitRenameScript = submitRenameScript;
})();
```

- Remover de `views/index.ejs` apenas o codigo extraido, evitando limpar ou reorganizar trechos nao relacionados.

## Criterios de aceite

- `views/index.ejs` passa a carregar o CSS e JS dedicados do modal.
- `views/index.ejs` passa a incluir o partial do modal.
- O CSS do modal nao fica mais inline em `views/index.ejs`.
- O JavaScript de renomeacao nao fica mais inline em `views/index.ejs`.
- O comportamento visual e funcional do modal permanece igual ao atual.
- Nenhuma dependencia nova e adicionada ao projeto.
- Nenhum arquivo de backend e alterado sem necessidade.
- A tela principal continua funcionando com assets estaticos servidos pelo Express.

## Testes sugeridos

- Abrir a tela principal autenticado.
- Confirmar no navegador que os arquivos abaixo carregam sem 404:
  - `/css/index/rename-script-modal.css`;
  - `/js/index/rename-script-modal.js`.
- Clicar no icone de renomear um script e confirmar que o modal abre.
- Confirmar que o campo vem preenchido com o nome atual.
- Salvar com campo vazio e confirmar erro amigavel no modal.
- Salvar com o mesmo nome e confirmar erro amigavel no modal.
- Informar `Teste.txt` e confirmar que aparece erro amigavel de extensao.
- Informar `../Teste.ps1` e confirmar que aparece erro amigavel de caminho.
- Cancelar e fechar o modal confirmando que nada e renomeado.
- Renomear um script valido e confirmar que a pagina recarrega com o novo nome.
- Confirmar que visualizar codigo fonte continua funcionando.

## Validacao esperada

- Rodar verificacao de sintaxe do novo JavaScript:

```powershell
node --check public\js\index\rename-script-modal.js
```

- Como a alteracao envolve EJS/CSS/JS no navegador, validar visualmente a tela principal com o servidor em execucao quando possivel.
- Nao e necessario rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
