<#
.SYNOPSIS
    Script de prova com parâmetros de aplicação e ambiente.

.DESCRIPTION
    Valida o fluxo do painel com parâmetros obrigatórios similares a um deploy: nome da aplicação
    e ambiente (INTERNO ou EXTERNO). Apenas escreve sucesso na saída.

.PARAMETER appName
    Nome lógico da aplicação (texto livre, obrigatório).

.PARAMETER AMBIENTE
    Ambiente alvo. Valores permitidos: INTERNO ou EXTERNO.

.EXAMPLE
    & '.\Proof-Test - Copia.ps1' -appName "MinhaApp" -AMBIENTE "INTERNO"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$appName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("INTERNO", "EXTERNO")]
    [string]$AMBIENTE
)

Write-Output "Script executado com sucesso!"
