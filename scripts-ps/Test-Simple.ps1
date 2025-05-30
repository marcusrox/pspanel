param(
    [string]$Name = "World"
)

Write-Host "Hello, $Name!"
Write-Host "Current time is: $(Get-Date)"
Write-Host "Script is running from: $PSScriptRoot" 