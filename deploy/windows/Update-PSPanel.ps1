<#
.SYNOPSIS
    Atualiza ou reverte uma instalacao do PS Panel no Windows Server.

.DESCRIPTION
    Realiza um deploy semi-automatico a partir de uma tag ou commit Git.
    O fluxo baixa as referencias antes da indisponibilidade, interrompe o worker
    e o servico web, cria um snapshot dos dados locais, instala a versao,
    valida os arquivos, executa um health check e reativa o worker.

    Em caso de falha apos a parada dos componentes, tenta restaurar
    automaticamente o commit, o banco e as configuracoes anteriores.

.EXAMPLE
    .\Update-PSPanel.ps1 -Version 'v2026.07.22-034'

.EXAMPLE
    .\Update-PSPanel.ps1 -Version 'e3198ac' -WhatIf

.EXAMPLE
    .\Update-PSPanel.ps1 -Rollback '2026-07-22_103000-12345'
#>
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Deploy', ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Deploy')]
    [ValidateNotNullOrEmpty()]
    [string] $Version,

    [Parameter(Mandatory = $true, ParameterSetName = 'Rollback')]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $Rollback,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ProjectRoot = 'C:\Apps\PSPanel',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ServiceName = 'PSPanelWeb',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $WorkerTaskName = 'PSPanel Schedule Worker',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $HealthCheckUrl = 'http://127.0.0.1:3000/login',

    [Parameter()]
    [ValidateRange(1, 60)]
    [int] $HealthCheckAttempts = 10,

    [Parameter()]
    [ValidateRange(1, 30)]
    [int] $HealthCheckDelaySeconds = 3,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int] $BackupRetention = 10,

    [Parameter()]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string] $RequiredNodeVersion = 'v24.18.0',

    [Parameter()]
    [ValidateRange(10, 600)]
    [int] $WorkerTestTimeoutSeconds = 60,

    [Parameter()]
    [switch] $SkipWorkerTest,

    [Parameter()]
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$PSNativeCommandUseErrorActionPreference = $false

$script:LogFile = $null
$script:GitPath = $null
$script:NodePath = $null
$script:NpmPath = $null
$script:ResolvedProjectRoot = $null
$script:ResolvedBackupRoot = $null

function Write-DeployLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string] $Level,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Message
    )

    $line = "{0} {1} {2}" -f (Get-Date).ToString('o'), $Level, $Message
    if ($Level -eq 'ERROR') {
        Write-Host $line -ForegroundColor Red
    } elseif ($Level -eq 'WARN') {
        Write-Host $line -ForegroundColor Yellow
    } else {
        Write-Host $line
    }

    if ($script:LogFile) {
        Add-Content -LiteralPath $script:LogFile -Value $line -Encoding utf8
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter()]
        [string[]] $ArgumentList = @(),

        [Parameter()]
        [string] $WorkingDirectory = $script:ResolvedProjectRoot,

        [Parameter()]
        [int[]] $SuccessExitCodes = @(0),

        [Parameter()]
        [switch] $Quiet
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        $output = @(& $FilePath @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if (-not $Quiet) {
        foreach ($item in $output) {
            Write-DeployLog -Level 'INFO' -Message ([string]$item)
        }
    }

    if ($exitCode -notin $SuccessExitCodes) {
        $commandText = "{0} {1}" -f $FilePath, ($ArgumentList -join ' ')
        throw "Comando falhou com codigo ${exitCode}: $commandText"
    }

    return $output | ForEach-Object { [string]$_ }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter()]
        [switch] $Quiet
    )

    return @(Invoke-NativeCommand `
        -FilePath $script:GitPath `
        -ArgumentList $Arguments `
        -Quiet:$Quiet)
}

function Assert-PathInside {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ChildPath,

        [Parameter(Mandatory = $true)]
        [string] $ParentPath
    )

    $childFullPath = [System.IO.Path]::GetFullPath($ChildPath)
    $parentFullPath = [System.IO.Path]::GetFullPath($ParentPath).TrimEnd('\') + '\'
    if (-not $childFullPath.StartsWith($parentFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora do diretorio permitido: $childFullPath"
    }

    return $childFullPath
}

function Initialize-DeploymentContext {
    $script:ResolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

    foreach ($requiredFile in @(
        'app.js',
        'package.json',
        'package-lock.json',
        'scripts-js\schedule-worker.js',
        'database\pspanel.sqlite'
    )) {
        $path = Join-Path $script:ResolvedProjectRoot $requiredFile
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Arquivo obrigatorio nao encontrado: $path"
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedProjectRoot '.git'))) {
        throw "O diretorio nao e um clone Git: $script:ResolvedProjectRoot"
    }

    if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedProjectRoot '.env') -PathType Leaf)) {
        throw 'Arquivo .env nao encontrado. O deploy foi interrompido para preservar a configuracao local.'
    }

    $script:GitPath = (Get-Command git.exe -ErrorAction Stop).Source
    $script:NodePath = (Get-Command node.exe -ErrorAction Stop).Source
    $script:NpmPath = (Get-Command npm.cmd -ErrorAction Stop).Source

    $nodeVersion = (@(Invoke-NativeCommand -FilePath $script:NodePath -ArgumentList @('--version') -Quiet) -join '').Trim()
    if ($nodeVersion -ne $RequiredNodeVersion) {
        throw "Versao do Node.js nao homologada. Esperado: $RequiredNodeVersion. Encontrado: $nodeVersion."
    }

    Get-Service -Name $ServiceName -ErrorAction Stop | Out-Null
    Get-ScheduledTask -TaskName $WorkerTaskName -ErrorAction Stop | Out-Null

    $trackedChanges = @(Get-GitOutput -Arguments @('status', '--porcelain', '--untracked-files=no') -Quiet)
    if ($trackedChanges.Count -gt 0) {
        throw "Existem alteracoes locais em arquivos rastreados. O deploy nao descarta trabalho local:`n$($trackedChanges -join "`n")"
    }

    $script:ResolvedBackupRoot = [System.IO.Path]::GetFullPath("$script:ResolvedProjectRoot-Backups")
}

function Initialize-DeploymentLog {
    $logDirectory = Join-Path $script:ResolvedProjectRoot 'log\deploy'
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    $script:LogFile = Join-Path $logDirectory ("deploy-{0}.log" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'))
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
}

function New-DeploymentLock {
    $parentDirectory = Split-Path -Parent $script:ResolvedProjectRoot
    $lockPath = Join-Path $parentDirectory 'PSPanel.deploy.lock'
    $stream = $null
    $writer = $null

    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $stream.SetLength(0)
        $writer = [System.IO.StreamWriter]::new($stream, [System.Text.UTF8Encoding]::new($false), 1024, $true)
        $writer.Write(("PID={0};StartedAt={1}" -f $PID, (Get-Date).ToString('o')))
        $writer.Flush()
        $writer.Dispose()
        $writer = $null
        return [pscustomobject]@{ Path = $lockPath; Stream = $stream }
    } catch {
        $lockError = $_
        if ($writer) {
            try { $writer.Dispose() } catch { }
        }
        if ($stream) {
            try { $stream.Dispose() } catch { }
        }
        throw "Nao foi possivel obter o lock $lockPath. Detalhe: $($lockError.Exception.Message)"
    }
}

function Remove-DeploymentLock {
    param([object] $Lock)

    if (-not $Lock) {
        return
    }
    try { $Lock.Stream.Dispose() } catch { }
    try { Remove-Item -LiteralPath $Lock.Path -Force -ErrorAction SilentlyContinue } catch { }
}

function Get-CurrentCommit {
    return (@(Get-GitOutput -Arguments @('rev-parse', 'HEAD') -Quiet) -join '').Trim()
}

function Resolve-TargetCommit {
    param([Parameter(Mandatory = $true)][string] $Reference)

    $resolved = (@(Get-GitOutput -Arguments @('rev-parse', '--verify', "${Reference}^{commit}") -Quiet) -join '').Trim()
    if ($resolved -notmatch '^[0-9a-fA-F]{40}$') {
        throw "Nao foi possivel resolver a versao para um commit: $Reference"
    }

    $matchingTag = @(Get-GitOutput -Arguments @('tag', '--list', $Reference) -Quiet)
    $isCommitHash = $Reference -match '^[0-9a-fA-F]{7,40}$'
    if ($matchingTag.Count -eq 0 -and -not $isCommitHash -and -not $Force) {
        throw "'$Reference' nao e uma tag nem um hash de commit. Use uma tag/commit ou informe -Force para uma referencia movel."
    }

    return $resolved
}

function Stop-PSPanelComponents {
    Write-DeployLog -Level 'INFO' -Message "Desabilitando a tarefa '$WorkerTaskName'."
    Disable-ScheduledTask -TaskName $WorkerTaskName | Out-Null
    Stop-ScheduledTask -TaskName $WorkerTaskName -ErrorAction SilentlyContinue

    $taskDeadline = (Get-Date).AddSeconds(60)
    do {
        $task = Get-ScheduledTask -TaskName $WorkerTaskName
        if ($task.State -ne 'Running') {
            break
        }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $taskDeadline)

    if ((Get-ScheduledTask -TaskName $WorkerTaskName).State -eq 'Running') {
        throw "A tarefa '$WorkerTaskName' nao encerrou dentro de 60 segundos."
    }

    $service = Get-Service -Name $ServiceName
    if ($service.Status -ne 'Stopped') {
        Write-DeployLog -Level 'INFO' -Message "Parando o servico '$ServiceName'."
        Stop-Service -Name $ServiceName
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)][string] $Source,
        [Parameter(Mandatory = $true)][string] $Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function New-StateBackup {
    param(
        [Parameter(Mandatory = $true)][string] $PreviousCommit,
        [Parameter(Mandatory = $true)][string] $TargetCommit,
        [Parameter(Mandatory = $true)][string] $RequestedVersion,
        [Parameter(Mandatory = $true)][string] $Operation
    )

    New-Item -ItemType Directory -Path $script:ResolvedBackupRoot -Force | Out-Null
    $backupId = "{0}-{1}" -f (Get-Date -Format 'yyyy-MM-dd_HHmmss'), $PID
    $backupPath = Join-Path $script:ResolvedBackupRoot $backupId
    $backupPath = Assert-PathInside -ChildPath $backupPath -ParentPath $script:ResolvedBackupRoot
    New-Item -ItemType Directory -Path $backupPath | Out-Null

    Write-DeployLog -Level 'INFO' -Message "Criando snapshot em $backupPath."
    Copy-DirectoryContents `
        -Source (Join-Path $script:ResolvedProjectRoot 'database') `
        -Destination (Join-Path $backupPath 'database')

    Copy-Item `
        -LiteralPath (Join-Path $script:ResolvedProjectRoot '.env') `
        -Destination (Join-Path $backupPath '.env') `
        -Force

    $serviceXml = Join-Path $script:ResolvedProjectRoot 'service\PSPanelWeb.xml'
    if (Test-Path -LiteralPath $serviceXml -PathType Leaf) {
        New-Item -ItemType Directory -Path (Join-Path $backupPath 'service') -Force | Out-Null
        Copy-Item -LiteralPath $serviceXml -Destination (Join-Path $backupPath 'service\PSPanelWeb.xml') -Force
    }

    $nodeVersion = (@(Invoke-NativeCommand -FilePath $script:NodePath -ArgumentList @('--version') -Quiet) -join '').Trim()
    $powerShellVersion = $PSVersionTable.PSVersion.ToString()
    $manifest = [ordered]@{
        id = $backupId
        createdAt = (Get-Date).ToString('o')
        operation = $Operation
        requestedVersion = $RequestedVersion
        previousCommit = $PreviousCommit
        targetCommit = $TargetCommit
        nodeVersion = $nodeVersion
        powerShellVersion = $powerShellVersion
        computerName = $env:COMPUTERNAME
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupPath 'deployment.json') -Encoding utf8
    return $backupPath
}

function Restore-StateBackup {
    param([Parameter(Mandatory = $true)][string] $BackupPath)

    $resolvedBackupPath = (Resolve-Path -LiteralPath $BackupPath).Path
    [void](Assert-PathInside -ChildPath $resolvedBackupPath -ParentPath $script:ResolvedBackupRoot)

    $backupDatabase = Join-Path $resolvedBackupPath 'database'
    $backupEnvironment = Join-Path $resolvedBackupPath '.env'
    if (-not (Test-Path -LiteralPath $backupDatabase -PathType Container)) {
        throw "Snapshot sem diretorio database: $resolvedBackupPath"
    }
    if (-not (Test-Path -LiteralPath $backupEnvironment -PathType Leaf)) {
        throw "Snapshot sem arquivo .env: $resolvedBackupPath"
    }

    $databasePath = Assert-PathInside `
        -ChildPath (Join-Path $script:ResolvedProjectRoot 'database') `
        -ParentPath $script:ResolvedProjectRoot
    if ((Split-Path -Leaf $databasePath) -ne 'database') {
        throw "Diretorio de banco inesperado: $databasePath"
    }

    Write-DeployLog -Level 'WARN' -Message "Restaurando dados locais do snapshot $resolvedBackupPath."
    if (Test-Path -LiteralPath $databasePath) {
        Remove-Item -LiteralPath $databasePath -Recurse -Force
    }
    Copy-DirectoryContents -Source $backupDatabase -Destination $databasePath
    Copy-Item -LiteralPath $backupEnvironment -Destination (Join-Path $script:ResolvedProjectRoot '.env') -Force

    $backupServiceXml = Join-Path $resolvedBackupPath 'service\PSPanelWeb.xml'
    if (Test-Path -LiteralPath $backupServiceXml -PathType Leaf) {
        New-Item -ItemType Directory -Path (Join-Path $script:ResolvedProjectRoot 'service') -Force | Out-Null
        Copy-Item -LiteralPath $backupServiceXml -Destination (Join-Path $script:ResolvedProjectRoot 'service\PSPanelWeb.xml') -Force
    }
}

function Install-ApplicationCommit {
    param([Parameter(Mandatory = $true)][string] $Commit)

    Write-DeployLog -Level 'INFO' -Message "Aplicando commit $Commit."
    [void](Get-GitOutput -Arguments @('switch', '--detach', $Commit))

    Write-DeployLog -Level 'INFO' -Message 'Instalando dependencias com npm ci --omit=dev.'
    [void](Invoke-NativeCommand `
        -FilePath $script:NpmPath `
        -ArgumentList @('ci', '--omit=dev') `
        -WorkingDirectory $script:ResolvedProjectRoot)
}

function Test-ApplicationFiles {
    Write-DeployLog -Level 'INFO' -Message 'Validando sintaxe dos arquivos JavaScript versionados.'
    $javascriptFiles = @(Get-GitOutput -Arguments @('ls-files', '*.js') -Quiet)
    foreach ($relativePath in $javascriptFiles) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        [void](Invoke-NativeCommand `
            -FilePath $script:NodePath `
            -ArgumentList @('--check', $relativePath) `
            -WorkingDirectory $script:ResolvedProjectRoot `
            -Quiet)
    }

    Write-DeployLog -Level 'INFO' -Message 'Validando sintaxe dos scripts PowerShell versionados.'
    $powerShellFiles = @(Get-GitOutput -Arguments @('ls-files', '*.ps1') -Quiet)
    foreach ($relativePath in $powerShellFiles) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            continue
        }
        $fullPath = Join-Path $script:ResolvedProjectRoot $relativePath
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $fullPath,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null

        if ($parseErrors.Count -gt 0) {
            $messages = $parseErrors | ForEach-Object { $_.Message }
            throw "Falha de sintaxe em ${relativePath}: $($messages -join '; ')"
        }
    }
}

function Test-ApplicationHealth {
    $lastError = $null
    for ($attempt = 1; $attempt -le $HealthCheckAttempts; $attempt++) {
        try {
            $response = Invoke-WebRequest `
                -Uri $HealthCheckUrl `
                -UseBasicParsing `
                -TimeoutSec 15 `
                -MaximumRedirection 5
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                Write-DeployLog -Level 'INFO' -Message "Health check aprovado: HTTP $($response.StatusCode)."
                return
            }
            $lastError = "HTTP $($response.StatusCode)"
        } catch {
            $lastError = $_.Exception.Message
        }

        if ($attempt -lt $HealthCheckAttempts) {
            Start-Sleep -Seconds $HealthCheckDelaySeconds
        }
    }

    throw "Health check falhou apos $HealthCheckAttempts tentativa(s): $lastError"
}

function Start-ApplicationAndValidate {
    Write-DeployLog -Level 'INFO' -Message "Iniciando o servico '$ServiceName'."
    Start-Service -Name $ServiceName
    $service = Get-Service -Name $ServiceName
    $service.WaitForStatus('Running', [TimeSpan]::FromSeconds(60))
    Test-ApplicationHealth
}

function Enable-AndTestWorker {
    Write-DeployLog -Level 'INFO' -Message "Reativando a tarefa '$WorkerTaskName'."
    Enable-ScheduledTask -TaskName $WorkerTaskName | Out-Null

    if ($SkipWorkerTest) {
        Write-DeployLog -Level 'WARN' -Message 'Teste imediato do worker ignorado por -SkipWorkerTest.'
        return
    }

    Start-ScheduledTask -TaskName $WorkerTaskName
    $deadline = (Get-Date).AddSeconds($WorkerTestTimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        $task = Get-ScheduledTask -TaskName $WorkerTaskName
        if ($task.State -ne 'Running') {
            break
        }
    } while ((Get-Date) -lt $deadline)

    if ((Get-ScheduledTask -TaskName $WorkerTaskName).State -eq 'Running') {
        Write-DeployLog -Level 'WARN' -Message "O worker continua em execucao apos $WorkerTestTimeoutSeconds segundos; o resultado final deve ser acompanhado no Agendador."
        return
    }

    $taskInfo = Get-ScheduledTaskInfo -TaskName $WorkerTaskName
    if ($taskInfo.LastTaskResult -eq 0) {
        Write-DeployLog -Level 'INFO' -Message 'Teste do worker concluido com LastTaskResult=0.'
    } else {
        Write-DeployLog -Level 'WARN' -Message "O worker terminou com LastTaskResult=$($taskInfo.LastTaskResult). O deploy web foi mantido; investigue o worker separadamente."
    }
}

function Invoke-AutomaticRollback {
    param(
        [Parameter(Mandatory = $true)][string] $Commit,
        [Parameter(Mandatory = $true)][string] $BackupPath
    )

    Write-DeployLog -Level 'WARN' -Message "Iniciando rollback automatico para o commit $Commit."
    Disable-ScheduledTask -TaskName $WorkerTaskName -ErrorAction SilentlyContinue | Out-Null
    Stop-ScheduledTask -TaskName $WorkerTaskName -ErrorAction SilentlyContinue
    Stop-Service -Name $ServiceName -ErrorAction SilentlyContinue
    $service = Get-Service -Name $ServiceName
    if ($service.Status -ne 'Stopped') {
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60))
    }

    Install-ApplicationCommit -Commit $Commit
    Restore-StateBackup -BackupPath $BackupPath
    Start-ApplicationAndValidate
    Enable-ScheduledTask -TaskName $WorkerTaskName | Out-Null
    Write-DeployLog -Level 'WARN' -Message 'Rollback automatico concluido. O worker foi reativado sem execucao imediata.'
}

function Remove-ExpiredBackups {
    if (-not (Test-Path -LiteralPath $script:ResolvedBackupRoot -PathType Container)) {
        return
    }

    $expired = Get-ChildItem -LiteralPath $script:ResolvedBackupRoot -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $BackupRetention

    foreach ($directory in $expired) {
        $safePath = Assert-PathInside -ChildPath $directory.FullName -ParentPath $script:ResolvedBackupRoot
        Write-DeployLog -Level 'INFO' -Message "Removendo snapshot antigo: $safePath"
        Remove-Item -LiteralPath $safePath -Recurse -Force
    }
}

function Get-RollbackManifest {
    param([Parameter(Mandatory = $true)][string] $BackupId)

    if (-not (Test-Path -LiteralPath $script:ResolvedBackupRoot -PathType Container)) {
        throw "Diretorio de snapshots nao encontrado: $script:ResolvedBackupRoot"
    }

    $backupPath = Join-Path $script:ResolvedBackupRoot $BackupId
    $backupPath = Assert-PathInside -ChildPath $backupPath -ParentPath $script:ResolvedBackupRoot
    $manifestPath = Join-Path $backupPath 'deployment.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Manifesto de rollback nao encontrado: $manifestPath"
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding utf8 | ConvertFrom-Json
    } catch {
        throw "Manifesto de rollback invalido: $manifestPath"
    }

    if ([string]$manifest.previousCommit -notmatch '^[0-9a-fA-F]{40}$') {
        throw 'O snapshot nao possui um commit anterior valido.'
    }

    return [pscustomobject]@{ Path = $backupPath; Manifest = $manifest }
}

Initialize-DeploymentContext

$operationDescription = if ($PSCmdlet.ParameterSetName -eq 'Deploy') {
    "implantar a versao '$Version'"
} else {
    "restaurar o snapshot '$Rollback'"
}

if (-not $PSCmdlet.ShouldProcess($script:ResolvedProjectRoot, $operationDescription)) {
    Write-Host "Plano: $operationDescription em $script:ResolvedProjectRoot."
    Write-Host "Componentes: servico '$ServiceName' e tarefa '$WorkerTaskName'."
    Write-Host "Health check: $HealthCheckUrl"
    Write-Host "Nenhuma alteracao foi realizada."
    return
}

Initialize-DeploymentLog
$deploymentLock = $null
$snapshotPath = $null
$componentsStopped = $false
$deploymentCompleted = $false
$oldCommit = $null
$targetCommit = $null
$requestedVersion = $null
$selectedRollbackPath = $null

try {
    $deploymentLock = New-DeploymentLock
    Write-DeployLog -Level 'INFO' -Message "Inicio: $operationDescription."
    Write-DeployLog -Level 'INFO' -Message "Log: $script:LogFile"

    $oldCommit = Get-CurrentCommit

    if ($PSCmdlet.ParameterSetName -eq 'Deploy') {
        Write-DeployLog -Level 'INFO' -Message 'Atualizando referencias e tags do origin antes da indisponibilidade.'
        [void](Get-GitOutput -Arguments @('fetch', 'origin', '--tags', '--prune'))
        $targetCommit = Resolve-TargetCommit -Reference $Version
        $requestedVersion = $Version

        if ($oldCommit -eq $targetCommit -and -not $Force) {
            Write-DeployLog -Level 'INFO' -Message "A versao solicitada ja esta instalada: $targetCommit"
            $deploymentCompleted = $true
            return
        }
    } else {
        $rollbackData = Get-RollbackManifest -BackupId $Rollback
        $selectedRollbackPath = $rollbackData.Path
        $targetCommit = [string]$rollbackData.Manifest.previousCommit
        $requestedVersion = "rollback:$Rollback"
        [void](Get-GitOutput -Arguments @('cat-file', '-e', "${targetCommit}^{commit}") -Quiet)
    }

    Write-DeployLog -Level 'INFO' -Message "Commit atual: $oldCommit"
    Write-DeployLog -Level 'INFO' -Message "Commit alvo: $targetCommit"

    Stop-PSPanelComponents
    $componentsStopped = $true

    $snapshotPath = New-StateBackup `
        -PreviousCommit $oldCommit `
        -TargetCommit $targetCommit `
        -RequestedVersion $requestedVersion `
        -Operation $PSCmdlet.ParameterSetName

    Install-ApplicationCommit -Commit $targetCommit

    if ($selectedRollbackPath) {
        Restore-StateBackup -BackupPath $selectedRollbackPath
    }

    Test-ApplicationFiles
    Start-ApplicationAndValidate
    Enable-AndTestWorker
    Remove-ExpiredBackups

    $deploymentCompleted = $true
    Write-DeployLog -Level 'INFO' -Message "Operacao concluida com sucesso. Commit ativo: $(Get-CurrentCommit)"
    Write-DeployLog -Level 'INFO' -Message "Snapshot anterior: $snapshotPath"
}
catch {
    $deploymentError = $_
    Write-DeployLog -Level 'ERROR' -Message "Falha no deploy: $($deploymentError.Exception.Message)"

    if ($componentsStopped -and $snapshotPath -and $oldCommit) {
        try {
            Invoke-AutomaticRollback -Commit $oldCommit -BackupPath $snapshotPath
        } catch {
            Write-DeployLog -Level 'ERROR' -Message "FALHA CRITICA NO ROLLBACK: $($_.Exception.Message)"
            Write-DeployLog -Level 'ERROR' -Message "O worker permanece desabilitado. Intervencao manual necessaria. Snapshot: $snapshotPath"
            throw "Deploy e rollback falharam. Erro original: $($deploymentError.Exception.Message). Erro do rollback: $($_.Exception.Message)"
        }
    } elseif ($componentsStopped) {
        try {
            Start-ApplicationAndValidate
            Enable-ScheduledTask -TaskName $WorkerTaskName | Out-Null
        } catch {
            Write-DeployLog -Level 'ERROR' -Message "Nao foi possivel restaurar o estado operacional: $($_.Exception.Message)"
        }
    }

    throw $deploymentError
}
finally {
    Remove-DeploymentLock -Lock $deploymentLock
    if ($script:LogFile) {
        $status = if ($deploymentCompleted) { 'sucesso' } else { 'falha' }
        Write-DeployLog -Level 'INFO' -Message "Fim da operacao: $status."
    }
}

[pscustomobject]@{
    Success = $true
    Operation = $PSCmdlet.ParameterSetName
    RequestedVersion = $requestedVersion
    PreviousCommit = $oldCommit
    ActiveCommit = Get-CurrentCommit
    SnapshotPath = $snapshotPath
    LogFile = $script:LogFile
}
