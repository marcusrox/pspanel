# TASK-017 - Corrigir largura do quadro de codigo fonte

## Contexto

A popup de visualizacao de codigo fonte em `/scripts/:scriptName/source` reaproveita o CSS global do painel. Esse CSS define `body` como `display: flex`, o que faz a area principal da popup se comportar como item flex.

Quando o script possui poucas linhas ou linhas curtas, a pagina pode encolher para a largura do conteudo. Com isso, o cabecalho e o quadro de codigo fonte ficam menores que a janela, deixando uma grande area vazia ao lado.

## Objetivo

Garantir que a tela de visualizar codigo fonte ocupe toda a largura da janela e que o quadro do codigo preencha a area disponivel mesmo quando o arquivo possui pouco texto.

## Escopo

- Ajustar apenas os estilos locais de `views/script-source-popup.ejs`.
- Fazer a pagina da popup ocupar 100% da largura da janela.
- Fazer a area de conteudo e o bloco de codigo crescerem para preencher o espaco disponivel.
- Preservar rolagem horizontal para linhas longas.
- Preservar a altura minima atual do quadro de codigo.
- Manter o visual operacional existente.

## Fora de escopo

- Alterar a rota de leitura de codigo fonte.
- Alterar validacao de nomes de scripts.
- Alterar highlight de sintaxe.
- Alterar a tela principal de scripts.
- Alterar o CSS global do painel.

## Arquivos alterados

```text
views/script-source-popup.ejs
```

## Criterios de aceite

- Ao abrir um script curto, o cabecalho da popup ocupa toda a largura da janela.
- Ao abrir um script curto, o quadro de codigo ocupa toda a largura disponivel.
- Ao abrir um script com linhas longas, a rolagem horizontal continua funcionando dentro do quadro.
- O quadro de codigo continua ocupando a altura minima esperada da janela.
- Nenhuma rota, controller, model ou arquivo SQLite e alterado.

## Testes sugeridos

- Abrir `/scripts/Codex-Param-Test3.ps1/source` ou outro script curto.
- Confirmar visualmente que o quadro de codigo acompanha a largura da janela.
- Redimensionar a popup e confirmar que o quadro se adapta.
- Abrir um script com linha longa e confirmar que a rolagem horizontal permanece dentro do quadro.

## Validacao esperada

Como a mudanca envolve EJS/CSS, validar visualmente a popup com o servidor em execucao quando possivel.

Nao e esperado alterar JavaScript. Se algum arquivo JavaScript for alterado por necessidade inesperada, rodar `node --check` no arquivo alterado.
