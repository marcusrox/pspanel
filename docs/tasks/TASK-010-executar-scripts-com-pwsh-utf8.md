# TASK-010 - Executar scripts com pwsh.exe e preservar UTF-8

## Contexto

A execucao de scripts PowerShell pelo painel apresentou problemas de acentuacao na saida exibida na tela.

Primeiro sintoma observado:

```text
Backup conclu��do!
Reposit��rio Git jǭ existe.
Backup automÃ¡tico FortiGate
```

Apos ajustar a saida do processo para UTF-8, o problema mudou para mojibake classico:

```text
Backup concluÃ­do!
RepositÃ³rio Git jÃ¡ existe.
Backup automÃ¡tico FortiGate
```

A investigacao mostrou que o arquivo `scripts-ps/Backup-Fortigate.ps1` esta em UTF-8 sem BOM. O Windows PowerShell classico (`powershell.exe`, 5.1) interpreta scripts UTF-8 sem BOM como ANSI/Windows-1252, entao literais como `concluido`, `Repositorio` e `ja` com acentos podem nascer corrompidos dentro do proprio PowerShell antes de chegarem ao Node.

Foi verificado que `pwsh.exe` esta instalado no ambiente:

```text
C:\Program Files\WindowsApps\Microsoft.PowerShell_7.6.1.0_x64__8wekyb3d8bbwe\pwsh.exe
```

Tambem foi confirmado que:

- `powershell.exe` le o trecho do script como `Backup concluÃ­do`;
- `pwsh.exe` le o mesmo trecho como `Backup concluído`.

## Objetivo

Alterar a execucao de scripts do painel para usar `pwsh.exe` por padrao, preservando UTF-8 de ponta a ponta na leitura dos arquivos `.ps1`, na captura de `stdout`/`stderr`, no historico e na resposta HTMX exibida na tela.

## Escopo

- Atualizar o helper de execucao PowerShell para usar `pwsh.exe` por padrao.
- Manter configuracao explicita de UTF-8 no processo PowerShell.
- Aplicar a mudanca ao fluxo manual de execucao de scripts.
- Aplicar a mudanca ao fluxo agendado de execucao de scripts.
- Definir charset UTF-8 explicito na resposta HTTP do endpoint `/run-script`.
- Escapar a saida renderizada dentro de `<pre>` para evitar HTML/script injection vindo da saida do PowerShell.
- Preservar separacao entre `stdout` e `stderr`.
- Preservar argumentos enviados aos scripts.
- Preservar historico de execucao.

## Fora de escopo

- Converter todos os arquivos `.ps1` para UTF-8 com BOM.
- Alterar o conteudo dos scripts em `scripts-ps/`.
- Criar uma tela de configuracao para escolher entre `pwsh.exe` e `powershell.exe`.
- Mudar o parser de parametros.
- Alterar regras de permissao, autenticacao ou validacao de nome de script.
- Refatorar a view principal alem do necessario para exibir a resposta com seguranca.
- Alterar comandos Git ou logica interna dos scripts PowerShell.

## Arquivos provaveis

```text
src/services/powerShellRunner.js
src/routes/mainRoutes.js
src/models/Schedule.js
```

Possivelmente tambem:

```text
views/index.ejs
```

Somente se for necessario ajustar como a resposta HTMX e exibida.

## Requisitos funcionais

1. Ao executar `scripts-ps/Backup-Fortigate.ps1` pelo painel, a saida deve exibir acentos corretamente:
   - `Backup concluído`;
   - `Repositório Git já existe`;
   - `Backup automático FortiGate`.
2. O mesmo comportamento deve valer para execucoes agendadas.
3. A saida de comandos nativos chamados pelo script, como `git commit`, deve continuar legivel.
4. Scripts existentes em UTF-8 sem BOM devem funcionar sem exigir conversao manual.
5. A interface deve continuar exibindo o resultado no painel de saida via HTMX.
6. Em caso de erro, `stderr` deve continuar sendo capturado e exibido no fluxo de erro.
7. O historico deve continuar gravando a saida final da execucao.

## Requisitos tecnicos

- Centralizar a escolha do executavel no helper `src/services/powerShellRunner.js`.
- Usar `pwsh.exe` como executavel padrao.
- Manter `-NoProfile`.
- Avaliar se `-ExecutionPolicy Bypass` deve ser mantido apenas no fluxo agendado atual, preservando comportamento existente.
- Manter wrapper que define:

```powershell
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
```

- No endpoint `/run-script`, responder com charset explicito, por exemplo:

```js
res.type('html; charset=utf-8');
```

ou equivalente compativel com Express.

- Escapar conteudo nao confiavel antes de inserir em HTML, especialmente `output`, `error` e `script` quando renderizados na resposta.
- Nao usar `<%- ... %>` nem `innerHTML` com conteudo vindo diretamente da saida do script sem escape.
- Nao introduzir ESM, dependencias novas ou build step.

## Sugestao de implementacao

1. Atualizar `src/services/powerShellRunner.js` para exportar tambem o nome do executavel ou uma funcao que retorne:

```js
function getPowerShellExecutable() {
    return 'pwsh.exe';
}
```

2. Trocar os `spawn('powershell.exe', ...)` dos fluxos atuais por algo centralizado, por exemplo:

```js
const ps = spawn(getPowerShellExecutable(), buildPowerShellCommandArgs(scriptPath, args));
```

3. Preservar no agendamento o comportamento atual de `ExecutionPolicy Bypass`, se ele continuar necessario:

```js
buildPowerShellCommandArgs(scriptPath, argList, { executionPolicy: 'Bypass' })
```

4. Adicionar uma funcao simples de escape HTML no backend onde a resposta e montada:

```js
function escapeHtml(value) {
    return String(value || '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
```

5. Usar essa funcao ao montar a resposta:

```js
res.type('html; charset=utf-8');
res.send(`<pre>${escapeHtml(output)}</pre><br />${escapeHtml(result)}`);
```

6. Aplicar tratamento equivalente para o fluxo de erro.

## Criterios de aceite

- A execucao manual usa `pwsh.exe`.
- A execucao agendada usa `pwsh.exe`.
- A saida do script `Backup-Fortigate.ps1` aparece com acentos corretos no painel.
- A mensagem do `git commit` aparece com acentos corretos quando houver commit.
- A resposta do endpoint `/run-script` declara charset UTF-8.
- A saida renderizada no `<pre>` esta escapada contra HTML/script injection.
- `stdout` e `stderr` continuam sendo acumulados separadamente.
- O historico continua sendo atualizado com `success` ou `error`.
- Nenhum arquivo `.ps1` e alterado.
- Nenhuma dependencia nova e adicionada.

## Testes sugeridos

- Rodar verificacao de sintaxe:

```powershell
node --check src\services\powerShellRunner.js
node --check src\routes\mainRoutes.js
node --check src\models\Schedule.js
```

- Testar leitura de acentos com `pwsh.exe`:

```powershell
pwsh.exe -NoProfile -Command '[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); (Get-Content .\scripts-ps\Backup-Fortigate.ps1 | Select-Object -Skip 117 -First 1)'
```

- Executar pelo painel o script afetado e confirmar a saida:

```text
Backup concluído! Arquivos salvos em C:\FortiGate-Backup
Repositório Git já existe.
Backup automático FortiGate - 2026-05-18 ...
Backup commitado no repositório Git.
```

- Executar um script que escreva em `stderr` e confirmar que o erro continua aparecendo.
- Verificar no historico se a saida foi gravada com acentos corretos.
- Quando seguro, validar tambem uma execucao agendada pelo worker.

## Validacao esperada

- Rodar `node --check` nos arquivos JavaScript alterados.
- Validar manualmente a execucao pelo painel com servidor em execucao.
- Se o worker for alterado ou validado, rodar:

```powershell
node --check scripts-js\schedule-worker.js
```

- Nao rodar `npm test`, pois o projeto ainda nao possui testes reais configurados.
