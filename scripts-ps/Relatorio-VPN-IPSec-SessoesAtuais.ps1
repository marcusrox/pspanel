<#
.SYNOPSIS
    Envia o relatorio de sessoes atuais de usuarios VPN IPsec pela API do FortiGate.

.DESCRIPTION
    Consulta GET /api/v2/monitor/vpn/ipsec por HTTPS, seleciona apenas sessoes
    dial-up com usuario identificado e envia um relatorio HTML por e-mail.
    Nao utiliza SSH nem comandos diagnose.

.PARAMETER FortiApiToken
    Token de um administrador REST API com permissao somente de leitura.

.PARAMETER FortiGateIP
    Endereco IP ou nome do FortiGate.

.PARAMETER FortiGatePort
    Porta HTTPS administrativa do FortiGate. O valor padrao e 4443.

.PARAMETER Vdom
    VDOM consultado. O valor padrao e root.

.PARAMETER ValidacaoCertificado
    O valor padrao e Ignorar, destinado ao certificado interno previamente verificado.

.PARAMETER MailTo
    Destinatario do relatorio por e-mail. O valor padrao e analistasusi@desenbahia.ba.gov.br.

.EXAMPLE
    .\Relatorio-VPN-IPSec-SessoesAtuais.ps1 -FortiApiToken "token-ficticio"
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiApiToken,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiGateIP = '10.35.0.1',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 65535)]
    [int]$FortiGatePort = 4443,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Vdom = 'root',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Validar', 'Ignorar')]
    [string]$ValidacaoCertificado = 'Ignorar',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$MailTo = 'analistasusi@desenbahia.ba.gov.br'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1') -Force -ErrorAction Stop

$ApiTimeoutSeconds = 90

function Encode-Html {
    param([AllowNull()][object]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function Get-ObjectValue {
    param([AllowNull()][object]$Object, [string[]]$Names)

    if ($null -eq $Object) { return $null }
    foreach ($name in $Names) {
        if ($Object -is [System.Collections.IDictionary]) {
            foreach ($key in $Object.Keys) {
                if ([string]$key -ieq $name) { return $Object[$key] }
            }
        }
        else {
            $property = $Object.PSObject.Properties[$name]
            if ($null -ne $property) { return $property.Value }
        }
    }
    return $null
}

function Test-MeaningfulValue {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return $false }
    return [string]$Value -notmatch '^(?i:N/A|unknown|anonymous|-)$'
}

function Get-AuthenticatedUsername {
    param([AllowNull()][object]$Session)

    # XAuth (IKEv1) e EAP (IKEv2) representam o login efetivamente autenticado.
    # O campo username fica por ultimo porque algumas versoes o usam para a
    # identidade do peer e podem retornar um endereco IP nesse campo.
    return Get-ObjectValue -Object $Session -Names @(
        'xauthuser', 'xauth_user', 'xauth-user',
        'eapuser', 'eap_user', 'eap-user',
        'authuser', 'auth_user', 'auth-user',
        'user_name', 'user-name', 'login',
        'username', 'user'
    )
}

function Find-IpsecSessionCandidates {
    param([AllowNull()][object]$Value, [int]$Depth = 0)

    if ($null -eq $Value -or $Depth -gt 8 -or $Value -is [string] -or $Value -is [ValueType]) { return }

    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary] -and $Value -isnot [PSCustomObject]) {
        foreach ($item in $Value) { Find-IpsecSessionCandidates -Value $item -Depth ($Depth + 1) }
        return
    }

    $username = Get-AuthenticatedUsername -Session $Value
    $hasSessionMarker = $null -ne (Get-ObjectValue -Object $Value -Names @(
        'creation_time', 'rgwy', 'tun_id', 'tun_id6', 'dialup_index', 'connection_count'
    ))
    if ((Test-MeaningfulValue $username) -and $hasSessionMarker) {
        Write-Output $Value
    }

    $properties = if ($Value -is [System.Collections.IDictionary]) {
        @($Value.Keys | ForEach-Object { $Value[$_] })
    }
    else {
        @($Value.PSObject.Properties | ForEach-Object { $_.Value })
    }

    foreach ($child in $properties) {
        if ($null -ne $child -and $child -isnot [string] -and $child -isnot [ValueType]) {
            Find-IpsecSessionCandidates -Value $child -Depth ($Depth + 1)
        }
    }
}

function Invoke-FortiApiGet {
    param([string]$Uri)

    $request = @{
        Uri = $Uri
        Method = 'Get'
        Headers = @{
            Accept = 'application/json'
            Authorization = "Bearer $FortiApiToken"
        }
        TimeoutSec = $ApiTimeoutSeconds
        ErrorAction = 'Stop'
    }

    $previousCertificateCallback = $null
    $certificateCallbackChanged = $false
    if ($ValidacaoCertificado -eq 'Ignorar') {
        $command = Get-Command Invoke-RestMethod
        if ($command.Parameters.ContainsKey('SkipCertificateCheck')) {
            $request.SkipCertificateCheck = $true
        }
        else {
            $previousCertificateCallback = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
            $certificateCallbackChanged = $true
        }
    }

    try { return Invoke-RestMethod @request }
    finally {
        if ($certificateCallbackChanged) {
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $previousCertificateCallback
        }
    }
}

function Get-FortiApiBaseUrl {
    $portPart = if ($FortiGatePort -eq 443) { '' } else { ":$FortiGatePort" }
    return "https://$FortiGateIP$portPart"
}

function Get-ActiveIpsecApiResponse {
    $baseUrl = Get-FortiApiBaseUrl
    $encodedVdom = [uri]::EscapeDataString($Vdom)
    $uri = "$baseUrl/api/v2/monitor/vpn/ipsec?vdom=$encodedVdom"
    return Invoke-FortiApiGet -Uri $uri
}

function ConvertTo-ActiveSessionRows {
    param([AllowNull()][object]$Response, [datetime]$CollectedAt)

    $status = Get-ObjectValue -Object $Response -Names @('status')
    if ($status -and [string]$status -notmatch '^(?i)success$') {
        throw "A API de monitoramento retornou status inesperado: $status."
    }

    $candidates = @(Find-IpsecSessionCandidates -Value $Response)
    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = @{}

    foreach ($candidate in $candidates) {
        $username = Get-AuthenticatedUsername -Session $candidate
        if (-not (Test-MeaningfulValue $username)) { continue }

        $type = Get-ObjectValue -Object $candidate -Names @('type', 'tunnel_type', 'wizard-type')
        $dialupIndex = Get-ObjectValue -Object $candidate -Names @('dialup_index', 'dialup-index')
        if ((Test-MeaningfulValue $type) -and [string]$type -notmatch '(?i)dialup|dynamic' -and $null -eq $dialupIndex) {
            continue
        }

        $name = Get-ObjectValue -Object $candidate -Names @('name', 'parent', 'p1name')
        $remoteGateway = Get-ObjectValue -Object $candidate -Names @('rgwy', 'remote_gateway', 'remote-gw')
        $clientIp = Get-ObjectValue -Object $candidate -Names @('tun_id', 'tun_id6', 'assigned_ip', 'assignip')
        $key = "$username|$name|$remoteGateway|$clientIp|$dialupIndex"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $uptimeSeconds = 0L
        $creationTime = Get-ObjectValue -Object $candidate -Names @('creation_time', 'uptime')
        if ($null -ne $creationTime) { [void][int64]::TryParse([string]$creationTime, [ref]$uptimeSeconds) }
        $startTime = if ($uptimeSeconds -gt 0) { $CollectedAt.AddSeconds(-$uptimeSeconds) } else { $null }
        $duration = if ($uptimeSeconds -gt 0) { [TimeSpan]::FromSeconds($uptimeSeconds).ToString('d\.hh\:mm\:ss') } else { '' }

        $state = Get-ObjectValue -Object $candidate -Names @('status', 'state', 'run_state')
        if (-not (Test-MeaningfulValue $state)) { $state = 'up' }

        $rows.Add([PSCustomObject]@{
            Usuario = [string]$username
            Inicio = $startTime
            Duracao = $duration
            IPOrigem = [string]$remoteGateway
            IPCliente = [string]$clientIp
            Tunel = [string]$name
            Tipo = [string]$type
            Estado = [string]$state
        })
    }

    return @($rows | Sort-Object Usuario, Inicio)
}

function New-ActiveSessionsReportHtml {
    param([object[]]$Rows, [datetime]$CollectedAt)

    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $sentAtText = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">')
    [void]$builder.Append('<h1 style="color:#1a365d;font-size:22px;">Sessões atuais de usuários VPN IPsec</h1>')
    [void]$builder.Append("<p>Coleta: <strong>$(Encode-Html $CollectedAt.ToString('dd/MM/yyyy HH:mm:ss'))</strong><br>FortiGate: <strong>$(Encode-Html $FortiGateIP)</strong><br>Sessões: <strong>$(@($Rows).Count)</strong></p>")

    if (@($Rows).Count -eq 0) {
        [void]$builder.Append('<p style="padding:12px;background:#f7fafc;border:1px solid #e2e8f0;">Nenhuma sessão de usuário encontrada.</p>')
    }
    else {
        [void]$builder.Append('<table style="border-collapse:collapse;width:100%;max-width:1050px;border:1px solid #ccc;font-size:12px;line-height:1.2;"><thead><tr style="background:#1a365d;color:#fff;text-align:left;">')
        foreach ($label in @('Usuário', 'Início', 'Duração', 'IP de origem', 'IP do cliente', 'Túnel', 'Tipo', 'Estado')) {
            [void]$builder.Append(('<th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">{0}</th>' -f (Encode-Html $label)))
        }
        [void]$builder.Append('</tr></thead><tbody>')
        foreach ($row in $Rows) {
            $startText = if ($null -eq $row.Inicio) { '—' } else { $row.Inicio.ToString('dd/MM/yyyy HH:mm:ss') }
            [void]$builder.Append('<tr>')
            foreach ($value in @($row.Usuario, $startText, $row.Duracao, $row.IPOrigem, $row.IPCliente, $row.Tunel, $row.Tipo, $row.Estado)) {
                $displayValue = if ([string]::IsNullOrWhiteSpace([string]$value)) { '—' } else { $value }
                [void]$builder.Append(('<td style="padding:4px 6px;border:1px solid #e2e8f0;">{0}</td>' -f (Encode-Html $displayValue)))
            }
            [void]$builder.Append('</tr>')
        }
        [void]$builder.Append('</tbody></table>')
    }

    [void]$builder.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #e2e8f0;color:#718096;font-size:12px;line-height:1.5;"">Enviado em: <strong>$(Encode-Html $sentAtText)</strong><br>Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(Encode-Html $routineName)</strong></div>")
    [void]$builder.Append('</body></html>')
    return $builder.ToString()
}

try {
    $collectedAt = Get-Date
    Write-Host 'Consultando sessoes atuais VPN IPsec pela API...'
    $response = Get-ActiveIpsecApiResponse
    $rows = @(ConvertTo-ActiveSessionRows -Response $response -CollectedAt $collectedAt)
    $html = New-ActiveSessionsReportHtml -Rows $rows -CollectedAt $collectedAt
    Send-PSPanelEmail -To $MailTo -Subject "[PSPanel] Sessões atuais na VPN IPsec - $($collectedAt.ToString('dd/MM/yyyy'))" -Body $html -BodyAsHtml
    Write-Host "Relatorio de sessoes atuais enviado com sucesso. Sessoes: $($rows.Count)."
    exit 0
}
catch {
    Write-Error "Falha ao gerar o relatorio de sessoes atuais VPN IPsec: $($_.Exception.Message)"
    exit 1
}
