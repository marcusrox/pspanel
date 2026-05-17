# Task: Alterar nome do script PowerShell

## Contexto

A tela principal do sistema, `Painel de Scripts`, lista os scripts PowerShell disponiveis na pasta `scripts-ps`. Cada linha da listagem ja possui uma acao para visualizar o codigo fonte do script usando um icone de olho.

## Objetivo

Adicionar uma nova acao ao lado do icone de visualizar script para permitir que o usuario altere o nome de um script PowerShell diretamente pela listagem da tela principal.

## Escopo

- Incluir um novo botao/icone de renomeacao em cada linha da listagem de scripts.
- Permitir informar o novo nome do arquivo `.ps1`.
- Renomear fisicamente o arquivo dentro da pasta `scripts-ps`.
- Atualizar a listagem apos a renomeacao bem-sucedida.
- Manter a acao atual de visualizar codigo fonte sem regressao.
- Restringir a renomeacao a arquivos `.ps1` existentes dentro da pasta `scripts-ps`.

## Fora de escopo

- Edicao do conteudo do script.
- Movimentacao de scripts para subpastas.
- Renomeacao de arquivos fora da pasta `scripts-ps`.
- Alteracao em registros historicos ja gravados, salvo se houver uma regra de negocio explicita para isso.
- Criacao de uma tela administrativa separada para gerenciamento completo de arquivos.

## Requisitos funcionais

1. Na tabela/lista de scripts da tela principal, cada script deve ter uma acao visivel para alterar seu nome.
2. A nova acao deve ficar ao lado do icone ja existente de visualizar codigo fonte.
3. Ao clicar na acao de renomear, o sistema deve solicitar o novo nome do script.
4. O nome sugerido inicialmente deve ser o nome atual do arquivo.
5. O usuario deve conseguir cancelar a operacao sem alterar o arquivo.
6. Ao confirmar um nome valido, o arquivo deve ser renomeado.
7. Depois da renomeacao, a tela deve refletir o novo nome na listagem.
8. A acao de renomear nao deve selecionar a linha nem disparar a execucao do script.
9. Caso o novo nome seja invalido, ja exista ou nao possa ser aplicado, o usuario deve receber uma mensagem amigavel.

## Requisitos tecnicos

- Reaproveitar os padroes existentes em `src/routes/mainRoutes.js` e `views/index.ejs`.
- Criar uma rota autenticada para renomear o script, por exemplo:

```text
POST /scripts/:scriptName/rename
```

- A rota deve receber o novo nome do script no corpo da requisicao, por exemplo:

```json
{
  "newScriptName": "Novo-Nome.ps1"
}
```

- A validacao do nome atual e do novo nome deve:
  - aceitar somente arquivos com extensao `.ps1`;
  - bloquear `..`, barras, contrabarras ou qualquer tentativa de path traversal;
  - confirmar que os caminhos resolvidos permanecem dentro de `scripts-ps`;
  - impedir nome vazio;
  - impedir sobrescrever um script existente;
  - opcionalmente normalizar o novo nome para adicionar `.ps1` quando o usuario informar somente o nome base.
- Usar `fs.rename`/`fs.promises.rename` para renomear o arquivo.
- Retornar status HTTP adequado:
  - `400` para nome invalido;
  - `404` para script original inexistente;
  - `409` para novo nome ja existente;
  - `500` para erro inesperado.
- Se for usado `fetch` no frontend, tratar respostas de erro e exibir a mensagem ao usuario.

## Sugestao de implementacao

- Backend:
  - reutilizar ou extrair a funcao `resolveScriptPath(scriptName)` para validar tanto o nome atual quanto o novo nome;
  - adicionar uma rota `POST /scripts/:scriptName/rename` em `src/routes/mainRoutes.js`;
  - verificar a existencia do arquivo original antes de renomear;
  - verificar se o arquivo de destino ja existe antes de chamar `rename`;
  - responder com JSON em caso de sucesso, por exemplo `{ "success": true, "scriptName": "Novo-Nome.ps1" }`.

- Frontend:
  - ajustar a celula de acoes em `views/index.ejs` para comportar dois botoes lado a lado;
  - adicionar um botao com icone de edicao/renomeacao, por exemplo Font Awesome `fa-pen` ou `fa-pen-to-square`;
  - criar uma funcao JavaScript, por exemplo `renameScript(event, button)`;
  - usar `event.preventDefault()` e `event.stopPropagation()` no clique do botao;
  - solicitar o novo nome inicialmente com `prompt()` ou, se o projeto preferir, com um modal dedicado;
  - enviar a requisicao via `fetch`;
  - em caso de sucesso, recarregar a pagina ou atualizar a linha da tabela.

Exemplo de comportamento esperado no clique:

```js
async function renameScript(event, button) {
    event.preventDefault();
    event.stopPropagation();

    const currentName = button.getAttribute('data-script-name');
    const newScriptName = prompt('Novo nome do script:', currentName);

    if (!newScriptName || newScriptName === currentName) {
        return;
    }

    const response = await fetch(`/scripts/${encodeURIComponent(currentName)}/rename`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ newScriptName })
    });

    if (!response.ok) {
        const data = await response.json().catch(() => null);
        alert(data && data.error ? data.error : 'Nao foi possivel renomear o script.');
        return;
    }

    window.location.reload();
}
```

## Criterios de aceite

- A tela principal exibe um novo icone de renomeacao ao lado do icone de visualizar codigo fonte.
- Clicar no icone de renomeacao solicita o novo nome do script.
- Um script valido pode ser renomeado com sucesso dentro da pasta `scripts-ps`.
- A listagem mostra o novo nome apos a renomeacao.
- A renomeacao nao permite sobrescrever outro script existente.
- Nomes invalidos, caminhos relativos e tentativas de path traversal sao bloqueados.
- Clicar no icone de renomeacao nao seleciona a linha e nao executa o script.
- A funcionalidade existente de visualizar codigo fonte continua funcionando.

## Testes sugeridos

- Abrir o `Painel de Scripts` autenticado e confirmar que cada linha possui os icones de visualizar e renomear.
- Renomear um script valido, por exemplo `Teste.ps1` para `Teste-Renomeado.ps1`.
- Confirmar que o arquivo foi renomeado fisicamente em `scripts-ps`.
- Confirmar que a listagem mostra o novo nome apos a operacao.
- Confirmar que o script renomeado ainda pode ser selecionado e executado.
- Tentar renomear para um nome ja existente e confirmar que a operacao e bloqueada.
- Tentar nomes invalidos, como:

```text
../Outro.ps1
subpasta/Outro.ps1
Outro.txt
```

- Confirmar que esses nomes sao bloqueados.
- Confirmar que cancelar a solicitacao do novo nome nao altera o arquivo.
