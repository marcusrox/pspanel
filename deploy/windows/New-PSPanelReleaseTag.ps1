<#
.SYNOPSIS
    Cria e publica a tag Git correspondente ao release atual do PS Panel.

.DESCRIPTION
    Le o campo version de src/config/release.js, valida o formato
    vAAAA.MM.DD-NNN e consulta as tags locais e remotas. A operacao e
    interrompida se ja existir uma release igual ou posterior.

    O script tambem exige uma arvore de trabalho limpa, o branch esperado e o
    HEAD ja publicado no branch remoto antes de criar uma tag anotada e
    envia-la ao repositorio remoto.

.EXAMPLE
    .\deploy\windows\New-PSPanelReleaseTag.ps1 -WhatIf

.EXAMPLE
    .\deploy\windows\New-PSPanelReleaseTag.ps1
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
    [string] $Branch = 'main'
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

    $output = @(& $script:GitPath -C $script:ResolvedProjectRoot @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    if (-not $Quiet) {
        $output | ForEach-Object { Write-Host ([string]$_) }
    }

    if ($exitCode -ne 0) {
        throw "Comando Git falhou com codigo ${exitCode}: git $($Arguments -join ' ')"
    }

    return @($output | ForEach-Object { [string]$_ })
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

$tagName = $currentRelease.Value
$tagMessage = "Release $tagName"
$target = "$Remote/$tagName no commit $headCommit"

if (-not $PSCmdlet.ShouldProcess($target, 'criar tag anotada e publicar no repositorio remoto')) {
    Write-Host "Plano validado: criar e publicar $tagName no commit $headCommit."
    Write-Host 'Nenhuma tag foi criada.'
    return
}

[void](Invoke-GitCommand -Arguments @('tag', '-a', $tagName, '-m', $tagMessage, $headCommit))

try {
    [void](Invoke-GitCommand -Arguments @('push', $Remote, "refs/tags/$tagName"))
} catch {
    throw "A tag local $tagName foi criada, mas o push falhou. Corrija o acesso remoto e execute: git push $Remote refs/tags/$tagName"
}

[pscustomobject]@{
    Success = $true
    Tag = $tagName
    Commit = $headCommit
    Remote = $Remote
    Branch = $Branch
    Published = $true
}
