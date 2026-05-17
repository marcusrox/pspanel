param(
    [Parameter(Mandatory=$true)]
    [string]$Name,

    [string]$Optional
)

Write-Output "Name=$Name"
Write-Output "Optional=$Optional"