<#
.SYNOPSIS
    Envia o relatorio diario de conexoes de usuarios VPN IPsec pela API do FortiGate.

.DESCRIPTION
    Consulta a Log API do FortiGate por HTTPS, pagina todos os eventos encontrados
    para a data selecionada, filtra conexoes IPsec com action=tunnel-up e envia um
    relatorio HTML por e-mail. Nao utiliza SSH nem execute log display.

.PARAMETER FortiApiToken
    Token de um administrador REST API com permissao somente de leitura.

.PARAMETER FortiGateIP
    Endereco IP ou nome do FortiGate.

.PARAMETER FortiGatePort
    Porta HTTPS administrativa do FortiGate. O valor padrao e 4443.

.PARAMETER Vdom
    VDOM consultado. O valor padrao e root.

.PARAMETER DataRelatorio
    Data no formato yyyy-MM-dd. Quando omitida, usa a data atual.

.PARAMETER LogApiPath
    Caminho da Log API. Pode ser ajustado conforme a versao do FortiOS.

.PARAMETER ValidacaoCertificado
    O valor padrao e Ignorar, destinado ao certificado interno previamente verificado.

.PARAMETER MailTo
    Destinatario do relatorio por e-mail. O valor padrao e analistasusi@desenbahia.ba.gov.br.

.EXAMPLE
    .\Relatorio-VPN-IPSec-Historico.ps1 -FortiApiToken "token-ficticio"

.EXAMPLE
    .\Relatorio-VPN-IPSec-Historico.ps1 -FortiApiToken "token-ficticio" -DataRelatorio "2026-07-13"
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
    [ValidatePattern('^\d{4}-\d{2}-\d{2}$')]
    [string]$DataRelatorio = (Get-Date).ToString('yyyy-MM-dd'),

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^/api/v2/log/[A-Za-z0-9/_-]+$')]
    [string]$LogApiPath = '/api/v2/log/disk/event/vpn',

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

$ApiPageSize = 200
$ApiMaxPages = 100
$ApiMaxPollAttempts = 45
$ApiPollIntervalSeconds = 2
$ApiTimeoutSeconds = 90

function Encode-Html {
    param([AllowNull()][object]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}

function ConvertTo-ReportDate {
    param([string]$Value)

    $parsed = [datetime]::MinValue
    if (-not [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )) {
        throw 'DataRelatorio invalida. Informe uma data existente no formato yyyy-MM-dd.'
    }

    return [datetime]::SpecifyKind($parsed.Date, [System.DateTimeKind]::Unspecified)
}

function ConvertFrom-FortiKeyValueLine {
    param([string]$Line)

    $fields = @{}
    $pattern = '(?<key>[A-Za-z0-9_.-]+)=(?:"(?<quoted>(?:\\.|[^"])*)"|(?<plain>\S+))'
    foreach ($match in [regex]::Matches($Line, $pattern)) {
        $value = if ($match.Groups['quoted'].Success) {
            $match.Groups['quoted'].Value -replace '\\"', '"' -replace '\\\\', '\'
        }
        else {
            $match.Groups['plain'].Value
        }
        $fields[$match.Groups['key'].Value.ToLowerInvariant()] = $value
    }
    return $fields
}

function ConvertTo-FieldMap {
    param([AllowNull()][object]$Record)

    if ($null -eq $Record) { return @{} }
    if ($Record -is [string]) { return ConvertFrom-FortiKeyValueLine -Line $Record }

    foreach ($rawName in @('raw', 'raw_log', 'message')) {
        $rawProperty = $Record.PSObject.Properties[$rawName]
        if ($null -ne $rawProperty -and $rawProperty.Value -is [string] -and $rawProperty.Value -match '\bdate=') {
            return ConvertFrom-FortiKeyValueLine -Line ([string]$rawProperty.Value)
        }
    }

    $fields = @{}
    if ($Record -is [System.Collections.IDictionary]) {
        foreach ($key in $Record.Keys) {
            $fields[[string]$key.ToString().ToLowerInvariant()] = $Record[$key]
        }
        return $fields
    }

    foreach ($property in $Record.PSObject.Properties) {
        $fields[$property.Name.ToLowerInvariant()] = $property.Value
    }
    return $fields
}

function Get-FieldValue {
    param([hashtable]$Fields, [string[]]$Names)

    foreach ($name in $Names) {
        $key = $name.ToLowerInvariant()
        if (-not $Fields.ContainsKey($key)) { continue }
        $value = [string]$Fields[$key]
        if (-not [string]::IsNullOrWhiteSpace($value) -and $value -notmatch '^(?:N/A|unknown|-)$') {
            return $value.Trim()
        }
    }
    return ''
}

function Get-ApiResultItems {
    param([AllowNull()][object]$Response)

    if ($null -eq $Response) { return @() }
    if ($Response -is [System.Array]) { return @($Response) }

    $resultsProperty = $Response.PSObject.Properties['results']
    if ($null -ne $resultsProperty) {
        $results = $resultsProperty.Value
        if ($null -ne $results) {
            $dataProperty = $results.PSObject.Properties['data']
            if ($null -ne $dataProperty) { return @($dataProperty.Value) }
            return @($results)
        }
    }

    foreach ($name in @('data', 'logs', 'entries')) {
        $property = $Response.PSObject.Properties[$name]
        if ($null -ne $property) { return @($property.Value) }
    }

    return @()
}

function Get-ResponsePropertyValue {
    param([AllowNull()][object]$Response, [string[]]$Names)

    if ($null -eq $Response) { return $null }
    foreach ($name in $Names) {
        $property = $Response.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Invoke-FortiApiGet {
    param([string]$Uri)

    $headers = @{
        Accept = 'application/json'
        Authorization = "Bearer $FortiApiToken"
    }
    $request = @{
        Uri = $Uri
        Method = 'Get'
        Headers = $headers
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

    try {
        return Invoke-RestMethod @request
    }
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

function Wait-FortiLogApiResponse {
    param([string]$Uri, [AllowNull()][object]$InitialResponse)

    $response = $InitialResponse
    $sessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')
    for ($attempt = 1; $attempt -le $ApiMaxPollAttempts; $attempt++) {
        $ready = Get-ResponsePropertyValue -Response $response -Names @('ready')
        if ($null -eq $ready -or $ready -eq $true -or [string]$ready -match '^(?i:true|1)$') {
            return $response
        }

        if ($null -eq $sessionId) {
            throw 'A Log API informou que a consulta nao esta pronta, mas nao retornou session_id.'
        }
        if ($attempt -eq $ApiMaxPollAttempts) { break }

        Write-Host "Aguardando a pesquisa de logs ficar pronta (tentativa $attempt de $ApiMaxPollAttempts)..."
        if ($ApiPollIntervalSeconds -gt 0) { Start-Sleep -Seconds $ApiPollIntervalSeconds }
        if ($Uri -match '(?i)[?&]session_id=') {
            $pollUri = $Uri
        }
        else {
            $separator = if ($Uri.Contains('?')) { '&' } else { '?' }
            $pollUri = "$Uri$separator`session_id=$([uri]::EscapeDataString([string]$sessionId))"
        }
        $response = Invoke-FortiApiGet -Uri $pollUri
        $newSessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')
        if ($null -ne $newSessionId) { $sessionId = $newSessionId }
    }

    throw "A pesquisa da Log API nao ficou pronta apos $ApiMaxPollAttempts tentativas."
}

function Get-FortiIpsecHistoryRecords {
    param([datetime]$ReportDate)

    $baseUrl = Get-FortiApiBaseUrl
    $encodedVdom = [uri]::EscapeDataString($Vdom)
    $dateFilter = [uri]::EscapeDataString("date==$($ReportDate.ToString('yyyy-MM-dd'))")
    $actionFilter = [uri]::EscapeDataString('action==tunnel-up')
    $allItems = [System.Collections.Generic.List[object]]::new()
    $start = 1
    $page = 0
    $completed = $false
    $sessionId = $null

    while ($page -lt $ApiMaxPages) {
        $page++
        $uri = "$baseUrl${LogApiPath}?vdom=$encodedVdom&start=$start&rows=$ApiPageSize&filter=$dateFilter&filter=$actionFilter"
        if ($null -ne $sessionId) {
            $uri += "&session_id=$([uri]::EscapeDataString([string]$sessionId))"
        }
        Write-Host "Consultando pagina $page da Log API..."
        $response = Invoke-FortiApiGet -Uri $uri
        $response = Wait-FortiLogApiResponse -Uri $uri -InitialResponse $response

        $responseSessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')
        if ($null -ne $responseSessionId) { $sessionId = $responseSessionId }

        $status = Get-ResponsePropertyValue -Response $response -Names @('status')
        if ($status -and [string]$status -notmatch '^(?i)success$') {
            throw "A Log API retornou status inesperado: $status."
        }

        $items = @(Get-ApiResultItems -Response $response)
        foreach ($item in $items) { $allItems.Add($item) }

        $nextIndex = Get-ResponsePropertyValue -Response $response -Names @('next_idx', 'next-index', 'next')
        $matchedCount = Get-ResponsePropertyValue -Response $response -Names @('matched_count', 'total_lines', 'total', 'total_count')
        $limitReached = Get-ResponsePropertyValue -Response $response -Names @('limit_reached')

        if ($null -ne $matchedCount -and $allItems.Count -ge [int64]$matchedCount) {
            $completed = $true
            break
        }
        if ($null -ne $nextIndex -and [int64]$nextIndex -gt $start) {
            $start = [int64]$nextIndex
            continue
        }
        if ($null -ne $matchedCount -and $allItems.Count -lt [int64]$matchedCount -and $items.Count -gt 0) {
            $start += $items.Count
            continue
        }
        if (($limitReached -eq $true -or [string]$limitReached -eq 'true') -and $items.Count -gt 0) {
            $start += $items.Count
            continue
        }
        if ($items.Count -ge $ApiPageSize) {
            $start += $items.Count
            continue
        }
        $completed = $true
        break
    }

    if (-not $completed) {
        throw "A Log API excedeu o limite de $ApiMaxPages paginas. Refine os filtros ou aumente o limite de forma controlada."
    }

    return @($allItems)
}

function ConvertTo-HistoryRows {
    param([object[]]$Records, [datetime]$ReportDate)

    $rows = [System.Collections.Generic.List[object]]::new()
    $seen = @{}
    foreach ($record in $Records) {
        $fields = ConvertTo-FieldMap -Record $record
        if ($fields.Count -eq 0) { continue }

        $action = Get-FieldValue -Fields $fields -Names @('action')
        $subtype = Get-FieldValue -Fields $fields -Names @('subtype')
        $tunnelType = Get-FieldValue -Fields $fields -Names @('tunneltype', 'vpntype')
        if ($action -notmatch '(?i)^tunnel-up$' -or $subtype -notmatch '(?i)^vpn$') { continue }
        if ($tunnelType -and $tunnelType -notmatch '(?i)ipsec|ike') { continue }

        $date = Get-FieldValue -Fields $fields -Names @('date')
        $time = Get-FieldValue -Fields $fields -Names @('time')
        $timestamp = [datetime]::MinValue
        if (-not [datetime]::TryParseExact(
            "$date $time",
            'yyyy-MM-dd HH:mm:ss',
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::None,
            [ref]$timestamp
        )) { continue }
        if ($timestamp.Date -ne $ReportDate.Date) { continue }

        $user = Get-FieldValue -Fields $fields -Names @('xauthuser', 'eapuser', 'user', 'username')
        if (-not $user) { continue }

        $eventTime = Get-FieldValue -Fields $fields -Names @('eventtime')
        $logId = Get-FieldValue -Fields $fields -Names @('logid')
        $tunnelId = Get-FieldValue -Fields $fields -Names @('tunnelid')
        $key = "$eventTime|$logId|$tunnelId"
        if (-not $eventTime -and -not $logId -and -not $tunnelId) {
            $key = "$($timestamp.ToString('s'))|$user|$(Get-FieldValue -Fields $fields -Names @('remip'))"
        }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $rows.Add([PSCustomObject]@{
            Usuario = $user
            Grupo = Get-FieldValue -Fields $fields -Names @('xauthgroup', 'group', 'usergroup')
            Inicio = [datetime]::SpecifyKind($timestamp, [System.DateTimeKind]::Unspecified)
            IPOrigem = Get-FieldValue -Fields $fields -Names @('remip', 'srcip', 'remoteip')
            IPCliente = Get-FieldValue -Fields $fields -Names @('assignip', 'tunnelip', 'assignedip')
            Tunel = Get-FieldValue -Fields $fields -Names @('vpntunnel', 'tunnel', 'name')
            Estado = $action
        })
    }

    return @($rows | Sort-Object Inicio)
}

function Get-HistorySummaryRows {
    param([object[]]$Rows)

    return @(
        $Rows |
            Group-Object Usuario |
            ForEach-Object {
                $firstConnection = $_.Group | Sort-Object Inicio | Select-Object -First 1
                [PSCustomObject]@{
                    Usuario = $_.Name
                    PrimeiraConexao = $firstConnection.Inicio
                    Quantidade = $_.Count
                }
            } |
            Sort-Object Usuario
    )
}

function New-HistoryReportHtml {
    param([object[]]$Rows, [datetime]$ReportDate)

    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $sentAtText = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">')
    [void]$builder.Append('<h1 style="color:#1a365d;font-size:22px;">Histórico diário de usuários VPN IPsec</h1>')
    [void]$builder.Append("<p>Data: <strong>$(Encode-Html $ReportDate.ToString('dd/MM/yyyy'))</strong><br>FortiGate: <strong>$(Encode-Html $FortiGateIP)</strong><br>Conexões: <strong>$(@($Rows).Count)</strong></p>")

    if (@($Rows).Count -eq 0) {
        [void]$builder.Append('<p style="padding:12px;background:#f7fafc;border:1px solid #e2e8f0;">Nenhuma conexão encontrada.</p>')
    }
    else {
        $summaryRows = @(Get-HistorySummaryRows -Rows $Rows)
        [void]$builder.Append('<h2 style="color:#2d3748;font-size:17px;margin:22px 0 8px;">Sumário por usuário</h2>')
        [void]$builder.Append('<table style="border-collapse:collapse;width:100%;max-width:700px;border:1px solid #ccc;font-size:13px;"><thead><tr style="background:#2b6cb0;color:#fff;text-align:left;">')
        foreach ($label in @('Usuário', 'Primeira conexão do dia', 'Qtde de conexões')) {
            [void]$builder.Append(('<th style="padding:6px 8px;border:1px solid #3182ce;">{0}</th>' -f (Encode-Html $label)))
        }
        [void]$builder.Append('</tr></thead><tbody>')
        foreach ($summaryRow in $summaryRows) {
            [void]$builder.Append('<tr>')
            foreach ($value in @($summaryRow.Usuario, $summaryRow.PrimeiraConexao.ToString('dd/MM/yyyy HH:mm:ss'), $summaryRow.Quantidade)) {
                [void]$builder.Append(('<td style="padding:5px 8px;border:1px solid #e2e8f0;">{0}</td>' -f (Encode-Html $value)))
            }
            [void]$builder.Append('</tr>')
        }
        [void]$builder.Append('</tbody></table>')

        [void]$builder.Append('<h2 style="color:#2d3748;font-size:17px;margin:22px 0 8px;">Histórico diário completo</h2>')
        [void]$builder.Append('<table style="border-collapse:collapse;width:100%;max-width:1050px;border:1px solid #ccc;font-size:12px;line-height:1.2;"><thead><tr style="background:#1a365d;color:#fff;text-align:left;">')
        foreach ($label in @('Usuário', 'Grupo', 'Início', 'IP de origem', 'IP do cliente', 'Túnel', 'Estado')) {
            [void]$builder.Append(('<th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">{0}</th>' -f (Encode-Html $label)))
        }
        [void]$builder.Append('</tr></thead><tbody>')
        foreach ($row in $Rows) {
            [void]$builder.Append('<tr>')
            foreach ($value in @($row.Usuario, $row.Grupo, $row.Inicio.ToString('dd/MM/yyyy HH:mm:ss'), $row.IPOrigem, $row.IPCliente, $row.Tunel, $row.Estado)) {
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
    $reportDate = ConvertTo-ReportDate -Value $DataRelatorio
    Write-Host "Consultando historico VPN IPsec de $($reportDate.ToString('dd/MM/yyyy')) pela API..."
    $records = @(Get-FortiIpsecHistoryRecords -ReportDate $reportDate)
    $rows = @(ConvertTo-HistoryRows -Records $records -ReportDate $reportDate)
    $html = New-HistoryReportHtml -Rows $rows -ReportDate $reportDate
    Send-PSPanelEmail -To $MailTo -Subject "[PSPanel] Histórico de conexões VPN IPsec - $($reportDate.ToString('dd/MM/yyyy'))" -Body $html -BodyAsHtml
    Write-Host "Relatorio historico enviado com sucesso. Registros da API: $($records.Count). Conexoes: $($rows.Count)."
    exit 0
}
catch {
    Write-Error "Falha ao gerar o historico VPN IPsec: $($_.Exception.Message)"
    exit 1
}
