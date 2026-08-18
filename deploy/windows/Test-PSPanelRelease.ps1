<#
.SYNOPSIS
Valida localmente uma release do PS Panel antes da criacao da tag Git.

.DESCRIPTION
Confere a estrutura do projeto e as ferramentas homologadas, instala as
dependencias exatamente como registradas no package-lock.json, executa a suite
automatizada e valida a sintaxe dos arquivos JavaScript e PowerShell rastreados
pelo Git.

O script nao inicia a aplicacao ou o worker, nao acessa o arquivo .env, nao
executa scripts de scripts-ps e nao altera bancos, servicos ou tarefas
agendadas. O npm ci recria somente as dependencias locais em node_modules.
Durante a validacao, a codificacao do console e normalizada para UTF-8 e os
valores anteriores sao restaurados ao final.

.PARAMETER ProjectRoot
Diretorio raiz do clone Git do PS Panel. Por padrao, usa a raiz relativa a este
script.

.PARAMETER RequiredNodeVersion
Versao exata e homologada do Node.js, incluindo o prefixo "v". O valor padrao
acompanha a versao esperada pelo atualizador de producao.

.INPUTS
None. Este script nao aceita entrada pelo pipeline.

.OUTPUTS
Mensagens de progresso e um resumo em portugues. Retorna codigo zero em caso de
sucesso e codigo diferente de zero na primeira falha.

.EXAMPLE
PS> .\deploy\windows\Test-PSPanelRelease.ps1

Valida o projeto atual usando a versao homologada padrao do Node.js.

.EXAMPLE
PS> .\deploy\windows\Test-PSPanelRelease.ps1 -RequiredNodeVersion v24.15.0

Valida o projeto exigindo explicitamente o Node.js v24.15.0.

.NOTES
Execute este comando na estacao DEV antes de criar a tag de release. Git,
node.exe e npm.cmd devem estar disponiveis no PATH.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ProjectRoot = (Join-Path $PSScriptRoot '..\..'),

    [Parameter()]
    [ValidatePattern('^v\d+\.\d+\.\d+$')]
    [string]$RequiredNodeVersion = 'v24.18.0'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Write-ValidationStep {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ("[{0}/6] {1}" -f $Number, $Message) -ForegroundColor Cyan
}

function Get-RequiredCommandPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if (-not $command) {
        throw "Comando obrigatorio nao encontrado no PATH: $Name"
    }

    return $command.Source
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [switch]$CaptureOutput
    )

    Push-Location -LiteralPath $WorkingDirectory
    try {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $output = @(& $FilePath @ArgumentList 2>&1)
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
    }
    finally {
        Pop-Location
    }

    if ($exitCode -ne 0) {
        foreach ($line in $output) {
            Write-Host $line
        }

        throw "O comando '$([System.IO.Path]::GetFileName($FilePath))' falhou com codigo $exitCode."
    }

    if ($CaptureOutput) {
        return @($output | ForEach-Object { $_.ToString() })
    }

    foreach ($line in $output) {
        Write-Host $line
    }
}

function Get-GitOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ArgumentList
    )

    return @(Invoke-NativeCommand `
        -FilePath $script:GitPath `
        -ArgumentList (@('-C', $script:ResolvedProjectRoot) + $ArgumentList) `
        -WorkingDirectory $script:ResolvedProjectRoot `
        -CaptureOutput)
}

function Resolve-TrackedFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    $candidate = [System.IO.Path]::GetFullPath(
        (Join-Path $script:ResolvedProjectRoot $RelativePath)
    )
    $rootPrefix = $script:ResolvedProjectRoot.TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ) + [System.IO.Path]::DirectorySeparatorChar

    if (-not $candidate.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "O Git retornou um caminho fora da raiz do projeto: $RelativePath"
    }

    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Arquivo rastreado pelo Git nao encontrado: $RelativePath"
    }

    return $candidate
}

function Assert-ProjectStructure {
    $requiredFiles = @(
        'app.js',
        'package.json',
        'package-lock.json'
    )
    $requiredDirectories = @(
        'src',
        'views',
        'public',
        'scripts-js',
        'scripts-ps',
        'test',
        'deploy\windows'
    )

    foreach ($relativePath in $requiredFiles) {
        $path = Join-Path $script:ResolvedProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Arquivo obrigatorio nao encontrado: $relativePath"
        }
    }

    foreach ($relativePath in $requiredDirectories) {
        $path = Join-Path $script:ResolvedProjectRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            throw "Diretorio obrigatorio nao encontrado: $relativePath"
        }
    }

    $insideWorkTree = @(Get-GitOutput -ArgumentList @('rev-parse', '--is-inside-work-tree'))
    if ($insideWorkTree.Count -ne 1 -or $insideWorkTree[0].Trim() -ne 'true') {
        throw 'A raiz informada nao pertence a uma arvore de trabalho Git valida.'
    }
}

function Assert-JavaScriptSyntax {
    $trackedFiles = @(Get-GitOutput -ArgumentList @('ls-files', '--', '*.js')) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

    if ($trackedFiles.Count -eq 0) {
        throw 'Nenhum arquivo JavaScript rastreado pelo Git foi encontrado.'
    }

    foreach ($relativePath in $trackedFiles) {
        $fullPath = Resolve-TrackedFilePath -RelativePath $relativePath
        Invoke-NativeCommand `
            -FilePath $script:NodePath `
            -ArgumentList @('--check', $fullPath) `
            -WorkingDirectory $script:ResolvedProjectRoot
    }

    return $trackedFiles.Count
}

function Assert-PowerShellSyntax {
    $trackedFiles = @(Get-GitOutput -ArgumentList @('ls-files', '--', '*.ps1')) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique

    if ($trackedFiles.Count -eq 0) {
        throw 'Nenhum script PowerShell rastreado pelo Git foi encontrado.'
    }

    foreach ($relativePath in $trackedFiles) {
        $fullPath = Resolve-TrackedFilePath -RelativePath $relativePath
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $fullPath,
            [ref]$tokens,
            [ref]$parseErrors
        ) | Out-Null

        if (@($parseErrors).Count -gt 0) {
            $details = @($parseErrors | ForEach-Object {
                "linha $($_.Extent.StartLineNumber), coluna $($_.Extent.StartColumnNumber): $($_.Message)"
            }) -join '; '
            throw "Erro de sintaxe em '$relativePath': $details"
        }
    }

    return $trackedFiles.Count
}

$previousConsoleInputEncoding = [Console]::InputEncoding
$previousConsoleOutputEncoding = [Console]::OutputEncoding
$previousOutputEncoding = $OutputEncoding
$previousConsoleCodePage = $previousConsoleInputEncoding.CodePage
$utf8Encoding = [System.Text.UTF8Encoding]::new($false)
$validationExitCode = 1

try {
    chcp 65001 | Out-Null
    [Console]::InputEncoding = $utf8Encoding
    [Console]::OutputEncoding = $utf8Encoding
    $OutputEncoding = $utf8Encoding

    $startedAt = Get-Date
    $script:ResolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

    Write-Host 'Validacao local da release do PS Panel' -ForegroundColor Green
    Write-Host "Raiz do projeto: $script:ResolvedProjectRoot"

    Write-ValidationStep -Number 1 -Message 'Validando estrutura e ferramentas obrigatorias...'
    $script:NodePath = Get-RequiredCommandPath -Name 'node.exe'
    $script:NpmPath = Get-RequiredCommandPath -Name 'npm.cmd'
    $script:GitPath = Get-RequiredCommandPath -Name 'git.exe'
    Assert-ProjectStructure

    Write-ValidationStep -Number 2 -Message 'Validando a versao homologada do Node.js...'
    $nodeVersionOutput = @(Invoke-NativeCommand `
        -FilePath $script:NodePath `
        -ArgumentList @('--version') `
        -WorkingDirectory $script:ResolvedProjectRoot `
        -CaptureOutput)
    $nodeVersion = ($nodeVersionOutput | Select-Object -First 1).Trim()
    if ($nodeVersion -ne $RequiredNodeVersion) {
        throw "Versao do Node.js incompativel. Esperada: $RequiredNodeVersion. Encontrada: $nodeVersion."
    }

    $trackedStateBefore = @(Get-GitOutput -ArgumentList @('status', '--porcelain', '--untracked-files=no'))

    Write-ValidationStep -Number 3 -Message 'Instalando dependencias com npm ci...'
    Invoke-NativeCommand `
        -FilePath $script:NpmPath `
        -ArgumentList @('ci') `
        -WorkingDirectory $script:ResolvedProjectRoot

    Write-ValidationStep -Number 4 -Message 'Executando a suite automatizada com npm test...'
    Invoke-NativeCommand `
        -FilePath $script:NpmPath `
        -ArgumentList @('test') `
        -WorkingDirectory $script:ResolvedProjectRoot

    Write-ValidationStep -Number 5 -Message 'Validando arquivos JavaScript rastreados pelo Git...'
    $javaScriptFileCount = Assert-JavaScriptSyntax

    Write-ValidationStep -Number 6 -Message 'Validando scripts PowerShell rastreados pelo Git...'
    $powerShellFileCount = Assert-PowerShellSyntax

    $trackedStateAfter = @(Get-GitOutput -ArgumentList @('status', '--porcelain', '--untracked-files=no'))
    if (@(Compare-Object -ReferenceObject $trackedStateBefore -DifferenceObject $trackedStateAfter).Count -gt 0) {
        throw 'A validacao alterou arquivos rastreados pelo Git. Revise a arvore de trabalho antes de criar a tag.'
    }

    $elapsed = (Get-Date) - $startedAt
    Write-Host ''
    Write-Host 'VALIDACAO CONCLUIDA COM SUCESSO' -ForegroundColor Green
    Write-Host "Node.js: $nodeVersion"
    Write-Host "Testes automatizados: aprovados"
    Write-Host "JavaScript verificado: $javaScriptFileCount arquivo(s)"
    Write-Host "PowerShell verificado: $powerShellFileCount script(s), somente sintaxe"
    Write-Host ("Duracao: {0:mm\:ss}" -f $elapsed)
    $validationExitCode = 0
}
catch {
    Write-Host ''
    Write-Host 'VALIDACAO INTERROMPIDA' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host 'A tag de release nao deve ser criada enquanto esta falha existir.' -ForegroundColor Yellow
}
finally {
    chcp $previousConsoleCodePage | Out-Null
    [Console]::InputEncoding = $previousConsoleInputEncoding
    [Console]::OutputEncoding = $previousConsoleOutputEncoding
    $OutputEncoding = $previousOutputEncoding
}

exit $validationExitCode
