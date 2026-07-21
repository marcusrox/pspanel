<#
.SYNOPSIS
    Instala a tarefa agendada do worker de agendamentos do PS Panel.

.DESCRIPTION
    Cria a tarefa "PSPanel Schedule Worker" com repeticao a cada cinco minutos.
    A tarefa executa scripts-js\schedule-worker.js diretamente pelo Node.js,
    usa o diretorio raiz do PS Panel como WorkingDirectory e ignora uma nova
    execucao quando a anterior ainda estiver ativa.

    Para uma conta de dominio comum, a credencial e solicitada interativamente.
    Para gMSA (nome terminado em $) e contas internas de servico do Windows,
    nenhuma senha e solicitada.

.EXAMPLE
    .\Install-PSPanelScheduleWorker.ps1 -RunAsUser 'DOMINIO\svc_pspanel'

.EXAMPLE
    .\Install-PSPanelScheduleWorker.ps1 -RunAsUser 'DOMINIO\gmsaPSPanel$'

.EXAMPLE
    .\Install-PSPanelScheduleWorker.ps1 `
        -ProjectRoot 'D:\Apps\PSPanel' `
        -RunAsUser 'DOMINIO\svc_pspanel' `
        -Force
#>
#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ProjectRoot = 'C:\Apps\PSPanel',

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string] $RunAsUser,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $NodePath = 'C:\Program Files\nodejs\node.exe',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $TaskName = 'PSPanel Schedule Worker',

    [Parameter()]
    [ValidateRange(1, 1440)]
    [int] $IntervalMinutes = 5,

    [Parameter()]
    [ValidateRange(1, 72)]
    [int] $ExecutionTimeLimitHours = 1,

    [Parameter()]
    [System.Management.Automation.PSCredential] $Credential,

    [Parameter()]
    [switch] $Force,

    [Parameter()]
    [switch] $StartAfterInstall
)

$ErrorActionPreference = 'Stop'

function Test-IsPasswordlessServiceAccount {
    param(
        [Parameter(Mandatory = $true)]
        [string] $AccountName
    )

    $normalized = $AccountName.Trim().ToUpperInvariant()
    $builtInAccounts = @(
        'SYSTEM',
        'LOCALSERVICE',
        'NETWORKSERVICE',
        'NT AUTHORITY\SYSTEM',
        'NT AUTHORITY\LOCAL SERVICE',
        'NT AUTHORITY\NETWORK SERVICE'
    )

    return $AccountName.EndsWith('$') -or $normalized -in $builtInAccounts
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$resolvedNodePath = (Resolve-Path -LiteralPath $NodePath).Path
$packageJsonPath = Join-Path $resolvedProjectRoot 'package.json'
$workerPath = Join-Path $resolvedProjectRoot 'scripts-js\schedule-worker.js'

if (-not (Test-Path -LiteralPath $packageJsonPath -PathType Leaf)) {
    throw "Raiz do PS Panel invalida (package.json nao encontrado): $resolvedProjectRoot"
}

if (-not (Test-Path -LiteralPath $workerPath -PathType Leaf)) {
    throw "Worker nao encontrado: $workerPath"
}

$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask -and -not $Force) {
    throw "A tarefa '$TaskName' ja existe. Use -Force para substitui-la."
}

$action = New-ScheduledTaskAction `
    -Execute $resolvedNodePath `
    -Argument 'scripts-js/schedule-worker.js' `
    -WorkingDirectory $resolvedProjectRoot

$trigger = New-ScheduledTaskTrigger `
    -Once `
    -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours $ExecutionTimeLimitHours) `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries

$description = "Executa o worker de agendamentos do PS Panel a cada $IntervalMinutes minuto(s)."
$isPasswordlessServiceAccount = Test-IsPasswordlessServiceAccount -AccountName $RunAsUser

if ($isPasswordlessServiceAccount) {
    if ($Credential) {
        throw 'Nao informe -Credential para gMSA ou conta interna de servico do Windows.'
    }

    $principal = New-ScheduledTaskPrincipal `
        -UserId $RunAsUser `
        -LogonType ServiceAccount `
        -RunLevel Limited

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description $description `
        -Force | Out-Null
} else {
    if (-not $Credential) {
        $Credential = Get-Credential `
            -UserName $RunAsUser `
            -Message "Credencial para executar a tarefa '$TaskName'"
    }

    if ($Credential.UserName -ne $RunAsUser) {
        throw "A credencial informada pertence a '$($Credential.UserName)', mas -RunAsUser recebeu '$RunAsUser'."
    }

    $plainPassword = $Credential.GetNetworkCredential().Password
    try {
        Register-ScheduledTask `
            -TaskName $TaskName `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -User $RunAsUser `
            -Password $plainPassword `
            -RunLevel Limited `
            -Description $description `
            -Force | Out-Null
    } finally {
        $plainPassword = $null
    }
}

if ($StartAfterInstall) {
    Start-ScheduledTask -TaskName $TaskName
}

$installedTask = Get-ScheduledTask -TaskName $TaskName
$installedInfo = Get-ScheduledTaskInfo -TaskName $TaskName

[pscustomobject]@{
    TaskName         = $installedTask.TaskName
    State            = $installedTask.State
    RunAsUser        = $installedTask.Principal.UserId
    Execute          = $installedTask.Actions.Execute
    Arguments        = $installedTask.Actions.Arguments
    WorkingDirectory = $installedTask.Actions.WorkingDirectory
    IntervalMinutes  = $IntervalMinutes
    NextRunTime      = $installedInfo.NextRunTime
}
