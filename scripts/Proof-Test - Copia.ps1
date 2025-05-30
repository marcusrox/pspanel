param(
    [Parameter(Mandatory = $true)]
    [string]$appName,
    
    [Parameter(Mandatory = $true)]
    [ValidateSet("INTERNO", "EXTERNO")]
    [string]$AMBIENTE
)

Write-Output "Script executado com sucesso!"