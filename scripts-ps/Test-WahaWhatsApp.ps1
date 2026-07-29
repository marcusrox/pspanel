<#
.SYNOPSIS
    Envia uma mensagem de teste pelo WhatsApp usando a API do WAHA.

.DESCRIPTION
    Envia uma mensagem de texto por POST /api/sendText. O destino pode ser um
    numero em formato internacional, somente com digitos, ou um chatId completo
    do WAHA, como 5511999999999@c.us ou 120363000000000000@g.us.

.PARAMETER ApiKey
    Chave de acesso configurada no WAHA. O valor e enviado no header X-Api-Key.

.PARAMETER Destino
    Numero com codigo do pais, como 5511999999999, ou chatId completo do WAHA.

.PARAMETER Mensagem
    Texto que sera enviado ao destinatario.

.PARAMETER Session
    Nome da sessao ativa no WAHA. O valor padrao e default.

.PARAMETER WahaUrl
    URL base da instalacao WAHA, sem necessidade de informar /api/sendText.

.PARAMETER TimeoutSeconds
    Tempo limite da chamada HTTP em segundos. O valor padrao e 30.

.EXAMPLE
    .\Test-WahaWhatsApp.ps1 -ApiKey 'sua-chave' -Destino '5511999999999' -Mensagem 'Teste pelo PS Panel'

.EXAMPLE
    .\Test-WahaWhatsApp.ps1 -ApiKey 'sua-chave' -Destino '120363000000000000@g.us' -Mensagem 'Teste no grupo' -Session 'default'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiKey,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destino,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Mensagem,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Session = 'default',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$WahaUrl = 'https://waha.idevsolutions.com.br',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 300)]
    [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ($null -ne (Get-Variable -Name PSStyle -ErrorAction SilentlyContinue)) {
    $PSStyle.OutputRendering = 'PlainText'
}

function ConvertTo-WahaChatId {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $normalizedValue = $Value.Trim()
    if ($normalizedValue -match '^[0-9]+@(c\.us|g\.us|lid|newsletter)$' -or $normalizedValue -eq 'status@broadcast') {
        return $normalizedValue
    }

    $phoneNumber = $normalizedValue -replace '[^0-9]', ''
    if ($phoneNumber -notmatch '^[0-9]{10,15}$') {
        throw 'Destino invalido. Informe o numero com codigo do pais ou um chatId completo do WAHA.'
    }

    return "$phoneNumber@c.us"
}

function Get-WahaErrorDetail {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $true)]
        [string]$SensitiveValue
    )

    $detail = $null
    if ($null -ne $ErrorRecord.ErrorDetails -and
        -not [string]::IsNullOrWhiteSpace($ErrorRecord.ErrorDetails.Message)) {
        $detail = $ErrorRecord.ErrorDetails.Message
    }
    else {
        $responseProperty = $ErrorRecord.Exception.PSObject.Properties['Response']
        $response = if ($null -ne $responseProperty) { $responseProperty.Value } else { $null }
        $contentProperty = if ($null -ne $response) { $response.PSObject.Properties['Content'] } else { $null }
        $responseContent = if ($null -ne $contentProperty) { $contentProperty.Value } else { $null }

        if ($null -ne $responseContent) {
            try {
                $detail = $responseContent.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            catch {
                $detail = $null
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$detail)) {
        return $null
    }

    $safeDetail = ([string]$detail).Trim()
    if (-not [string]::IsNullOrEmpty($SensitiveValue)) {
        $safeDetail = $safeDetail.Replace($SensitiveValue, '********')
    }
    if ($safeDetail.Length -gt 2000) {
        $safeDetail = $safeDetail.Substring(0, 2000)
    }

    return $safeDetail
}

$baseUri = $null
if (-not [Uri]::TryCreate($WahaUrl.Trim(), [UriKind]::Absolute, [ref]$baseUri) -or
    $baseUri.Scheme -notin @('http', 'https')) {
    throw 'WahaUrl invalida. Informe uma URL absoluta iniciada por http:// ou https://.'
}

$baseUrl = $WahaUrl.Trim().TrimEnd('/')
$sessionName = $Session.Trim()
$escapedSession = [Uri]::EscapeDataString($sessionName)
$headers = @{
    'X-Api-Key' = $ApiKey
    'Accept'    = 'application/json'
}

try {
    $sessionInfo = Invoke-RestMethod `
        -Uri "$baseUrl/api/sessions/$escapedSession" `
        -Method Get `
        -Headers $headers `
        -TimeoutSec $TimeoutSeconds

    $statusProperty = if ($null -ne $sessionInfo) { $sessionInfo.PSObject.Properties['status'] } else { $null }
    $sessionStatus = if ($null -ne $statusProperty) { [string]$statusProperty.Value } else { '' }
    if ($sessionStatus -ne 'WORKING') {
        $displayStatus = if ([string]::IsNullOrWhiteSpace($sessionStatus)) { 'desconhecido' } else { $sessionStatus }
        throw "A sessao '$sessionName' nao esta pronta para envio. Status atual: $displayStatus; esperado: WORKING."
    }

    $chatId = ConvertTo-WahaChatId -Value $Destino
    $normalizedDestination = $Destino.Trim()
    if ($normalizedDestination -notmatch '@') {
        $phoneNumber = $normalizedDestination -replace '[^0-9]', ''
        $escapedPhone = [Uri]::EscapeDataString($phoneNumber)
        $contactInfo = Invoke-RestMethod `
            -Uri "$baseUrl/api/contacts/check-exists?phone=$escapedPhone&session=$escapedSession" `
            -Method Get `
            -Headers $headers `
            -TimeoutSec $TimeoutSeconds

        $existsProperty = if ($null -ne $contactInfo) { $contactInfo.PSObject.Properties['numberExists'] } else { $null }
        $contactExists = $null -ne $existsProperty -and [bool]$existsProperty.Value
        if (-not $contactExists) {
            throw 'O numero informado nao foi encontrado no WhatsApp pela sessao selecionada.'
        }

        $chatIdProperty = $contactInfo.PSObject.Properties['chatId']
        if ($null -eq $chatIdProperty -or [string]::IsNullOrWhiteSpace([string]$chatIdProperty.Value)) {
            throw 'O WAHA confirmou o numero, mas nao retornou o chatId necessario para o envio.'
        }
        $chatId = [string]$chatIdProperty.Value
    }

    $requestBody = @{
        session = $sessionName
        chatId  = $chatId
        text    = $Mensagem
    } | ConvertTo-Json -Depth 3

    $response = Invoke-RestMethod `
        -Uri "$baseUrl/api/sendText" `
        -Method Post `
        -Headers $headers `
        -ContentType 'application/json; charset=utf-8' `
        -Body ([System.Text.Encoding]::UTF8.GetBytes($requestBody)) `
        -TimeoutSec $TimeoutSeconds

    $messageId = $null
    $idProperty = if ($null -ne $response) { $response.PSObject.Properties['id'] } else { $null }
    if ($null -ne $idProperty) {
        if ($idProperty.Value -is [string]) {
            $messageId = $idProperty.Value
        }
        elseif ($null -ne $idProperty.Value) {
            $serializedProperty = $idProperty.Value.PSObject.Properties['_serialized']
            if ($null -ne $serializedProperty) {
                $messageId = $serializedProperty.Value
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$messageId)) {
        Write-Output "Mensagem de teste enviada com sucesso para $chatId pela sessao '$sessionName'."
    }
    else {
        Write-Output "Mensagem de teste enviada com sucesso para $chatId pela sessao '$sessionName'. ID: $messageId"
    }
}
catch {
    $statusCode = $null
    $errorDetail = Get-WahaErrorDetail -ErrorRecord $_ -SensitiveValue $ApiKey
    $responseProperty = $_.Exception.PSObject.Properties['Response']
    $errorResponse = if ($null -ne $responseProperty) { $responseProperty.Value } else { $null }
    if ($null -ne $errorResponse) {
        try {
            $statusCode = [int]$errorResponse.StatusCode
        }
        catch {
            $statusCode = $null
        }
    }

    if ($null -ne $statusCode) {
        $detailText = if ([string]::IsNullOrWhiteSpace([string]$errorDetail)) {
            $_.Exception.Message
        }
        else {
            $errorDetail
        }
        throw "Falha ao enviar mensagem pelo WAHA. HTTP $statusCode. Detalhes: $detailText"
    }

    throw "Falha ao enviar mensagem pelo WAHA. $($_.Exception.Message)"
}
