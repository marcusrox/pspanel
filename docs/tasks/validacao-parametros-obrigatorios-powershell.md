# Task: Validacao de parametros obrigatorios em scripts PowerShell

## Contexto

Alguns scripts PowerShell disponiveis no PS Panel possuem parametros obrigatorios declarados no bloco `param(...)`, por exemplo com `[Parameter(Mandatory=$true)]`. Quando o usuario solicita a execucao sem informar esses parametros, o PowerShell abre um prompt interativo na console aguardando entrada manual. Como a execucao foi iniciada pela aplicacao WEB, o usuario nao consegue responder esse prompt e a interface fica sem retorno adequado.

## Objetivo

Adicionar validacao de parametros obrigatorios na aplicacao WEB antes da execucao do script, impedindo que scripts PowerShell sejam iniciados quando faltarem valores exigidos.

## Escopo

- Identificar parametros obrigatorios declarados nos scripts `.ps1`.
- Exibir esses parametros na tela principal de execucao de scripts.
- Indicar visualmente quais parametros sao obrigatorios.
- Bloquear a execucao no frontend quando algum parametro obrigatorio estiver vazio.
- Bloquear a execucao tambem no backend, mesmo que a requisicao seja feita manualmente.
- Retornar uma mensagem amigavel ao usuario informando quais parametros obrigatorios estao faltando.
- Manter compatibilidade com scripts que nao possuem parametros obrigatorios.

## Fora de escopo

- Criar um parser completo da linguagem PowerShell.
- Suportar todos os formatos possiveis de atributos PowerShell.
- Validar regras avancadas como `ValidateSet`, `ValidatePattern`, `ValidateRange` ou tipos complexos, salvo se ja houver suporte simples reutilizavel.
- Criar prompt interativo no navegador durante a execucao.
- Alterar a assinatura dos scripts existentes.

## Requisitos funcionais

1. Ao listar os scripts, o sistema deve identificar quais parametros sao obrigatorios.
2. Ao selecionar um script com parametros obrigatorios, a interface deve exibir campos correspondentes para preenchimento.
3. Campos obrigatorios devem ser marcados de forma clara na interface.
4. O usuario nao deve conseguir iniciar a execucao se algum parametro obrigatorio estiver vazio.
5. Caso tente executar mesmo assim, o sistema deve mostrar mensagem amigavel, por exemplo:

```text
Informe os parametros obrigatorios: appName, AMBIENTE.
```

6. A validacao deve ocorrer tambem no backend antes de chamar `spawn("powershell.exe", ...)`.
7. Scripts sem parametros obrigatorios devem continuar executando como antes.
8. Scripts com parametros opcionais devem permitir execucao sem preencher esses campos.

## Requisitos tecnicos

- Reaproveitar a leitura existente dos scripts em `src/routes/mainRoutes.js`.
- Melhorar a extracao atual de parametros para identificar metadados basicos:
  - nome do parametro;
  - se e obrigatorio;
  - tipo declarado, quando simples;
  - valor padrao, quando existir de forma simples.
- Reconhecer pelo menos os seguintes formatos:

```powershell
param(
    [Parameter(Mandatory=$true)]
    [string]$appName,

    [Parameter(Mandatory = $true)]
    [ValidateSet("INTERNO", "EXTERNO")]
    [string]$AMBIENTE,

    [string]$Opcional = "valor"
)
```

- Considerar obrigatorio quando o atributo `Parameter` possuir `Mandatory=$true`, ignorando diferencas de maiusculas/minusculas e espacos.
- Evitar falso positivo para `Mandatory=$false`.
- No backend, antes de executar o script:
  - resolver o script com a mesma validacao de caminho ja usada para leitura de codigo fonte;
  - reler ou reutilizar os metadados de parametros do script;
  - comparar parametros obrigatorios com os valores enviados pela requisicao;
  - retornar erro HTTP adequado, como `400`, quando faltarem valores.
- Evitar montar argumentos PowerShell apenas por string livre quando houver parametros estruturados.
- Preservar o comportamento atual para scripts antigos enquanto a UI de parametros e ajustada.

## Sugestao de implementacao

- Backend:
  - substituir ou complementar `parseScriptParametersFromContent` para retornar uma estrutura como:

```js
{
  content: "...",
  parameters: [
    { name: "appName", type: "string", mandatory: true, defaultValue: null },
    { name: "AMBIENTE", type: "string", mandatory: true, defaultValue: null },
    { name: "Opcional", type: "string", mandatory: false, defaultValue: "valor" }
  ]
}
```

  - criar helper para validar parametros obrigatorios antes da execucao:

```js
function getMissingRequiredParameters(parameterDefinitions, providedParams) {
    return parameterDefinitions
        .filter((param) => param.mandatory)
        .filter((param) => !providedParams[param.name] || !String(providedParams[param.name]).trim())
        .map((param) => param.name);
}
```

  - ajustar `POST /run-script` para aceitar parametros estruturados, por exemplo:

```json
{
  "script": "Deploy-IIS.ps1",
  "params": {
    "appName": "Portal",
    "AMBIENTE": "INTERNO"
  }
}
```

  - montar os argumentos para o PowerShell usando pares `-NomeParametro valor`.

- Frontend:
  - ao selecionar um script, renderizar campos individuais para os parametros identificados.
  - usar `required` em inputs obrigatorios.
  - exibir marcador visual para parametros obrigatorios.
  - antes de enviar a execucao, validar os campos obrigatorios e exibir mensagem local se algum estiver vazio.

## Criterios de aceite

- Scripts com `[Parameter(Mandatory=$true)]` exibem campos obrigatorios na interface.
- A execucao e bloqueada no navegador quando campos obrigatorios estao vazios.
- A rota `POST /run-script` tambem bloqueia execucao com parametros obrigatorios ausentes.
- Quando a validacao falha, nenhum processo `powershell.exe` e iniciado.
- A mensagem de erro lista os parametros obrigatorios ausentes.
- Scripts sem parametros obrigatorios continuam executando sem preenchimento adicional.
- Parametros opcionais podem ficar vazios sem bloquear a execucao.
- A validacao nao permite que o PowerShell entre em prompt interativo por falta de parametros obrigatorios conhecidos.

## Testes sugeridos

- Selecionar um script como `Deploy-IIS.ps1` sem preencher `appName` e `AMBIENTE` e confirmar que a execucao e bloqueada.
- Preencher apenas um dos parametros obrigatorios e confirmar que a mensagem informa o parametro restante.
- Preencher todos os parametros obrigatorios e confirmar que a execucao chama o PowerShell com os argumentos corretos.
- Enviar uma requisicao manual para `POST /run-script` sem parametros obrigatorios e confirmar retorno `400`.
- Confirmar que nenhum processo PowerShell fica aguardando input na console.
- Testar um script sem parametros obrigatorios e confirmar que continua executando como antes.
- Testar formatos com espacos e caixa diferentes, como:

```powershell
[Parameter( Mandatory = $True )]
```

- Confirmar que `Mandatory=$false` nao marca o parametro como obrigatorio.
