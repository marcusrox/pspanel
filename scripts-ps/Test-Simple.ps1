<#
.SYNOPSIS
    Exemplo simples de saudação com parâmetro opcional.

.DESCRIPTION
    Escreve uma saudação no console, a hora atual e o diretório do script. Serve para validar
    passagem de parâmetros pelo painel PS Panel.

.PARAMETER Name
    Nome a incluir na saudação. Padrão: World.

.EXAMPLE
    .\Test-Simple.ps1

.EXAMPLE
    .\Test-Simple.ps1 -Name "PSPanel"
#>
param(
    [string]$Name = "World"
)

Write-Host "Hello, $Name!"
Write-Host "Current time is: $(Get-Date)"
Write-Host "Script is running from: $PSScriptRoot" 