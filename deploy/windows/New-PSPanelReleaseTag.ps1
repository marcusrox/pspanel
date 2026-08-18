<#
.SYNOPSIS
    Cria e publica a tag Git correspondente ao release atual do PS Panel.

.DESCRIPTION
    Le o campo version de src/config/release.js, valida o formato
    vAAAA.MM.DD-NNN e consulta as tags locais e remotas. A operacao e
    interrompida se ja existir uma release igual ou posterior.

    O script tambem exige uma arvore de trabalho limpa, o branch esperado e o
    HEAD ja publicado no branch remoto. Antes de qualquer criacao de tag, ele
    executa Test-PSPanelRelease.ps1 em um processo PowerShell isolado. O -WhatIf
    tambem executa essa validacao, mas nao cria nem publica a tag. A saida do
    processo isolado e capturada e exibida em UTF-8.

.PARAMETER ProjectRoot
    Diretorio raiz do clone Git do PS Panel.

.PARAMETER Remote
    Nome do remote Git que contem o branch e recebera a tag.

.PARAMETER Branch
    Nome do branch local e remoto que deve apontar para o commit da release.

.PARAMETER RequiredNodeVersion
    Versao exata do Node.js exigida pelo validador, incluindo o prefixo "v".

.INPUTS
    Nenhum. Este script nao aceita entrada pelo pipeline.

.OUTPUTS
    Objeto com os dados da tag publicada quando a operacao e concluida. Em
    -WhatIf, exibe o plano validado sem criar tag local ou remota.

.EXAMPLE
    .\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf

.EXAMPLE
    .\deploy\windows\New-PSPanelReleaseTag.ps1

.NOTES
    Git, Node.js, npm e PowerShell devem estar disponiveis no PATH. O validador
    executa npm ci, portanto processos que usam node_modules devem ser
    encerrados antes deste comando.
#>

[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ProjectRoot = (Join-Path $PSScriptRoot '..\..'),

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string] $Remote = 'origin',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9._/-]+$')]
    [string] $Branch = 'main',

    [Parameter()]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string] $RequiredNodeVersion = 'v24.18.0'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Arguments,

        [Parameter()]
        [switch] $Quiet
    )

    # No Windows PowerShell 5.1, stderr redirecionado por 2>&1 pode se tornar
    # um erro terminante quando ErrorActionPreference esta definido como Stop.
    # O Git usa stderr tambem para mensagens normais de progresso, inclusive
    # em pushes bem-sucedidos. Capture a saida com Continue e determine o
    # sucesso exclusivamente pelo codigo de saida do processo nativo.
    $previousErrorActionPreference = $ErrorActionPreference

    try {
        $ErrorActionPreference = 'Continue'
        $output = @(
            & $script:GitPath -C $script:ResolvedProjectRoot @Arguments 2>&1
        )
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    if (-not $Quiet) {
        $output | ForEach-Object { Write-Host ([string]$_) }
    }

    if ($exitCode -ne 0) {
        throw "Comando Git falhou com codigo ${exitCode}: git $($Arguments -join ' ')"
    }

    return @($output | ForEach-Object { [string]$_ })
}

function Invoke-ReleaseValidation {
    $validatorPath = Join-Path $script:ResolvedProjectRoot 'deploy\windows\Test-PSPanelRelease.ps1'
    if (-not (Test-Path -LiteralPath $validatorPath -PathType Leaf)) {
        throw "Validador de release nao encontrado: $validatorPath"
    }

    $preferredHosts = if ($PSVersionTable.PSEdition -eq 'Core') {
        @('pwsh.exe', 'powershell.exe')
    } else {
        @('powershell.exe', 'pwsh.exe')
    }

    $powerShellPath = $null
    foreach ($hostName in $preferredHosts) {
        $command = Get-Command $hostName -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($command) {
            $powerShellPath = $command.Source
            break
        }
    }

    if (-not $powerShellPath) {
        throw 'Nenhum executavel PowerShell foi encontrado no PATH para executar o validador.'
    }

    $arguments = @(
        '-NoProfile',
        '-File',
        $validatorPath,
        '-ProjectRoot',
        $script:ResolvedProjectRoot,
        '-RequiredNodeVersion',
        $RequiredNodeVersion
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $previousConsoleInputEncoding = [Console]::InputEncoding
    $previousConsoleOutputEncoding = [Console]::OutputEncoding
    $previousOutputEncoding = $OutputEncoding
    $previousConsoleCodePage = $previousConsoleInputEncoding.CodePage
    $utf8Encoding = [System.Text.UTF8Encoding]::new($false)

    try {
        chcp 65001 | Out-Null
        [Console]::InputEncoding = $utf8Encoding
        [Console]::OutputEncoding = $utf8Encoding
        $OutputEncoding = $utf8Encoding

        $ErrorActionPreference = 'Continue'
        $output = @(& $powerShellPath @arguments 2>&1)
        $exitCode = $LASTEXITCODE

        $output | ForEach-Object { Write-Host ([string]$_) }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        chcp $previousConsoleCodePage | Out-Null
        [Console]::InputEncoding = $previousConsoleInputEncoding
        [Console]::OutputEncoding = $previousConsoleOutputEncoding
        $OutputEncoding = $previousOutputEncoding
    }

    if ($exitCode -ne 0) {
        throw "O validador de release falhou com codigo $exitCode. Nenhuma tag foi criada ou publicada."
    }
}

function ConvertTo-ReleaseVersion {
    param([Parameter(Mandatory = $true)][string] $Value)

    if ($Value -notmatch '^v(?<year>\d{4})\.(?<month>\d{2})\.(?<day>\d{2})-(?<sequence>\d{3})$') {
        return $null
    }

    $dateText = '{0}.{1}.{2}' -f $Matches.year, $Matches.month, $Matches.day
    $parsedDate = [datetime]::MinValue
    $validDate = [datetime]::TryParseExact(
        $dateText,
        'yyyy.MM.dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsedDate
    )
    if (-not $validDate) {
        return $null
    }

    return [pscustomobject]@{
        Value = $Value
        Date = $parsedDate.Date
        Sequence = [int]$Matches.sequence
    }
}

function Get-CurrentReleaseVersion {
    $releasePath = Join-Path $script:ResolvedProjectRoot 'src\config\release.js'
    if (-not (Test-Path -LiteralPath $releasePath -PathType Leaf)) {
        throw "Arquivo de release nao encontrado: $releasePath"
    }

    $content = Get-Content -LiteralPath $releasePath -Raw -Encoding utf8
    $pattern = 'version\s*:\s*[''"](?<version>v\d{4}\.\d{2}\.\d{2}-\d{3})[''"]'
    $versionMatches = [regex]::Matches($content, $pattern)
    if ($versionMatches.Count -ne 1) {
        throw 'src/config/release.js deve conter exatamente um campo version no formato vAAAA.MM.DD-NNN.'
    }

    $value = $versionMatches[0].Groups['version'].Value
    $parsed = ConvertTo-ReleaseVersion -Value $value
    if (-not $parsed) {
        throw "Release invalida em src/config/release.js: $value"
    }

    return $parsed
}

function Get-LocalReleaseTags {
    return @(Invoke-GitCommand -Arguments @('tag', '--list', 'v*') -Quiet)
}

function Get-RemoteReleaseTags {
    $lines = @(Invoke-GitCommand `
        -Arguments @('ls-remote', '--tags', '--refs', $Remote, 'refs/tags/v*') `
        -Quiet)

    $tags = foreach ($line in $lines) {
        if ($line -match '^[0-9a-fA-F]+\s+refs/tags/(?<tag>[^\s]+)$') {
            $Matches.tag
        }
    }

    return @($tags)
}

function Assert-NoEqualOrLaterRelease {
    param(
        [Parameter(Mandatory = $true)]
        [object] $CurrentRelease,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $TagNames
    )

    $blockingTags = foreach ($tagName in ($TagNames | Sort-Object -Unique)) {
        $candidate = ConvertTo-ReleaseVersion -Value $tagName
        if (-not $candidate) {
            continue
        }

        $sameOrLaterSequence = $candidate.Sequence -ge $CurrentRelease.Sequence
        $laterDate = $candidate.Date -gt $CurrentRelease.Date
        if ($sameOrLaterSequence -or $laterDate) {
            $candidate
        }
    }

    $latestBlockingTag = $blockingTags |
        Sort-Object -Property @{ Expression = 'Sequence'; Descending = $true },
        @{ Expression = 'Date'; Descending = $true } |
        Select-Object -First 1

    if ($latestBlockingTag) {
        throw "Ja existe uma release igual ou posterior: $($latestBlockingTag.Value). Release atual: $($CurrentRelease.Value)."
    }
}

$script:ResolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not (Test-Path -LiteralPath (Join-Path $script:ResolvedProjectRoot '.git'))) {
    throw "O diretorio nao e um repositorio Git: $script:ResolvedProjectRoot"
}

$script:GitPath = (Get-Command git.exe -ErrorAction Stop).Source
$currentRelease = Get-CurrentReleaseVersion

$worktreeChanges = @(Invoke-GitCommand -Arguments @('status', '--porcelain') -Quiet)
if ($worktreeChanges.Count -gt 0) {
    throw "Existem alteracoes locais. Faca commit ou descarte-as antes de criar a tag:`n$($worktreeChanges -join "`n")"
}

$currentBranch = (@(Invoke-GitCommand -Arguments @('branch', '--show-current') -Quiet) -join '').Trim()
if ($currentBranch -ne $Branch) {
    throw "Branch atual inesperado. Esperado: $Branch. Encontrado: $currentBranch."
}

$headCommit = (@(Invoke-GitCommand -Arguments @('rev-parse', 'HEAD') -Quiet) -join '').Trim()
$remoteBranchRef = "refs/heads/$Branch"
$remoteBranchLine = (@(Invoke-GitCommand `
    -Arguments @('ls-remote', '--heads', $Remote, $remoteBranchRef) `
    -Quiet) -join '').Trim()

if ($remoteBranchLine -notmatch '^(?<commit>[0-9a-fA-F]{40})\s+') {
    throw "Nao foi possivel localizar $Remote/$Branch no repositorio remoto."
}

$remoteCommit = $Matches.commit
if ($headCommit -ne $remoteCommit) {
    throw "O HEAD local ($headCommit) ainda nao corresponde a $Remote/$Branch ($remoteCommit). Faca o push ou sincronize o branch antes de criar a tag."
}

$localTags = @(Get-LocalReleaseTags)
$remoteTags = @(Get-RemoteReleaseTags)
Assert-NoEqualOrLaterRelease `
    -CurrentRelease $currentRelease `
    -TagNames @($localTags + $remoteTags)

Write-Host 'Executando testes e validacoes obrigatorias da release...'
Invoke-ReleaseValidation
Write-Host 'Testes e validacoes da release aprovados.' -ForegroundColor Green

$tagName = $currentRelease.Value
$tagMessage = "Release $tagName"
$target = "$Remote/$tagName no commit $headCommit"

if (-not $PSCmdlet.ShouldProcess($target, 'criar tag anotada e publicar no repositorio remoto')) {
    Write-Host "Plano validado, incluindo os testes: criar e publicar $tagName no commit $headCommit."
    Write-Host 'Nenhuma tag foi criada.'
    return
}

[void](Invoke-GitCommand -Arguments @('tag', '-a', $tagName, '-m', $tagMessage, $headCommit))

try {
    [void](Invoke-GitCommand -Arguments @('push', $Remote, "refs/tags/$tagName"))
} catch {
    throw "A tag local $tagName foi criada, mas o push falhou. Detalhes: $($_.Exception.Message). Corrija o acesso remoto e execute: git push $Remote refs/tags/$tagName"
}

[pscustomobject]@{
    Success = $true
    Tag = $tagName
    Commit = $headCommit
    Remote = $Remote
    Branch = $Branch
    Published = $true
}
