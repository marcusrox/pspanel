#requires -Version 7.0

<#
.SYNOPSIS
    Gera e envia por e-mail o relatorio de uso do YouTube registrado pelo FortiGate.

.DESCRIPTION
    Consulta o endpoint de Application Control da Log API, aguarda a pesquisa
    assincrona do FortiGate ficar pronta e pagina todos os registros encontrados.
    Consolida trafego e tempo estimado por usuario, gera um arquivo XLSX com as
    planilhas Resumo, Detalhes (opcional) e Metodologia e envia o arquivo como
    anexo pelo modulo compartilhado PSPanel.Email.

.PARAMETER ApiToken
    Token de um administrador REST API com permissao de leitura dos logs. E obrigatorio.

.PARAMETER DataRelatorio
    Dia consultado. Quando omitido, usa a data atual.

.PARAMETER MailTo
    Destinatarios do e-mail. Aceita um ou mais enderecos e usa, por padrao,
    analistasusi@desenbahia.ba.gov.br.

.EXAMPLE
    .\Relatorio-YouTube-FortiGate.ps1 -ApiToken "token-ficticio"

    Consulta o dia atual, gera o XLSX e envia o anexo ao destinatario padrao.

.EXAMPLE
    .\Relatorio-YouTube-FortiGate.ps1 -ApiToken "token-ficticio" `
        -DataRelatorio "2026-08-12" -MailTo "seguranca@example.com"

    Gera e envia o relatorio de uma data especifica.

.INPUTS
    Nenhum. O script nao aceita objetos pelo pipeline.

.OUTPUTS
    Arquivo XLSX no OutputPath e mensagem de e-mail com o arquivo anexado.

.NOTES
    Requer PowerShell 7 ou superior, o modulo ImportExcel e permissao de leitura
    de logs no FortiGate. O envio usa a configuracao SMTP salva no PS Panel e as
    bibliotecas do modulo scripts-ps/modules/PSPanel.Email.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ApiToken,

    [datetime]$DataRelatorio = (Get-Date).Date,

    [ValidateNotNullOrEmpty()]
    [string[]]$MailTo = @('analistasusi@desenbahia.ba.gov.br')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuracoes fixas da integracao e do relatorio. Altere somente quando houver
# mudanca no ambiente, no endpoint do FortiGate ou na metodologia do relatorio.
$FortigateUrl = [uri]'https://10.35.0.1:4443'
$Vdom = 'root'
$SerialNumber = 'FG2H1GT925910973'
$ApplicationName = 'YouTube'
$ApplicationId = '31077'
$TimeZoneId = 'Bahia Standard Time'
$PageSize = 500
$MaxPages = 1000
$MaxPollAttempts = 60
$PollIntervalSeconds = 2
$TimeoutSec = 120
$ValidacaoCertificado = 'Ignorar'
$FallbackEventSeconds = 60
$TrafficAggregation = 'PerSessionMax'
$IncludeRawLogs = $true
$InstallImportExcelIfMissing = $true
$OutputPath = Join-Path $PSScriptRoot ("Relatorio_YouTube_{0:yyyy-MM-dd}.xlsx" -f $DataRelatorio)

# ============================================================================
# FUNCOES
# ============================================================================

function Get-ReportTimeZone {
    param([Parameter(Mandatory)][string]$RequestedId)

    $candidates = @($RequestedId, 'E. South America Standard Time', 'America/Bahia') | Select-Object -Unique
    foreach ($id in $candidates) {
        try {
            return [TimeZoneInfo]::FindSystemTimeZoneById($id)
        }
        catch {
            # Tenta o proximo identificador.
        }
    }

    Write-Warning "Nao foi possivel localizar o fuso '$RequestedId'. Sera usado o fuso local do Windows."
    return [TimeZoneInfo]::Local
}

function ConvertTo-Int64Safe {
    param($Value)

    if ($null -eq $Value) { return [int64]0 }
    $n = [int64]0
    if ([int64]::TryParse(([string]$Value), [ref]$n)) { return $n }
    return [int64]0
}

function ConvertTo-DoubleSafe {
    param($Value)

    if ($null -eq $Value) { return [double]0 }
    $n = [double]0
    if ([double]::TryParse(
        ([string]$Value),
        [Globalization.NumberStyles]::Any,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$n
    )) { return $n }
    return [double]0
}

function Get-FirstPropertyValue {
    param(
        [Parameter(Mandatory)]$Object,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        $prop = $Object.PSObject.Properties[$name]
        if ($null -ne $prop -and $null -ne $prop.Value) {
            $text = [string]$prop.Value
            if (-not [string]::IsNullOrWhiteSpace($text) -and $text -ne 'N/A' -and $text -ne '-') {
                return $prop.Value
            }
        }
    }
    return $null
}

function Convert-EpochValueToMilliseconds {
    param($Value)

    if ($null -eq $Value) { return $null }

    $n = [int64]0
    if (-not [int64]::TryParse(([string]$Value), [ref]$n)) { return $null }

    # FortiOS pode expor epoch em segundos, ms, us ou ns, dependendo do campo.
    if ($n -ge 100000000000000000) { return [int64]($n / 1000000) } # ns -> ms
    if ($n -ge 100000000000000)    { return [int64]($n / 1000)    } # us -> ms
    if ($n -ge 100000000000)       { return $n                    } # ms
    return [int64]($n * 1000)                                      # s -> ms
}

function Get-LogDateTime {
    param(
        [Parameter(Mandatory)]$Log,
        [Parameter(Mandatory)][TimeZoneInfo]$TimeZone
    )

    $epochValue = $null

    # Formato visto na API do Log Viewer.
    $metadataProp = $Log.PSObject.Properties['_metadata']
    if ($null -ne $metadataProp -and $null -ne $metadataProp.Value) {
        $tsProp = $metadataProp.Value.PSObject.Properties['timestamp']
        if ($null -ne $tsProp) { $epochValue = $tsProp.Value }
    }

    # Alguns retornos podem trazer o nome achatado.
    if ($null -eq $epochValue) {
        $flatMetadata = $Log.PSObject.Properties['_metadata.timestamp']
        if ($null -ne $flatMetadata) { $epochValue = $flatMetadata.Value }
    }

    # eventtime em logs raw do FortiOS costuma ser epoch com precisao maior.
    if ($null -eq $epochValue) {
        $epochValue = Get-FirstPropertyValue -Object $Log -Names @('eventtime', 'timestamp')
    }

    if ($null -ne $epochValue) {
        $ms = Convert-EpochValueToMilliseconds $epochValue
        if ($null -ne $ms) {
            try {
                $dto = [DateTimeOffset]::FromUnixTimeMilliseconds($ms)
                return ([TimeZoneInfo]::ConvertTime($dto, $TimeZone)).DateTime
            }
            catch {
                # Continua para date + time.
            }
        }
    }

    $dateText = Get-FirstPropertyValue -Object $Log -Names @('date')
    $timeText = Get-FirstPropertyValue -Object $Log -Names @('time')
    if ($null -ne $dateText -and $null -ne $timeText) {
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParseExact(
            "$dateText $timeText",
            'yyyy-MM-dd HH:mm:ss',
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::None,
            [ref]$parsed
        )) {
            return [datetime]::SpecifyKind($parsed, [DateTimeKind]::Unspecified)
        }
    }

    return $null
}

function Convert-LocalDateToEpochMilliseconds {
    param(
        [Parameter(Mandatory)][datetime]$LocalDateTime,
        [Parameter(Mandatory)][TimeZoneInfo]$TimeZone
    )

    $unspecified = [datetime]::SpecifyKind($LocalDateTime, [DateTimeKind]::Unspecified)
    $utc = [TimeZoneInfo]::ConvertTimeToUtc($unspecified, $TimeZone)
    return ([DateTimeOffset]$utc).ToUnixTimeMilliseconds()
}

function New-FortiGateLogUri {
    param(
        [Parameter(Mandatory)][int]$Start,
        [Parameter(Mandatory)][int]$Rows,
        [Parameter(Mandatory)][int64]$StartEpochMs,
        [Parameter(Mandatory)][int64]$EndEpochMs,
        [AllowNull()][object]$SessionId
    )

    if (-not [string]::IsNullOrWhiteSpace($ApplicationId)) {
        $appFilter = 'app=*"{0}",app=*"{1}"' -f $ApplicationId, $ApplicationName
    }
    else {
        $appFilter = 'app=*"{0}"' -f $ApplicationName
    }

    $filters = @(
        $appFilter,
        ('_metadata.timestamp>="{0}"' -f $StartEpochMs),
        ('_metadata.timestamp<="{0}"' -f $EndEpochMs)
    )

    $query = [System.Collections.Generic.List[string]]::new()
    $query.Add("start=$Start")
    $query.Add("rows=$Rows")
    if ($null -ne $SessionId -and -not [string]::IsNullOrWhiteSpace([string]$SessionId)) {
        $query.Add('session_id=' + [uri]::EscapeDataString([string]$SessionId))
    }

    foreach ($filter in $filters) {
        $query.Add('filter=' + [uri]::EscapeDataString($filter))
    }

    # Estes extras sao opcionais. country_id e reverse_lookup nao sao necessarios para o resumo,
    # portanto foram omitidos para reduzir trabalho da consulta.
    if (-not [string]::IsNullOrWhiteSpace($SerialNumber)) {
        $query.Add('serial_no=' + [uri]::EscapeDataString($SerialNumber))
    }
    $query.Add('vdom=' + [uri]::EscapeDataString($Vdom))

    return ($FortigateUrl.AbsoluteUri.TrimEnd('/') + '/api/v2/log/disk/app-ctrl?' + ($query -join '&'))
}

function Get-ApiResultItems {
    param([AllowNull()][object]$Response)

    if ($null -eq $Response) { return @() }
    if ($Response -is [System.Array]) { return @($Response) }

    $resultsProperty = $Response.PSObject.Properties['results']
    if ($null -ne $resultsProperty -and $null -ne $resultsProperty.Value) {
        $dataProperty = $resultsProperty.Value.PSObject.Properties['data']
        if ($null -ne $dataProperty) { return @($dataProperty.Value) }
        return @($resultsProperty.Value)
    }

    foreach ($name in @('data', 'logs', 'entries')) {
        $property = $Response.PSObject.Properties[$name]
        if ($null -ne $property) { return @($property.Value) }
    }

    return @()
}

function Get-ResponsePropertyValue {
    param(
        [AllowNull()][object]$Response,
        [Parameter(Mandatory)][string[]]$Names
    )

    if ($null -eq $Response) { return $null }
    foreach ($name in $Names) {
        $property = $Response.PSObject.Properties[$name]
        if ($null -ne $property) { return $property.Value }
    }
    return $null
}

function Invoke-FortiGateApiGet {
    param([Parameter(Mandatory)][string]$Uri)

    $headers = @{ Authorization = "Bearer $ApiToken" }
    $invokeParams = @{
        Uri         = $Uri
        Headers     = $headers
        Method      = 'GET'
        TimeoutSec  = $TimeoutSec
        ErrorAction = 'Stop'
    }
    if ($ValidacaoCertificado -eq 'Ignorar') {
        $invokeParams['SkipCertificateCheck'] = $true
    }

    try {
        return Invoke-RestMethod @invokeParams
    }
    catch {
        throw "Erro ao consultar a API do FortiGate: $($_.Exception.Message)"
    }
}

function Wait-FortiGateLogResponse {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [AllowNull()][object]$InitialResponse
    )

    $response = $InitialResponse
    $sessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')

    for ($attempt = 1; $attempt -le $MaxPollAttempts; $attempt++) {
        $ready = Get-ResponsePropertyValue -Response $response -Names @('ready')
        if ($null -eq $ready -or $ready -eq $true -or [string]$ready -match '^(?i:true|1)$') {
            return $response
        }

        if ($null -eq $sessionId) {
            throw 'A Log API retornou ready=false sem informar session_id.'
        }
        if ($attempt -eq $MaxPollAttempts) { break }

        $percent = Get-ResponsePropertyValue -Response $response -Names @('percent_logs_processed', 'completed')
        Write-Host ("  Pesquisa ainda em processamento ({0}%). Tentativa {1} de {2}." -f $percent, $attempt, $MaxPollAttempts)
        if ($PollIntervalSeconds -gt 0) { Start-Sleep -Seconds $PollIntervalSeconds }

        if ($Uri -match '(?i)[?&]session_id=') {
            $pollUri = $Uri
        }
        else {
            $pollUri = $Uri + '&session_id=' + [uri]::EscapeDataString([string]$sessionId)
        }
        $response = Invoke-FortiGateApiGet -Uri $pollUri
        $newSessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')
        if ($null -ne $newSessionId) { $sessionId = $newSessionId }
    }

    throw "A pesquisa da Log API nao ficou pronta apos $MaxPollAttempts tentativas."
}

function Invoke-FortiGateApplicationLogs {
    param(
        [Parameter(Mandatory)][int64]$StartEpochMs,
        [Parameter(Mandatory)][int64]$EndEpochMs
    )

    $all = [System.Collections.Generic.List[object]]::new()
    $start = 1
    $page = 0
    $sessionId = $null
    $completed = $false

    while ($page -lt $MaxPages) {
        $page++
        $uri = New-FortiGateLogUri -Start $start -Rows $PageSize `
            -StartEpochMs $StartEpochMs -EndEpochMs $EndEpochMs -SessionId $sessionId
        Write-Host ("Consultando pagina {0}, start={1}, rows={2}..." -f $page, $start, $PageSize)

        $response = Invoke-FortiGateApiGet -Uri $uri
        $response = Wait-FortiGateLogResponse -Uri $uri -InitialResponse $response

        $status = Get-ResponsePropertyValue -Response $response -Names @('status')
        if ($status -and [string]$status -notmatch '^(?i)success$') {
            throw "A Log API retornou status inesperado: $status."
        }

        $responseSessionId = Get-ResponsePropertyValue -Response $response -Names @('session_id', 'session-id')
        if ($null -ne $responseSessionId) { $sessionId = $responseSessionId }

        $batch = @(Get-ApiResultItems -Response $response | Where-Object { $null -ne $_ })
        foreach ($item in $batch) { [void]$all.Add($item) }
        Write-Host ("  Registros recebidos: {0}. Total acumulado: {1}." -f $batch.Count, $all.Count)

        $nextIndex = Get-ResponsePropertyValue -Response $response -Names @('next_idx', 'next-index', 'next')
        $matchedCount = Get-ResponsePropertyValue -Response $response -Names @('matched_count', 'total_lines', 'total', 'total_count')
        $limitReached = Get-ResponsePropertyValue -Response $response -Names @('limit_reached')

        if ($null -ne $matchedCount -and $all.Count -ge (ConvertTo-Int64Safe $matchedCount)) {
            $completed = $true
            break
        }
        if ($null -ne $nextIndex -and (ConvertTo-Int64Safe $nextIndex) -gt $start) {
            $start = ConvertTo-Int64Safe $nextIndex
            continue
        }
        if ($null -ne $matchedCount -and $all.Count -lt (ConvertTo-Int64Safe $matchedCount) -and $batch.Count -gt 0) {
            $start += $batch.Count
            continue
        }
        if (($limitReached -eq $true -or [string]$limitReached -match '^(?i:true|1)$') -and $batch.Count -gt 0) {
            $start += $batch.Count
            continue
        }
        if ($batch.Count -ge $PageSize) {
            $start += $batch.Count
            continue
        }

        $completed = $true
        break
    }

    if (-not $completed) {
        throw "A Log API excedeu o limite de $MaxPages paginas."
    }

    return @($all)
}

function Merge-TimeIntervals {
    param(
        [Parameter(Mandatory)][object[]]$Intervals,
        [Parameter(Mandatory)][datetime]$ClipStart,
        [Parameter(Mandatory)][datetime]$ClipEnd
    )

    $normalized = foreach ($i in $Intervals) {
        if ($null -eq $i.Start -or $null -eq $i.End) { continue }

        $s = [datetime]$i.Start
        $e = [datetime]$i.End
        if ($e -lt $ClipStart -or $s -gt $ClipEnd) { continue }
        if ($s -lt $ClipStart) { $s = $ClipStart }
        if ($e -gt $ClipEnd)   { $e = $ClipEnd }
        if ($e -lt $s) { continue }

        [pscustomobject]@{ Start = $s; End = $e }
    }

    $sorted = @($normalized | Sort-Object Start, End)
    if ($sorted.Count -eq 0) {
        return [pscustomobject]@{
            Seconds = [double]0
            Count   = 0
            First   = $null
            Last    = $null
        }
    }

    $merged = [System.Collections.Generic.List[object]]::new()
    $currentStart = [datetime]$sorted[0].Start
    $currentEnd   = [datetime]$sorted[0].End

    for ($i = 1; $i -lt $sorted.Count; $i++) {
        $nextStart = [datetime]$sorted[$i].Start
        $nextEnd   = [datetime]$sorted[$i].End

        if ($nextStart -le $currentEnd) {
            if ($nextEnd -gt $currentEnd) { $currentEnd = $nextEnd }
        }
        else {
            [void]$merged.Add([pscustomobject]@{ Start = $currentStart; End = $currentEnd })
            $currentStart = $nextStart
            $currentEnd = $nextEnd
        }
    }
    [void]$merged.Add([pscustomobject]@{ Start = $currentStart; End = $currentEnd })

    $seconds = 0.0
    foreach ($m in $merged) {
        $seconds += ([datetime]$m.End - [datetime]$m.Start).TotalSeconds
    }

    return [pscustomobject]@{
        Seconds = $seconds
        Count   = $merged.Count
        First   = [datetime]$merged[0].Start
        Last    = [datetime]$merged[$merged.Count - 1].End
    }
}

function ConvertTo-NormalizedLog {
    param(
        [Parameter(Mandatory)]$Log,
        [Parameter(Mandatory)][TimeZoneInfo]$TimeZone,
        [Parameter(Mandatory)][int]$Index
    )

    $eventDateTime = Get-LogDateTime -Log $Log -TimeZone $TimeZone
    if ($null -eq $eventDateTime) { return $null }

    $srcIp = [string](Get-FirstPropertyValue -Object $Log -Names @('srcip', 'src_ip', 'source'))
    $user  = [string](Get-FirstPropertyValue -Object $Log -Names @('user', 'srcuser', 'src_user', 'unauthuser'))

    if ([string]::IsNullOrWhiteSpace($user)) {
        if (-not [string]::IsNullOrWhiteSpace($srcIp)) {
            $user = "SEM_USUARIO ($srcIp)"
        }
        else {
            $user = 'SEM_USUARIO'
        }
    }

    $sessionId = [string](Get-FirstPropertyValue -Object $Log -Names @('sessionid', 'session_id'))
    if ($sessionId -eq '0') { $sessionId = '' }

    $duration = ConvertTo-DoubleSafe (Get-FirstPropertyValue -Object $Log -Names @('duration'))
    $sent     = ConvertTo-Int64Safe  (Get-FirstPropertyValue -Object $Log -Names @('sentbyte', 'sentbytes', 'sentdelta'))
    $received = ConvertTo-Int64Safe  (Get-FirstPropertyValue -Object $Log -Names @('rcvdbyte', 'receivedbyte', 'rcvddelta'))

    $app = [string](Get-FirstPropertyValue -Object $Log -Names @('app', 'application'))
    $appid = [string](Get-FirstPropertyValue -Object $Log -Names @('appid', 'app_id'))
    $action = [string](Get-FirstPropertyValue -Object $Log -Names @('action', 'utmaction'))
    $dstIp = [string](Get-FirstPropertyValue -Object $Log -Names @('dstip', 'dst_ip', 'destination'))
    $hostname = [string](Get-FirstPropertyValue -Object $Log -Names @('hostname', 'host', 'dstname'))

    [pscustomobject][ordered]@{
        Index            = $Index
        Usuario          = $user
        IPOrigem         = $srcIp
        DataHora         = $eventDateTime
        SessionId        = $sessionId
        DuracaoSegundos  = $duration
        EnviadoBytes     = $sent
        RecebidoBytes    = $received
        TrafegoBytes     = ($sent + $received)
        Aplicacao        = $app
        AppId            = $appid
        Acao             = $action
        IPDestino        = $dstIp
        HostDestino      = $hostname
        Raw              = $Log
    }
}

function Get-UserTraffic {
    param([Parameter(Mandatory)][object[]]$Rows)

    if ($TrafficAggregation -eq 'SumEvents') {
        return [pscustomobject]@{
            Sent     = [int64](($Rows | Measure-Object EnviadoBytes -Sum).Sum)
            Received = [int64](($Rows | Measure-Object RecebidoBytes -Sum).Sum)
        }
    }

    # PerSessionMax: para cada sessionid usa o maior contador observado.
    # Registros sem sessionid sao tratados individualmente.
    $buckets = @{}
    foreach ($row in $Rows) {
        $key = if ([string]::IsNullOrWhiteSpace([string]$row.SessionId)) {
            "EVENT:$($row.Index)"
        }
        else {
            "SESSION:$($row.SessionId)"
        }

        if (-not $buckets.ContainsKey($key)) {
            $buckets[$key] = [pscustomobject]@{
                Sent = [int64]$row.EnviadoBytes
                Received = [int64]$row.RecebidoBytes
            }
        }
        else {
            if ([int64]$row.EnviadoBytes -gt [int64]$buckets[$key].Sent) {
                $buckets[$key].Sent = [int64]$row.EnviadoBytes
            }
            if ([int64]$row.RecebidoBytes -gt [int64]$buckets[$key].Received) {
                $buckets[$key].Received = [int64]$row.RecebidoBytes
            }
        }
    }

    $sent = [int64]0
    $received = [int64]0
    foreach ($bucket in $buckets.Values) {
        $sent += [int64]$bucket.Sent
        $received += [int64]$bucket.Received
    }

    return [pscustomobject]@{ Sent = $sent; Received = $received }
}

function Get-UserTimeEstimate {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][datetime]$DayStart,
        [Parameter(Mandatory)][datetime]$DayEnd
    )

    $intervals = [System.Collections.Generic.List[object]]::new()

    # Usa apenas o melhor registro de cada sessionid: o de maior duration;
    # em empate, o mais recente. Isso evita repetir o mesmo intervalo varias vezes.
    $withSession = @($Rows | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.SessionId) -and [double]$_.DuracaoSegundos -gt 0
    })

    if ($withSession.Count -gt 0) {
        foreach ($group in ($withSession | Group-Object SessionId)) {
            $best = $group.Group |
                Sort-Object @{Expression='DuracaoSegundos';Descending=$true}, @{Expression='DataHora';Descending=$true} |
                Select-Object -First 1

            $end = [datetime]$best.DataHora
            $start = $end.AddSeconds(-[double]$best.DuracaoSegundos)
            [void]$intervals.Add([pscustomobject]@{ Start = $start; End = $end })
        }
    }

    # Eventos sem sessionid, ou sessoes que nao possuem nenhum duration utilizavel,
    # recebem uma pequena janela fallback. Se uma sessionid tiver ao menos um
    # registro com duration > 0, os registros duration=0 dessa sessao nao geram
    # intervalos extras.
    $usableSessionIds = @{}
    foreach ($row in $withSession) {
        $usableSessionIds[[string]$row.SessionId] = $true
    }

    foreach ($row in $Rows) {
        $sid = [string]$row.SessionId
        $needsFallback = [string]::IsNullOrWhiteSpace($sid) -or (-not $usableSessionIds.ContainsKey($sid))
        if ($needsFallback) {
            $start = [datetime]$row.DataHora
            $end = $start.AddSeconds($FallbackEventSeconds)
            [void]$intervals.Add([pscustomobject]@{ Start = $start; End = $end })
        }
    }

    return Merge-TimeIntervals -Intervals @($intervals) -ClipStart $DayStart -ClipEnd $DayEnd
}

function Format-Duration {
    param([double]$Seconds)

    $ts = [TimeSpan]::FromSeconds([math]::Max(0, [math]::Round($Seconds)))
    if ($ts.TotalHours -ge 24) {
        return ('{0}d {1:00}:{2:00}:{3:00}' -f [math]::Floor($ts.TotalDays), $ts.Hours, $ts.Minutes, $ts.Seconds)
    }
    return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
}

function ConvertTo-HtmlText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

# ============================================================================
# VALIDACOES E CONSULTA
# ============================================================================

if ($FortigateUrl.Scheme -ne 'https') {
    throw 'FortigateUrl deve usar HTTPS.'
}

if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
    if ($InstallImportExcelIfMissing) {
        Write-Host 'Modulo ImportExcel nao encontrado. Instalando no escopo CurrentUser...'
        Install-Module ImportExcel -Scope CurrentUser -Force -AllowClobber
    }
    else {
        throw "Modulo ImportExcel nao encontrado. Execute: Install-Module ImportExcel -Scope CurrentUser"
    }
}
Import-Module ImportExcel

$tz = Get-ReportTimeZone -RequestedId $TimeZoneId
$dayStart = [datetime]::SpecifyKind($DataRelatorio.Date, [DateTimeKind]::Unspecified)
$dayEnd = $dayStart.AddDays(1).AddMilliseconds(-1)
$startEpoch = Convert-LocalDateToEpochMilliseconds -LocalDateTime $dayStart -TimeZone $tz
$endEpoch   = Convert-LocalDateToEpochMilliseconds -LocalDateTime $dayEnd   -TimeZone $tz

Write-Host ""
Write-Host '=== Relatorio YouTube / FortiGate ==='
Write-Host "FortiGate : $FortigateUrl"
Write-Host "VDOM      : $Vdom"
Write-Host ("Periodo   : {0:dd/MM/yyyy HH:mm:ss.fff} a {1:dd/MM/yyyy HH:mm:ss.fff} ({2})" -f $dayStart, $dayEnd, $tz.Id)
Write-Host "Aplicacao : $ApplicationName (AppId $ApplicationId)"
Write-Host "Saida     : $OutputPath"
Write-Host ""

$rawLogs = Invoke-FortiGateApplicationLogs -StartEpochMs $startEpoch -EndEpochMs $endEpoch

$normalized = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($log in $rawLogs) {
    $index++
    $n = ConvertTo-NormalizedLog -Log $log -TimeZone $tz -Index $index
    if ($null -ne $n) {
        # Defesa adicional: mantem somente eventos dentro do dia pedido.
        if ($n.DataHora -ge $dayStart -and $n.DataHora -le $dayEnd) {
            [void]$normalized.Add($n)
        }
    }
}

Write-Host ("Registros validos no periodo: {0}" -f $normalized.Count)

# ============================================================================
# CONSOLIDACAO POR USUARIO
# ============================================================================

$summary = [System.Collections.Generic.List[object]]::new()

foreach ($userGroup in ($normalized | Group-Object Usuario | Sort-Object Name)) {
    $rows = @($userGroup.Group)
    $traffic = Get-UserTraffic -Rows $rows
    $time = Get-UserTimeEstimate -Rows $rows -DayStart $dayStart -DayEnd $dayEnd

    $sent = [int64]$traffic.Sent
    $received = [int64]$traffic.Received
    $total = $sent + $received

    $ips = @($rows | ForEach-Object { $_.IPOrigem } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $sessionIds = @($rows | ForEach-Object { $_.SessionId } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

    [void]$summary.Add([pscustomobject][ordered]@{
        Usuario                  = $userGroup.Name
        IPsOrigem                = ($ips -join ', ')
        PrimeiroAcesso           = $time.First
        UltimoAcesso             = $time.Last
        TempoEstimado            = (Format-Duration $time.Seconds)
        MinutosEstimados         = [math]::Round($time.Seconds / 60, 2)
        SessoesTempoEstimadas    = $time.Count
        SessoesFortiGate         = $sessionIds.Count
        Eventos                  = $rows.Count
        TrafegoTotalMB           = [math]::Round($total / 1MB, 2)
        TrafegoRecebidoMB        = [math]::Round($received / 1MB, 2)
        TrafegoEnviadoMB         = [math]::Round($sent / 1MB, 2)
        TrafegoTotalGB           = [math]::Round($total / 1GB, 3)
    })
}

# ============================================================================
# EXPORTACAO PARA EXCEL
# ============================================================================

if (Test-Path $OutputPath) {
    Remove-Item $OutputPath -Force
}

if ($summary.Count -gt 0) {
    $excel = $summary |
        Export-Excel -Path $OutputPath -WorksheetName 'Resumo' -TableName 'tbResumoYouTube' `
        -TableStyle Medium2 -AutoFilter -FreezeTopRow -BoldTopRow -AutoSize -PassThru

    $ws = $excel.Workbook.Worksheets['Resumo']
    $ws.Column(3).Style.Numberformat.Format = 'dd/mm/yyyy hh:mm:ss'
    $ws.Column(4).Style.Numberformat.Format = 'dd/mm/yyyy hh:mm:ss'
    $ws.Column(6).Style.Numberformat.Format = '0.00'
    $ws.Column(10).Style.Numberformat.Format = '0.00'
    $ws.Column(11).Style.Numberformat.Format = '0.00'
    $ws.Column(12).Style.Numberformat.Format = '0.00'
    $ws.Column(13).Style.Numberformat.Format = '0.000'

    # Limita algumas larguras que podem crescer demais com AutoSize.
    $ws.Column(1).Width = [math]::Min($ws.Column(1).Width, 30)
    $ws.Column(2).Width = [math]::Min([math]::Max($ws.Column(2).Width, 18), 45)
    $ws.Column(5).Width = 18

    $excel.Save()
    $excel.Dispose()
}
else {
    [pscustomobject]@{
        Mensagem = "Nenhum log de $ApplicationName encontrado em $($DataRelatorio.ToString('dd/MM/yyyy'))."
        Periodo  = "$dayStart a $dayEnd"
        VDOM     = $Vdom
    } | Export-Excel -Path $OutputPath -WorksheetName 'Resumo' -AutoSize -BoldTopRow -FreezeTopRow
}

if ($IncludeRawLogs -and $normalized.Count -gt 0) {
    $details = $normalized | Select-Object `
        Usuario, IPOrigem, DataHora, SessionId, DuracaoSegundos, `
        @{Name='EnviadoMB';Expression={[math]::Round($_.EnviadoBytes / 1MB, 3)}}, `
        @{Name='RecebidoMB';Expression={[math]::Round($_.RecebidoBytes / 1MB, 3)}}, `
        @{Name='TrafegoMB';Expression={[math]::Round($_.TrafegoBytes / 1MB, 3)}}, `
        Aplicacao, AppId, Acao, IPDestino, HostDestino

    $excel = $details |
        Export-Excel -Path $OutputPath -WorksheetName 'Detalhes' -TableName 'tbDetalhesYouTube' `
        -TableStyle Medium2 -AutoFilter -FreezeTopRow -BoldTopRow -AutoSize -PassThru

    $ws = $excel.Workbook.Worksheets['Detalhes']
    $ws.Column(3).Style.Numberformat.Format = 'dd/mm/yyyy hh:mm:ss'
    $ws.Column(4).Width = [math]::Min([math]::Max($ws.Column(4).Width, 14), 20)
    $ws.Column(13).Width = [math]::Min([math]::Max($ws.Column(13).Width, 20), 55)
    $excel.Save()
    $excel.Dispose()
}

# Planilha de metodologia/parametros para facilitar auditoria do relatorio.
$methodology = @(
    [pscustomobject]@{ Item='FortiGate'; Valor=$FortigateUrl },
    [pscustomobject]@{ Item='VDOM'; Valor=$Vdom },
    [pscustomobject]@{ Item='Data'; Valor=$DataRelatorio.ToString('yyyy-MM-dd') },
    [pscustomobject]@{ Item='Fuso horario'; Valor=$tz.Id },
    [pscustomobject]@{ Item='Aplicacao'; Valor="$ApplicationName / AppId $ApplicationId" },
    [pscustomobject]@{ Item='Endpoint'; Valor='/api/v2/log/disk/app-ctrl' },
    [pscustomobject]@{ Item='Agregacao de trafego'; Valor=$TrafficAggregation },
    [pscustomobject]@{ Item='Estimativa de tempo'; Valor='Uniao dos intervalos de sessionid/duration; eventos sem duration recebem janela fallback.' },
    [pscustomobject]@{ Item='Fallback por evento (s)'; Valor=$FallbackEventSeconds },
    [pscustomobject]@{ Item='Observacao'; Valor='Tempo estimado representa atividade/conectividade YouTube detectada pelo FortiGate, nao tempo comprovado de video assistido.' }
)

$methodology | Export-Excel -Path $OutputPath -WorksheetName 'Metodologia' -TableName 'tbMetodologia' `
    -TableStyle Medium2 -AutoSize -BoldTopRow -FreezeTopRow

if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "O arquivo XLSX nao foi criado: $OutputPath"
}

$emailModulePath = Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1'
if (-not (Test-Path -LiteralPath $emailModulePath -PathType Leaf)) {
    throw "Modulo PSPanel.Email nao encontrado: $emailModulePath"
}
Import-Module $emailModulePath -Force -ErrorAction Stop

$emailSubject = "[PSPanel] Relatorio YouTube / FortiGate - $($DataRelatorio.ToString('dd/MM/yyyy'))"
$emailBody = @"
<html>
<body style="font-family:Segoe UI,Arial,sans-serif;color:#1f2937;">
    <h2>Relatorio YouTube / FortiGate</h2>
    <p>Segue anexado o relatorio referente a <strong>$(ConvertTo-HtmlText $($DataRelatorio.ToString('dd/MM/yyyy')))</strong>.</p>
    <ul>
        <li>Usuarios consolidados: <strong>$($summary.Count)</strong></li>
        <li>Eventos processados: <strong>$($normalized.Count)</strong></li>
        <li>VDOM: <strong>$(ConvertTo-HtmlText $Vdom)</strong></li>
        <li>Aplicacao: <strong>$(ConvertTo-HtmlText $ApplicationName)</strong></li>
    </ul>
    <p>Mensagem enviada automaticamente pelo PS Panel.</p>
</body>
</html>
"@

Send-PSPanelEmail -To $MailTo -Subject $emailSubject -Body $emailBody `
    -BodyAsHtml -AttachmentPath $OutputPath -ErrorAction Stop

Write-Host ""
Write-Host 'Concluido.' -ForegroundColor Green
Write-Host "Usuarios consolidados : $($summary.Count)"
Write-Host "Eventos processados   : $($normalized.Count)"
Write-Host "Arquivo                : $OutputPath"
Write-Host "E-mail enviado para   : $($MailTo -join ', ')"
