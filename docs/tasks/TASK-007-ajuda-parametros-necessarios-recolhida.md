# TASK-007 - Ajuda recolhida para parametros necessarios

## Contexto

Na tela principal, ao selecionar um script com parametros declarados, a interface exibia dois blocos consecutivos:

- `Parametros Necessarios`, com o conteudo informativo extraido do bloco `param(...)`.
- `Preenchimento de parametros`, com os campos que o usuario precisa preencher.

O bloco informativo permanecia sempre visivel e consumia espaco da tela, mesmo quando o usuario queria apenas preencher o formulario.

## Objetivo

Recolher as informacoes de `Parametros Necessarios` por padrao e disponibiliza-las por meio de um icone `?` dentro do quadro `Preenchimento de parametros`.

## Escopo

- Remover o bloco informativo sempre visivel acima do formulario.
- Adicionar um botao de ajuda no cabecalho de `Preenchimento de parametros`.
- Exibir ou ocultar o conteudo de `Parametros Necessarios` quando o usuario clicar no botao `?`.
- Manter o formulario de parametros como area principal da tela.
- Limpar o estado da ajuda ao trocar de script ou resetar o formulario.

## Fora de escopo

- Alterar o parser de parametros PowerShell.
- Alterar a validacao de parametros obrigatorios.
- Alterar a execucao dos scripts.
- Criar modal ou popup separado para a ajuda.

## Requisitos funcionais

1. Ao selecionar um script com parametros, o quadro `Preenchimento de parametros` deve continuar exibindo os campos normalmente.
2. O conteudo de `Parametros Necessarios` deve iniciar oculto.
3. O botao `?` deve aparecer no quadro `Preenchimento de parametros` quando houver informacao de parametros para mostrar.
4. Ao clicar no botao `?`, o conteudo informativo deve ser exibido dentro do mesmo quadro.
5. Ao clicar novamente no botao `?`, o conteudo informativo deve ser ocultado.
6. Ao selecionar outro script, a ajuda deve voltar ao estado recolhido.
7. Ao limpar o formulario, a ajuda e os campos devem ser removidos da tela.

## Requisitos tecnicos

- Implementar a mudanca em `views/index.ejs`.
- Usar o conteudo ja montado por `createParameterInfoContent`.
- Preservar o uso de `aria-expanded` e `aria-controls` no botao de ajuda.
- Evitar criar dependencias novas.

## Criterios de aceite

- O bloco `Parametros Necessarios` nao aparece mais como quadro separado sempre visivel.
- O icone `?` aparece no cabecalho de `Preenchimento de parametros` para scripts com informacoes de parametros.
- O clique no icone alterna corretamente entre mostrar e esconder a ajuda.
- A troca de script nao deixa informacoes antigas abertas na tela.
- O reset do formulario limpa campos, selecao e ajuda.
