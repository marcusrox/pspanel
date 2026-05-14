<#
.SYNOPSIS
    Executa o worker de agendamentos do PS Panel (processa jobs vencidos no SQLite).

.DESCRIPTION
    Destinado a ser chamado pelo Agendador de Tarefas do Windows (por exemplo a cada 5 minutos).
    Resolve o caminho do repositório, valida package.json e scripts-js\schedule-worker.js, e invoca
    o Node.js para executar a mesma lógica de processamento usada pela aplicação web (SQLite em database\).

.PARAMETER ProjectRoot
    Caminho absoluto da raiz do repositório PS Panel (pasta onde está o arquivo package.json).

.EXAMPLE
    .\Invoke-ScheduleWorker.ps1 -ProjectRoot "C:\Projects\PSPanel"

.EXAMPLE
    pwsh -NoProfile -File .\Invoke-ScheduleWorker.ps1 -ProjectRoot "D:\Apps\PSPanel"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ProjectRoot
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot 'package.json'))) {
    throw "ProjectRoot inválido (package.json não encontrado): $ProjectRoot"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw "Node.js não está no PATH. Instale o Node ou ajuste o PATH do sistema / da tarefa agendada."
}

$worker = Join-Path $ProjectRoot 'scripts-js\schedule-worker.js'
if (-not (Test-Path -LiteralPath $worker)) {
    throw "Arquivo do worker não encontrado: $worker"
}

Set-Location -LiteralPath $ProjectRoot
& node $worker
exit $LASTEXITCODE
