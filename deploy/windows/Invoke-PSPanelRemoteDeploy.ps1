<#
.SYNOPSIS
Solicita da estacao DEV o deploy de uma tag do PS Panel em um servidor remoto.

.DESCRIPTION
Valida a tag publicada em origin, confirma conectividade WSMan, abre uma
PSSession com Kerberos e verifica os pre-requisitos do PS Panel no servidor.
Executa primeiro o Update-PSPanel.ps1 remoto com -WhatIf. No modo efetivo,
solicita uma unica confirmacao local e chama o atualizador com -Confirm:$false.

O wrapper nao habilita WinRM, nao altera TrustedHosts, nao usa CredSSP, nao
transfere codigo ou dados e nao persiste credenciais. A PSSession e sempre
encerrada em um bloco finally.

.PARAMETER ComputerName
Hostname ou FQDN do servidor. Enderecos IP nao sao aceitos no fluxo Kerberos.

.PARAMETER Version
Tag obrigatoria no formato vAAAA.MM.DD-NNN.

.PARAMETER ProjectRoot
Raiz do PS Panel no servidor remoto. O padrao e C:\Apps\PSPanel.

.PARAMETER ConfigurationName
Nome opcional de um endpoint PowerShell Remoting previamente configurado.

.PARAMETER Credential
Credencial opcional usada apenas em memoria para WSMan e para a PSSession.

.PARAMETER HealthCheckUrl
URL HTTP ou HTTPS opcional, sem credenciais ou query, para um health check
adicional executado a partir da estacao DEV depois do deploy.

.INPUTS
Nenhum. Este script nao aceita entrada pelo pipeline.

.OUTPUTS
PSPanel.RemoteDeploymentResult com a tag, os dados do atualizador remoto, o
health check externo e o estado final conhecido. Falhas geram excecao
terminante e mantem o resultado como TargetObject quando disponivel.

.EXAMPLE
PS> .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName 'pspanel-dev.exemplo.local' `
    -Version 'v2026.08.18-061' `
    -WhatIf

Valida a tag, o servidor e a simulacao remota sem executar o deploy.

.EXAMPLE
PS> .\deploy\windows\Invoke-PSPanelRemoteDeploy.ps1 `
    -ComputerName 'pspanel-prod.exemplo.local' `
    -Version 'v2026.08.18-061' `
    -HealthCheckUrl 'https://pspanel.exemplo.local/login'

Executa a pre-validacao, solicita confirmacao local e implanta a tag.

.NOTES
Requer DNS, Kerberos e WinRM previamente configurados pela equipe responsavel.
O usuario remoto precisa ter permissao administrativa e o servidor precisa
acessar origin sem receber credenciais deste wrapper.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        $value = [string]$_
        $parsedAddress = $null
        if ([System.Net.IPAddress]::TryParse($value, [ref]$parsedAddress)) {
            throw 'Use hostname ou FQDN; endereco IP nao e aceito com Kerberos.'
        }
        if ($value.Length -gt 253 -or $value -notmatch '^(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$') {
            throw 'ComputerName deve ser um hostname ou FQDN valido.'
        }
        return $true
    })]
    [string] $ComputerName,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^v\d{4}\.\d{2}\.\d{2}-\d{3}$')]
    [string] $Version,

    [Parameter()]
    [ValidateScript({
        $value = [string]$_
        if ($value -notmatch '^[A-Za-z]:\\' -or $value.Substring(2) -match '[<>:"/|?*]' -or $value -match '(?:^|\\)\.\.(?:\\|$)') {
            throw 'ProjectRoot deve ser um caminho absoluto e seguro do Windows.'
        }
        return $true
    })]
    [string] $ProjectRoot = 'C:\Apps\PSPanel',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $ConfigurationName,

    [Parameter()]
    [System.Management.Automation.PSCredential] $Credential,

    [Parameter()]
    [ValidateScript({
        if (-not $_.IsAbsoluteUri -or $_.Scheme -notin @('http', 'https')) {
            throw 'HealthCheckUrl deve ser uma URL HTTP ou HTTPS absoluta.'
        }
        if (-not [string]::IsNullOrEmpty($_.UserInfo) -or
            -not [string]::IsNullOrEmpty($_.Query) -or
            -not [string]::IsNullOrEmpty($_.Fragment)) {
            throw 'HealthCheckUrl nao pode conter credenciais, query ou fragmento.'
        }
        return $true
    })]
    [uri] $HealthCheckUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$script:LocalProjectRoot = $null
$script:GitPath = $null

function Invoke-LocalGitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& $script:GitPath -C $script:LocalProjectRoot @ArgumentList 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if ($exitCode -ne 0) {
        throw "Nao foi possivel consultar a tag no remote origin. Codigo Git: $exitCode."
    }

    return @($output | ForEach-Object { [string]$_ })
}

function Assert-PublishedReleaseTag {
    $script:LocalProjectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
    if (-not (Test-Path -LiteralPath (Join-Path $script:LocalProjectRoot '.git'))) {
        throw "A raiz local nao e um repositorio Git: $script:LocalProjectRoot"
    }

    $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction Stop |
        Select-Object -First 1
    $script:GitPath = $gitCommand.Source
    $remoteLines = @(Invoke-LocalGitCommand -ArgumentList @(
        'ls-remote',
        '--tags',
        '--refs',
        'origin',
        "refs/tags/$Version"
    ))
    $matchingLines = @($remoteLines | Where-Object {
        $_ -match "^[0-9a-fA-F]{40}\s+refs/tags/$([regex]::Escape($Version))$"
    })

    if ($matchingLines.Count -ne 1) {
        throw "A tag '$Version' nao foi encontrada de forma univoca no remote origin."
    }

    return ($matchingLines[0] -split '\s+')[0]
}

function Test-KerberosConnectivity {
    $parameters = @{
        ComputerName = $ComputerName
        Authentication = 'Kerberos'
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $parameters.Credential = $Credential
    }

    [void](Test-WSMan @parameters)
}

function New-KerberosSession {
    $parameters = @{
        ComputerName = $ComputerName
        Authentication = 'Kerberos'
        ErrorAction = 'Stop'
    }
    if ($ConfigurationName) {
        $parameters.ConfigurationName = $ConfigurationName
    }
    if ($Credential) {
        $parameters.Credential = $Credential
    }

    return New-PSSession @parameters
}

function Invoke-RemoteEnvironmentPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session
    )

    return Invoke-Command `
        -Session $Session `
        -ArgumentList @($ProjectRoot, 'PSPanelWeb', 'PSPanel Schedule Worker') `
        -ErrorAction Stop `
        -ScriptBlock {
            param($remoteProjectRoot, $serviceName, $workerTaskName)

            $resolvedRoot = (Resolve-Path -LiteralPath $remoteProjectRoot -ErrorAction Stop).Path
            $updatePath = Join-Path $resolvedRoot 'deploy\windows\Update-PSPanel.ps1'
            if (-not (Test-Path -LiteralPath $updatePath -PathType Leaf)) {
                throw "Atualizador remoto nao encontrado: $updatePath"
            }
            if (-not (Test-Path -LiteralPath (Join-Path $resolvedRoot '.git'))) {
                throw "A raiz remota nao e um clone Git: $resolvedRoot"
            }

            $gitCommand = Get-Command git.exe -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
            $nodeCommand = Get-Command node.exe -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
            $npmCommand = Get-Command npm.cmd -CommandType Application -ErrorAction Stop |
                Select-Object -First 1
            $gitPath = $gitCommand.Source
            $nodePath = $nodeCommand.Source
            $npmPath = $npmCommand.Source
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            $worker = Get-ScheduledTask -TaskName $workerTaskName -ErrorAction Stop
            $workerInfo = Get-ScheduledTaskInfo -TaskName $workerTaskName -ErrorAction Stop

            $nodeVersion = @(& $nodePath --version 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw 'Nao foi possivel consultar a versao do Node.js no servidor.'
            }

            [pscustomobject]@{
                ComputerName = $env:COMPUTERNAME
                ProjectRoot = $resolvedRoot
                UpdatePath = $updatePath
                GitAvailable = [bool]$gitPath
                NodeVersion = (@($nodeVersion) -join '').Trim()
                NpmAvailable = [bool]$npmPath
                ServiceStatus = $service.Status.ToString()
                WorkerState = $worker.State.ToString()
                WorkerLastTaskResult = $workerInfo.LastTaskResult
            }
        }
}

function Find-DeploymentResult {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $InputObjects
    )

    return @($InputObjects | Where-Object {
        $_ -and
        $_.PSObject.Properties.Name -contains 'Operation' -and
        $_.PSObject.Properties.Name -contains 'RequestedVersion' -and
        $_.PSObject.Properties.Name -contains 'ActiveCommit' -and
        $_.PSObject.Properties.Name -contains 'ServiceStatus' -and
        $_.PSObject.Properties.Name -contains 'WorkerState'
    }) | Select-Object -Last 1
}

function Invoke-RemoteUpdater {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession] $Session,

        [Parameter(Mandatory = $true)]
        [bool] $Preview
    )

    $received = [System.Collections.Generic.List[object]]::new()
    try {
        Invoke-Command `
            -Session $Session `
            -ArgumentList @($ProjectRoot, $Version, $Preview) `
            -ErrorAction Stop `
            -ScriptBlock {
                param($remoteProjectRoot, $requestedVersion, $previewOnly)

                $updatePath = Join-Path $remoteProjectRoot 'deploy\windows\Update-PSPanel.ps1'
                if ($previewOnly) {
                    & $updatePath `
                        -Version $requestedVersion `
                        -ProjectRoot $remoteProjectRoot `
                        -WhatIf `
                        -Confirm:$false
                } else {
                    & $updatePath `
                        -Version $requestedVersion `
                        -ProjectRoot $remoteProjectRoot `
                        -Confirm:$false
                }
            } | ForEach-Object { [void]$received.Add($_) }
    }
    catch {
        $remoteError = $_
        $remoteResult = Find-DeploymentResult -InputObjects @($received)
        if (-not $remoteResult -and $remoteError.TargetObject) {
            $remoteResult = Find-DeploymentResult -InputObjects @($remoteError.TargetObject)
        }

        $exception = [System.InvalidOperationException]::new(
            'O atualizador remoto terminou com falha. Consulte o resultado e o log remoto.',
            $remoteError.Exception
        )
        $errorRecord = [System.Management.Automation.ErrorRecord]::new(
            $exception,
            'PSPanelRemoteUpdaterFailed',
            [System.Management.Automation.ErrorCategory]::OperationStopped,
            $remoteResult
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    $result = Find-DeploymentResult -InputObjects @($received)
    if (-not $result) {
        throw 'O atualizador remoto nao retornou PSPanel.DeploymentResult.'
    }

    return $result
}

function Invoke-ExternalHealthCheck {
    if (-not $HealthCheckUrl) {
        return [pscustomobject]@{ Status = 'NaoSolicitado'; HttpStatusCode = $null }
    }

    $lastFailure = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            $response = Invoke-WebRequest `
                -Uri $HealthCheckUrl `
                -UseBasicParsing `
                -TimeoutSec 15 `
                -MaximumRedirection 5 `
                -ErrorAction Stop
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400) {
                return [pscustomobject]@{
                    Status = 'Aprovado'
                    HttpStatusCode = [int]$response.StatusCode
                }
            }
            $lastFailure = "HTTP $($response.StatusCode)"
        }
        catch {
            $lastFailure = $_.Exception.GetType().Name
        }

        if ($attempt -lt 3) {
            Start-Sleep -Seconds 3
        }
    }

    throw "O health check a partir da estacao falhou apos 3 tentativas: $lastFailure"
}

function New-RemoteDeploymentResult {
    param(
        [Parameter(Mandatory = $true)][bool] $Success,
        [Parameter(Mandatory = $true)][string] $Status,
        [Parameter(Mandatory = $true)][bool] $WhatIf,
        [AllowNull()][object] $RemotePreflight,
        [AllowNull()][object] $PreviewResult,
        [AllowNull()][object] $DeploymentResult,
        [AllowNull()][object] $ExternalHealthCheck,
        [AllowNull()][object] $TagObjectId
    )

    $effectiveResult = if ($DeploymentResult) { $DeploymentResult } else { $PreviewResult }
    $result = [pscustomobject]@{
        Success = $Success
        Status = $Status
        WhatIf = $WhatIf
        ComputerName = $ComputerName
        Version = $Version
        TagObjectId = $TagObjectId
        PreviousCommit = if ($effectiveResult) { $effectiveResult.PreviousCommit } else { $null }
        TargetCommit = if ($effectiveResult) { $effectiveResult.TargetCommit } else { $null }
        ActiveCommit = if ($effectiveResult) { $effectiveResult.ActiveCommit } else { $null }
        SnapshotPath = if ($effectiveResult) { $effectiveResult.SnapshotPath } else { $null }
        ServiceStatus = if ($effectiveResult) { $effectiveResult.ServiceStatus } else { $null }
        WorkerState = if ($effectiveResult) { $effectiveResult.WorkerState } else { $null }
        WorkerLastTaskResult = if ($effectiveResult) { $effectiveResult.WorkerLastTaskResult } else { $null }
        RemoteHealthCheck = if ($effectiveResult) { $effectiveResult.HealthCheck } else { $null }
        ExternalHealthCheck = $ExternalHealthCheck
        RemoteLogFile = if ($effectiveResult) { $effectiveResult.LogFile } else { $null }
        AutomaticRollbackPerformed = if ($effectiveResult) { $effectiveResult.AutomaticRollbackPerformed } else { $false }
        AutomaticRollbackSucceeded = if ($effectiveResult) { $effectiveResult.AutomaticRollbackSucceeded } else { $null }
        RemotePreflight = $RemotePreflight
        RemoteResult = $effectiveResult
        CompletedAt = (Get-Date).ToString('o')
    }
    $result.PSObject.TypeNames.Insert(0, 'PSPanel.RemoteDeploymentResult')
    return $result
}

function Write-RemoteDeploymentSummary {
    param([Parameter(Mandatory = $true)][object] $Result)

    $remoteHealthStatus = if ($Result.RemoteHealthCheck) {
        $Result.RemoteHealthCheck.Status
    } else {
        'NaoExecutado'
    }
    $externalHealthStatus = if ($Result.ExternalHealthCheck) {
        $Result.ExternalHealthCheck.Status
    } else {
        'NaoExecutado'
    }

    Write-Host ''
    Write-Host 'Resumo do deploy remoto:'
    Write-Host "Status: $($Result.Status)"
    Write-Host "Servidor: $($Result.ComputerName)"
    Write-Host "Tag: $($Result.Version)"
    Write-Host "Commit anterior: $($Result.PreviousCommit)"
    Write-Host "Commit ativo: $($Result.ActiveCommit)"
    Write-Host "Snapshot: $($Result.SnapshotPath)"
    Write-Host "Servico: $($Result.ServiceStatus)"
    Write-Host "Worker: $($Result.WorkerState); ultimo resultado: $($Result.WorkerLastTaskResult)"
    Write-Host "Health check remoto: $remoteHealthStatus"
    Write-Host "Health check da estacao: $externalHealthStatus"
    Write-Host "Log remoto: $($Result.RemoteLogFile)"
}

$session = $null
$tagObjectId = $null
$remotePreflight = $null
$previewResult = $null
$deploymentResult = $null
$externalHealthCheck = [pscustomobject]@{ Status = 'NaoExecutado'; HttpStatusCode = $null }

try {
    Write-Host "Validando a tag '$Version' no remote origin..."
    $tagObjectId = Assert-PublishedReleaseTag

    Write-Host "Validando WSMan com Kerberos em '$ComputerName'..."
    Test-KerberosConnectivity

    $session = New-KerberosSession
    Write-Host 'Validando o ambiente remoto...'
    $remotePreflight = Invoke-RemoteEnvironmentPreflight -Session $session

    Write-Host 'Executando a simulacao do atualizador no servidor...'
    $previewResult = Invoke-RemoteUpdater -Session $session -Preview $true
    if (-not $previewResult.Success -or $previewResult.Status -ne 'SimulacaoAprovada') {
        throw "A simulacao remota nao foi aprovada. Status: $($previewResult.Status)"
    }

    $target = "$ComputerName / $Version"
    if (-not $PSCmdlet.ShouldProcess($target, 'executar o deploy remoto do PS Panel')) {
        $status = if ($WhatIfPreference) { 'SimulacaoAprovada' } else { 'Cancelado' }
        $simulationResult = New-RemoteDeploymentResult `
            -Success $true `
            -Status $status `
            -WhatIf ([bool]$WhatIfPreference) `
            -RemotePreflight $remotePreflight `
            -PreviewResult $previewResult `
            -DeploymentResult $null `
            -ExternalHealthCheck $externalHealthCheck `
            -TagObjectId $tagObjectId
        Write-RemoteDeploymentSummary -Result $simulationResult
        Write-Output $simulationResult
        return
    }

    Write-Host "Executando o deploy de '$Version' em '$ComputerName'..."
    $deploymentResult = Invoke-RemoteUpdater -Session $session -Preview $false
    if (-not $deploymentResult.Success) {
        throw "O atualizador remoto retornou falha. Status: $($deploymentResult.Status)"
    }

    try {
        $externalHealthCheck = Invoke-ExternalHealthCheck
    }
    catch {
        $externalHealthCheck = [pscustomobject]@{ Status = 'Falhou'; HttpStatusCode = $null }
        throw
    }
    $successResult = New-RemoteDeploymentResult `
        -Success $true `
        -Status 'Sucesso' `
        -WhatIf $false `
        -RemotePreflight $remotePreflight `
        -PreviewResult $previewResult `
        -DeploymentResult $deploymentResult `
        -ExternalHealthCheck $externalHealthCheck `
        -TagObjectId $tagObjectId
    Write-RemoteDeploymentSummary -Result $successResult
    Write-Output $successResult
}
catch {
    $wrapperError = $_
    if (-not $deploymentResult -and $wrapperError.TargetObject) {
        $deploymentResult = Find-DeploymentResult -InputObjects @($wrapperError.TargetObject)
    }

    $failureResult = New-RemoteDeploymentResult `
        -Success $false `
        -Status 'Falha' `
        -WhatIf ([bool]$WhatIfPreference) `
        -RemotePreflight $remotePreflight `
        -PreviewResult $previewResult `
        -DeploymentResult $deploymentResult `
        -ExternalHealthCheck $externalHealthCheck `
        -TagObjectId $tagObjectId
    Write-RemoteDeploymentSummary -Result $failureResult
    Write-Output $failureResult

    $exception = [System.InvalidOperationException]::new(
        "Falha no deploy remoto de '$Version' em '$ComputerName'.",
        $wrapperError.Exception
    )
    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'PSPanelRemoteDeployFailed',
        [System.Management.Automation.ErrorCategory]::OperationStopped,
        $failureResult
    )
    $PSCmdlet.ThrowTerminatingError($errorRecord)
}
finally {
    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}
