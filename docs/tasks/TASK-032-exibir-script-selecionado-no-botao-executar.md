# TASK-032 - Exibir script selecionado junto ao botao Executar

## Contexto

Na tela principal do sistema, `Painel de Scripts`, o usuario seleciona um script clicando em uma linha da tabela de scripts disponiveis. A selecao fica destacada na tabela e o nome do script e armazenado no campo oculto `script`, mas a area de acoes do formulario mostra apenas os botoes `Executar` e `Limpar`.

Isso pode deixar duvida sobre qual script sera executado, especialmente quando a lista tem muitos itens ou quando o usuario rola a pagina ate os parametros e botoes.

## Objetivo

Melhorar a clareza da execucao manual exibindo o nome do script selecionado na frente do botao `Executar` e ajustando a ordem dos botoes para que `Limpar` apareca antes de `Executar`.

## Escopo

- Alterar a tela principal `views/index.ejs`.
- Exibir o nome do script selecionado proximo ao botao `Executar`, de forma visivel e atualizada quando o usuario selecionar outro script.
- Trocar a posicao dos botoes para manter `Limpar` antes de `Executar`.
- Garantir que o indicador do script selecionado seja limpo ao acionar `Limpar`.
- Preservar o fluxo atual de execucao via `hx-post="/run-script"` e a validacao existente de script selecionado.

## Fora de escopo

- Alterar rotas, controllers, models ou a execucao PowerShell.
- Mudar a forma de selecao dos scripts na tabela.
- Alterar regras de validacao de parametros obrigatorios.
- Reestruturar a tela inteira ou refatorar CSS global.
- Implementar novas mensagens de backend.

## Arquivos provaveis

- `views/index.ejs`

## Requisitos funcionais

1. Ao abrir o Painel de Scripts sem script selecionado, a area de acoes nao deve indicar um script antigo ou inexistente.
2. Ao selecionar um script na tabela, o nome do script selecionado deve aparecer na frente do botao `Executar`.
3. Ao selecionar outro script, o nome exibido deve ser atualizado imediatamente.
4. Ao clicar em `Limpar`, o campo oculto `script`, o destaque da linha selecionada, os parametros renderizados e o nome exibido junto ao botao devem ser limpos.
5. A ordem visual dos botoes deve ficar: `Limpar` primeiro, `Executar` depois.
6. O botao `Executar` deve continuar submetendo o formulario como antes.
7. O botao `Limpar` deve continuar sendo `type="button"` para nao submeter o formulario.

## Requisitos tecnicos

- Manter mensagens e textos visiveis em portugues.
- Usar saida escapada do EJS quando houver conteudo renderizado pelo servidor.
- Para atualizacao no cliente, usar `textContent` ao inserir o nome do script no DOM.
- Evitar incluir HTML dinamico com nome de script para nao abrir risco de XSS.
- Preferir um ajuste local no CSS inline de `views/index.ejs`, caso seja necessario alinhar o novo indicador aos botoes.
- Preservar acessibilidade basica: se o indicador for visual, ele deve ser legivel e nao depender apenas de cor.

## Sugestao de implementacao

1. Na area `.form-actions` de `views/index.ejs`, reposicionar o botao `Limpar` antes do botao `Executar`.
2. Adicionar um elemento pequeno perto do botao `Executar`, por exemplo um `span` com `id="selectedScriptName"` e texto inicial vazio ou um fallback como `Nenhum script selecionado`.
3. Na funcao que trata a selecao da linha do script, atualizar esse elemento com o valor de `data-script-name`.
4. Na funcao `clearForm()`, limpar tambem o texto do indicador.
5. Ajustar CSS apenas se necessario para manter os botoes e o nome do script alinhados em desktop e sem quebra ruim em telas menores.

## Criterios de aceite

- Ao selecionar `MeuScript.ps1`, a area de acoes mostra esse nome junto ao botao `Executar`.
- Ao trocar para outro script, o nome exibido muda para o novo script.
- Ao clicar em `Limpar`, nenhum nome de script permanece exibido como selecionado.
- A ordem dos botoes passa a ser `Limpar` e depois `Executar`.
- A execucao manual continua funcionando para scripts sem parametros e com parametros.
- A tela nao apresenta sobreposicao ou quebra visual incoerente em largura desktop comum.

## Testes sugeridos

- Abrir `/` autenticado e confirmar que nenhum script aparece como selecionado antes de clicar na tabela.
- Selecionar um script e verificar se o nome aparece junto ao botao `Executar`.
- Selecionar outro script e verificar se o nome exibido e atualizado.
- Clicar em `Limpar` e confirmar que o nome some, a linha perde o destaque e os parametros sao limpos.
- Executar um script selecionado e confirmar que o formulario continua enviando o script correto.

## Validacao esperada

- Como a mudanca e em `views/index.ejs`, fazer validacao visual da tela principal quando houver servidor disponivel.
- Se algum JavaScript embutido for alterado, validar sintaxe do trecho ou abrir a tela no navegador para confirmar ausencia de erro no console.

---

## Assinatura da LLM

- Data: 2026-07-13
- Modelo: GPT-5
- Versao: nao informado
- Acao: criacao
