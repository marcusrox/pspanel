# TASK-008 - Modal amigavel para renomear script

## Contexto

Na tela principal do sistema, `Painel de Scripts`, cada linha da listagem de scripts possui um icone para alterar o nome do arquivo PowerShell.

Atualmente, o clique nesse icone chama a funcao `renameScript(event, button)` em `views/index.ejs`, que usa `prompt('Novo nome do script:', currentName)` para solicitar o novo nome. Em caso de erro no `fetch`, a mesma funcao usa `alert(...)` para avisar o usuario.

A base de codigo nao possui uma biblioteca especifica para dialogs amigaveis, como SweetAlert. O padrao mais proximo existente e um modal simples implementado diretamente em EJS/CSS/JS em `views/history.ejs`, usado para exibir detalhes do historico.

## Objetivo

Substituir o `prompt()` de renomeacao de script por um modal visualmente integrado ao PS Panel, mantendo o fluxo atual de renomear arquivos dentro de `scripts-ps`.

## Escopo

- Criar um modal na tela principal (`views/index.ejs`) para informar o novo nome do script.
- Preencher o campo do modal com o nome atual do script.
- Permitir confirmar ou cancelar a renomeacao.
- Exibir mensagens de validacao e erro dentro do modal, sem usar `alert()` para esse fluxo.
- Manter o endpoint atual `POST /scripts/:scriptName/rename` em `src/routes/mainRoutes.js`.
- Manter a listagem atualizada apos renomeacao bem-sucedida.

## Fora de escopo

- Trocar o padrao visual global do projeto.
- Adicionar biblioteca nova de modal, toast ou alert.
- Criar um componente compartilhado para todas as telas.
- Alterar a regra de backend para renomear scripts.
- Alterar historico, agendamentos ou referencias antigas ao nome do script.
- Substituir todos os `alert()` ou `confirm()` existentes no sistema.

## Requisitos funcionais

1. Ao clicar no icone de renomear script na tela principal, deve abrir um modal em vez de um `prompt()` do navegador.
2. O modal deve mostrar o nome atual do script e um campo editavel com o novo nome.
3. O campo deve iniciar preenchido com o nome atual.
4. O usuario deve conseguir cancelar a operacao sem alterar o arquivo.
5. Pressionar o botao de confirmar deve enviar o novo nome para a rota atual de renomeacao.
6. Se o nome estiver vazio ou igual ao atual, o modal deve exibir uma mensagem amigavel sem enviar a requisicao.
7. Se o backend retornar erro, a mensagem retornada em JSON deve aparecer no modal.
8. Enquanto a requisicao estiver em andamento, o botao de confirmar deve ficar desabilitado e indicar carregamento.
9. Apos sucesso, a tela deve refletir o novo nome, podendo recarregar a pagina como ocorre hoje.
10. O clique no icone de renomear deve continuar sem selecionar a linha do script.

## Requisitos tecnicos

- Implementar a mudanca de forma localizada em `views/index.ejs`.
- Reaproveitar o estilo visual existente:
  - cores via variaveis CSS ja usadas na view;
  - botoes `primary-btn`, `secondary-btn` ou classes locais equivalentes;
  - icones Font Awesome, ja usados na tela.
- Usar como referencia o modal artesanal de `views/history.ejs`, mas adaptar para formulario de renomeacao.
- Evitar dependencia externa nova.
- Manter `fetch(renameUrl, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(...) })`.
- Continuar usando a resposta JSON do backend para mensagens de erro.
- Preservar `event.preventDefault()` e `event.stopPropagation()` no clique do botao.
- Usar `<%= ... %>` para conteudo renderizado pelo EJS quando aplicavel.
- Garantir que textos e botoes nao se sobreponham em telas pequenas.

## Sugestao de implementacao

- Adicionar no HTML de `views/index.ejs`, proximo ao fim do `body`, um modal dedicado, por exemplo:

```html
<div id="renameScriptModal" class="rename-script-modal" aria-hidden="true">
    <div class="rename-script-dialog" role="dialog" aria-modal="true" aria-labelledby="renameScriptTitle">
        ...
    </div>
</div>
```

- Incluir no modal:
  - titulo `Renomear script`;
  - texto com o nome atual;
  - input de texto para o novo nome;
  - area de erro;
  - botoes `Cancelar` e `Salvar`.
- Substituir a funcao atual `renameScript(event, button)` para apenas abrir o modal e guardar em estado local:
  - `currentName`;
  - `renameUrl`;
  - referencia do botao que abriu o modal, se necessario.
- Criar funcoes pequenas:
  - `openRenameScriptModal(currentName, renameUrl)`;
  - `closeRenameScriptModal()`;
  - `submitRenameScript()`;
  - `showRenameScriptError(message)`.
- Permitir fechar o modal por:
  - botao cancelar;
  - botao de fechar;
  - tecla `Escape`;
  - clique no backdrop, se seguir o padrao de `views/history.ejs`.
- No sucesso, manter `window.location.reload()` para atualizar a listagem de forma simples.

## Criterios de aceite

- O clique no icone de renomear abre um modal estilizado na propria pagina.
- O `prompt()` nao e mais usado no fluxo de renomeacao.
- Erros de validacao e erros retornados pelo backend aparecem dentro do modal.
- Cancelar ou fechar o modal nao renomeia o arquivo.
- Renomear para um nome valido continua funcionando.
- Renomear para nome existente ou invalido continua bloqueado pelo backend e mostra mensagem amigavel.
- A interface permanece usavel em largura pequena, sem sobreposicao de textos ou botoes.
- A acao de visualizar codigo fonte continua funcionando sem regressao.

## Testes sugeridos

- Abrir a tela principal autenticado e clicar no icone de renomear um script.
- Confirmar que o modal abre com o nome atual preenchido.
- Cancelar o modal e confirmar que nenhum arquivo foi alterado.
- Tentar salvar com campo vazio e confirmar que aparece erro no modal.
- Tentar salvar com o mesmo nome atual e confirmar que aparece erro no modal.
- Renomear um script valido e confirmar que a pagina recarrega com o novo nome.
- Tentar renomear para um nome ja existente e confirmar que a mensagem do backend aparece no modal.
- Tentar nomes invalidos como `../Teste.ps1`, `subpasta/Teste.ps1` e `Teste.txt`.
- Confirmar que clicar no icone de renomear nao seleciona a linha do script.
- Confirmar que o icone de visualizar codigo fonte ainda abre a popup normalmente.

## Validacao esperada

- Como a mudanca principal fica em EJS/CSS/JS inline, validar visualmente a tela principal com o servidor em execucao quando possivel.
- Se houver alteracao em `src/routes/mainRoutes.js`, rodar:

```powershell
node --check src\routes\mainRoutes.js
```

- Se a implementacao ficar restrita a `views/index.ejs`, documentar que nao ha validacao `node --check` aplicavel para a view.
