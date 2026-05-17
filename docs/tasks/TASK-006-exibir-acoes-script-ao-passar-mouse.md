# TASK-006 - Exibir acoes do script apenas ao passar o mouse

## Contexto

A tela principal do sistema, `Painel de Scripts`, lista os scripts PowerShell disponiveis na pasta `scripts-ps`. Cada linha da listagem possui acoes para visualizar o codigo fonte do script e alterar o nome do arquivo.

Atualmente, os icones de visualizar script e renomear script ficam sempre visiveis na listagem. Para deixar a tela mais limpa, essas acoes devem aparecer somente quando o usuario interagir visualmente com a linha do script.

## Objetivo

Ajustar a listagem de scripts da tela principal para que os icones de visualizar codigo fonte e renomear script fiquem ocultos por padrao e sejam exibidos apenas ao passar o mouse sobre a linha correspondente.

## Escopo

- Ocultar por padrao os icones de visualizar codigo fonte e renomear script em cada linha da tabela de scripts.
- Exibir os icones quando o usuario passar o mouse sobre a linha do script.
- Manter os icones visiveis quando qualquer botao de acao estiver com foco, para preservar navegacao por teclado.
- Manter o comportamento atual de clicar em uma linha para selecionar o script.
- Manter o comportamento atual dos botoes de visualizar codigo fonte e renomear script.

## Fora de escopo

- Alterar rotas de backend.
- Alterar a funcionalidade de visualizar codigo fonte.
- Alterar a funcionalidade de renomear script.
- Criar novos icones ou novas acoes na listagem.
- Reestruturar a tabela de scripts alem do necessario para o comportamento de hover/foco.

## Requisitos funcionais

1. Ao carregar a tela principal, os icones de visualizar codigo fonte e renomear script nao devem aparecer nas linhas da listagem.
2. Ao passar o mouse sobre uma linha de script, os icones dessa linha devem aparecer.
3. Ao tirar o mouse da linha, os icones devem voltar a ficar ocultos.
4. Se o usuario navegar por teclado ate um dos botoes de acao, os icones da linha devem permanecer visiveis enquanto houver foco dentro da linha.
5. Clicar nos icones nao deve selecionar a linha nem executar o script.
6. Clicar na linha fora dos icones deve continuar selecionando o script normalmente.

## Requisitos tecnicos

- Reaproveitar os estilos existentes em `views/index.ejs`, especialmente:
  - `.scripts-table tbody tr`;
  - `.script-actions-cell`;
  - `.script-action-buttons`;
  - `.source-view-btn`;
  - `.rename-script-btn`.
- Aplicar o comportamento preferencialmente via CSS, usando seletores como:
  - `.scripts-table tbody tr .script-action-buttons`;
  - `.scripts-table tbody tr:hover .script-action-buttons`;
  - `.scripts-table tbody tr:focus-within .script-action-buttons`.
- Ocultar as acoes sem remover os botoes do DOM, para manter acessibilidade e preservar os handlers JavaScript existentes.
- Usar `opacity`, `visibility` e/ou `pointer-events` para controlar a exibicao sem alterar a largura da coluna de acoes.
- Manter uma transicao curta e discreta, se estiver alinhada ao estilo visual atual.
- Garantir que o layout da linha nao mude quando os icones aparecem.

Exemplo de ajuste esperado:

```css
.scripts-table tbody tr .script-action-buttons {
    opacity: 0;
    visibility: hidden;
    pointer-events: none;
}

.scripts-table tbody tr:hover .script-action-buttons,
.scripts-table tbody tr:focus-within .script-action-buttons {
    opacity: 1;
    visibility: visible;
    pointer-events: auto;
}
```

## Criterios de aceite

- Os icones de visualizar codigo fonte e renomear script ficam ocultos por padrao na listagem da tela principal.
- Os icones aparecem somente na linha em que o usuario esta com o mouse.
- Os icones tambem aparecem quando a linha contem foco de teclado.
- A coluna de acoes nao causa deslocamento visual quando os icones aparecem.
- A selecao de linha continua funcionando como antes.
- A abertura da popup de codigo fonte continua funcionando como antes.
- A renomeacao de script continua funcionando como antes.

## Testes sugeridos

- Abrir a tela principal autenticado e confirmar que os icones nao aparecem inicialmente na listagem.
- Passar o mouse sobre uma linha e confirmar que apenas os icones daquela linha aparecem.
- Tirar o mouse da linha e confirmar que os icones desaparecem.
- Clicar no icone de visualizar codigo fonte e confirmar que a popup abre normalmente.
- Clicar no icone de renomear script e confirmar que a acao de renomeacao continua funcionando.
- Confirmar que clicar nos icones nao seleciona a linha.
- Confirmar que clicar no restante da linha continua selecionando o script.
- Navegar por teclado ate os botoes de acao e confirmar que eles ficam visiveis durante o foco.
