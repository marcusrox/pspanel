# TASK-002 - Destaque de sintaxe simples para scripts PowerShell

## Contexto

O sistema permite visualizar o codigo fonte dos scripts PowerShell em uma popup. Atualmente, o conteudo do arquivo e exibido como texto monoespacado, sem diferenciacao visual entre comandos, comentarios, strings, variaveis e outros elementos comuns da linguagem.

## Objetivo

Adicionar um destaque de sintaxe simples para melhorar a leitura dos scripts PowerShell visualizados pelo sistema, mantendo a implementacao leve, segura e compativel com a visualizacao atual.

## Escopo

- Aplicar highlight visual basico ao conteudo `.ps1` exibido na popup de codigo fonte.
- Diferenciar, no minimo:
  - comentarios;
  - strings;
  - variaveis;
  - palavras-chave comuns do PowerShell;
  - comandos ou cmdlets com padrao `Verbo-Substantivo`.
- Preservar quebras de linha, indentacao e espacamento do script original.
- Manter a exibicao em fonte monoespacada.
- Garantir que o conteudo do script continue sendo tratado como texto seguro, sem execucao ou interpretacao de HTML vindo do arquivo.
- Numeracao de linhas

## Fora de escopo

- Editor de codigo.
- Highlight completo ou perfeito da gramatica PowerShell.
- Autocomplete, busca, minimapa, folding ou outras funcionalidades de IDE.
- Execucao ou validacao sintatica do script.

## Requisitos funcionais

1. Ao abrir a visualizacao de codigo fonte de um script PowerShell, o conteudo deve aparecer com destaque de sintaxe basico.
2. O usuario deve conseguir ler comentarios, strings, variaveis e comandos com diferenciacao visual clara.
3. Scripts sem elementos reconhecidos devem continuar sendo exibidos corretamente como texto.
4. A popup deve continuar funcionando mesmo se o highlight falhar, exibindo o codigo sem formatacao especial.
5. A funcionalidade atual de abrir e visualizar scripts nao deve sofrer regressao.

## Requisitos tecnicos

- O highlight deve ser aplicado somente na view de visualizacao de codigo fonte, por exemplo em `views/script-source-popup.ejs`.
- O conteudo original do arquivo deve ser escapado antes de qualquer insercao no HTML.
- Se a implementacao usar JavaScript no frontend, deve operar sobre texto ja renderizado de forma segura.
- Se a implementacao gerar HTML no backend, deve garantir escape correto antes de envolver tokens com tags.
- Evitar dependencias pesadas para esta primeira versao.
- Preferir uma implementacao simples baseada em expressoes regulares ou uma biblioteca pequena.
- Manter estilos de highlight em CSS local da popup, se necessário.

## Sugestao de implementacao

- Criar um bloco de codigo com estrutura semelhante a:

```html
<pre class="script-source"><code class="language-powershell">...</code></pre>
```

- Se não usar biblioteca, implementar uma funcao simples de highlight que reconheca padroes comuns:
  - comentarios iniciados por `#`;
  - strings entre aspas simples ou duplas;
  - variaveis como `$name`, `$env:PATH` e `${name}`;
  - palavras-chave como `if`, `else`, `elseif`, `foreach`, `for`, `while`, `switch`, `function`, `param`, `return`, `try`, `catch`, `finally`, `throw`, `break` e `continue`;
  - cmdlets como `Get-Process`, `Set-Item`, `New-Object`, `Write-Host`.

- Se não usar biblioteca, usar classes CSS semanticas para os tokens, por exemplo:

```css
.token-comment { color: #6a737d; }
.token-string { color: #0a7f42; }
.token-variable { color: #0550ae; }
.token-keyword { color: #9a3412; font-weight: 600; }
.token-command { color: #7c3aed; }
```

## Criterios de aceite

- A popup de visualizacao de scripts apresenta highlight simples para arquivos `.ps1`.
- Comentarios, strings, variaveis, palavras-chave e cmdlets sao visualmente diferenciados.
- O conteudo do script nao e interpretado como HTML, mesmo quando contem tags ou caracteres especiais.
- Quebras de linha e indentacao sao preservadas.
- A visualizacao continua utilizavel para scripts grandes ou sem tokens reconhecidos.
- A abertura da popup e a rota de leitura do script continuam funcionando como antes.

## Testes sugeridos

- Abrir um script `.ps1` valido com comentarios, strings, variaveis, palavras-chave e cmdlets.
- Confirmar que cada tipo de token recebe uma cor ou estilo distinto.
- Testar um script contendo caracteres HTML, como:

```powershell
Write-Host "<script>alert('x')</script>"
```

- Confirmar que o trecho e exibido como texto e nao executado pelo navegador.
- Confirmar que scripts com acentos, linhas vazias e indentacao continuam legiveis.
- Confirmar que, se o JavaScript de highlight falhar, o codigo ainda aparece sem quebrar a popup.
