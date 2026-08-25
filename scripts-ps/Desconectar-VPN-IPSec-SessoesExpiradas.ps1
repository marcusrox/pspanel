#requires -Version 5.1

<#
.SYNOPSIS
    Desconecta sessoes VPN IPsec dial-up que excederam o tempo maximo configurado.

.DESCRIPTION
    Consulta as sessoes VPN IPsec ativas pela API REST do FortiGate, identifica
    sessoes dial-up cujo tempo conectado atingiu o limite e, no modo Executar,
    solicita o encerramento pela API POST /api/v2/monitor/vpn/ike/clear.

    O modo padrao e Simular. Antes de cada desconexao, a sessao e consultada
    novamente e a rotina exige que o nome dinamico do gateway identifique uma
    unica sessao ativa. Ao final, envia um relatorio HTML por e-mail.

.PARAMETER FortiApiToken
    Token de um administrador REST API autorizado a consultar sessoes VPN e,
    no modo Executar, chamar o endpoint de encerramento de IKE.

.PARAMETER FortiGateIP
    Endereco IP ou nome do FortiGate. O valor padrao e 10.35.0.1.

.PARAMETER FortiGatePort
    Porta HTTPS administrativa do FortiGate. O valor padrao e 4443.

.PARAMETER Vdom
    VDOM consultado. O valor padrao e root.

.PARAMETER LimiteHoras
    Quantidade maxima de horas continuas permitidas. O valor padrao e 12.

.PARAMETER Modo
    Simular apenas informa as sessoes elegiveis. Executar solicita as
    desconexoes. O valor padrao e Simular.

.PARAMETER UsuariosExcluidos
    Lista opcional de usuarios que nunca devem ser desconectados pela rotina.
    Aceita um array ou nomes separados por virgula ou ponto e virgula. A
    comparacao nao diferencia maiusculas de minusculas.

.PARAMETER MaximoDesconexoes
    Limite de seguranca de desconexoes em uma unica execucao. Se a quantidade
    elegivel for maior, nenhuma sessao sera encerrada. O valor padrao e 10.

.PARAMETER IntervaloVerificacaoSegundos
    Tempo de espera antes da verificacao final. Aceita de 0 a 30 segundos e o
    valor padrao e 3.

.PARAMETER ValidacaoCertificado
    Validar exige certificado HTTPS confiavel. Ignorar aceita o certificado
    interno previamente verificado. O valor padrao e Ignorar.

.PARAMETER MailTo
    Destinatario do relatorio por e-mail. O valor padrao e
    analistasusi@desenbahia.ba.gov.br.

.EXAMPLE
    .\Desconectar-VPN-IPSec-SessoesExpiradas.ps1 -FortiApiToken "token-ficticio"

    Simula a regra de 12 horas sem desconectar usuarios.

.EXAMPLE
    .\Desconectar-VPN-IPSec-SessoesExpiradas.ps1 -FortiApiToken "token-ficticio" -Modo Executar -LimiteHoras 12 -UsuariosExcluidos "usuario.servico,outro.usuario"

    Desconecta sessoes elegiveis, respeitando a excecao informada.

.INPUTS
    Nenhum. O script nao aceita objetos pelo pipeline.

.OUTPUTS
    Mensagens de progresso em stdout e um relatorio HTML enviado por e-mail.

.NOTES
    Requer PowerShell 5.1, acesso HTTPS ao FortiGate, modulo PSPanel.Email e um
    token REST API com privilegios minimos compativeis. O endpoint de clear esta
    disponivel em versoes compativeis do FortiOS a partir da linha 6.4.5.
#>
[CmdletBinding()]
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
    [ValidateRange(1, 8760)]
    [int]$LimiteHoras = 12,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Simular', 'Executar')]
    [string]$Modo = 'Simular',

    [Parameter(Mandatory = $false)]
    [AllowEmptyCollection()]
    [string[]]$UsuariosExcluidos = @(),

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$MaximoDesconexoes = 10,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 30)]
    [int]$IntervaloVerificacaoSegundos = 3,

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
$LimiteSegundos = [int64]$LimiteHoras * 3600

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
        'creation_time', 'uptime', 'rgwy', 'tun_id', 'tun_id6', 'dialup_index', 'connection_count'
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

function Invoke-FortiApiRequest {
    param(
        [ValidateSet('Get', 'Post')]
        [string]$Method,
        [string]$Uri
    )

    $request = @{
        Uri = $Uri
        Method = $Method
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
    $encodedVdom = [uri]::EscapeDataString($Vdom)
    $uri = "$(Get-FortiApiBaseUrl)/api/v2/monitor/vpn/ipsec?vdom=$encodedVdom"
    return Invoke-FortiApiRequest -Method Get -Uri $uri
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
        $uptimeValue = Get-ObjectValue -Object $candidate -Names @('creation_time', 'uptime')
        if ($null -ne $uptimeValue) {
            [void][int64]::TryParse([string]$uptimeValue, [ref]$uptimeSeconds)
        }

        $state = Get-ObjectValue -Object $candidate -Names @('status', 'state', 'run_state')
        if (-not (Test-MeaningfulValue $state)) { $state = 'up' }

        $rows.Add([PSCustomObject]@{
            Usuario = [string]$username
            Inicio = if ($uptimeSeconds -gt 0) { $CollectedAt.AddSeconds(-$uptimeSeconds) } else { $null }
            Duracao = if ($uptimeSeconds -gt 0) { [TimeSpan]::FromSeconds($uptimeSeconds).ToString('d\.hh\:mm\:ss') } else { '' }
            DuracaoSegundos = $uptimeSeconds
            IPOrigem = [string]$remoteGateway
            IPCliente = [string]$clientIp
            Tunel = [string]$name
            DialupIndex = if ($null -eq $dialupIndex) { '' } else { [string]$dialupIndex }
            Tipo = [string]$type
            Estado = [string]$state
        })
    }

    return @($rows | Sort-Object Usuario, Inicio)
}

function Get-ActiveIpsecSessions {
    $collectedAt = Get-Date
    $response = Get-ActiveIpsecApiResponse
    return @(ConvertTo-ActiveSessionRows -Response $response -CollectedAt $collectedAt)
}

function Test-UsernameExcluded {
    param([string]$Username)

    foreach ($excludedValue in $UsuariosExcluidos) {
        if ([string]::IsNullOrWhiteSpace($excludedValue)) { continue }
        foreach ($excluded in @($excludedValue -split '[,;]')) {
            if (-not [string]::IsNullOrWhiteSpace($excluded) -and $Username -ieq $excluded.Trim()) {
                return $true
            }
        }
    }
    return $false
}

function Test-SessionIdentity {
    param([object]$Expected, [object]$Current)

    return (
        $Expected.Usuario -ieq $Current.Usuario -and
        $Expected.Tunel -ieq $Current.Tunel -and
        $Expected.IPOrigem -ieq $Current.IPOrigem -and
        $Expected.IPCliente -ieq $Current.IPCliente -and
        $Expected.DialupIndex -ieq $Current.DialupIndex
    )
}

function Get-CurrentMatchingSessions {
    param([object]$Expected, [object[]]$CurrentSessions)

    return @(
        $CurrentSessions | Where-Object {
            (Test-SessionIdentity -Expected $Expected -Current $_) -and
            $_.DuracaoSegundos -ge $LimiteSegundos -and
            $_.Estado -match '^(?i:up|connected|established)$'
        }
    )
}

function Invoke-ClearIpsecGateway {
    param([string]$GatewayName)

    if ([string]::IsNullOrWhiteSpace($GatewayName)) {
        throw 'O nome dinamico do gateway esta vazio.'
    }

    $encodedVdom = [uri]::EscapeDataString($Vdom)
    $encodedGateway = [uri]::EscapeDataString($GatewayName)
    $uri = "$(Get-FortiApiBaseUrl)/api/v2/monitor/vpn/ike/clear?vdom=$encodedVdom&mkey=$encodedGateway"
    $response = Invoke-FortiApiRequest -Method Post -Uri $uri
    $status = Get-ObjectValue -Object $response -Names @('status')
    if ($status -and [string]$status -notmatch '^(?i)success$') {
        throw "A API de desconexao retornou status inesperado: $status."
    }
    return $response
}

function New-ResultRow {
    param([object]$Session, [string]$Result)

    return [PSCustomObject]@{
        Usuario = $Session.Usuario
        Inicio = $Session.Inicio
        Duracao = $Session.Duracao
        IPOrigem = $Session.IPOrigem
        IPCliente = $Session.IPCliente
        Tunel = $Session.Tunel
        Resultado = $Result
    }
}

function New-ExpiredSessionsReportHtml {
    param(
        [object[]]$Rows,
        [datetime]$CollectedAt,
        [string]$BlockReason
    )

    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $builder = [System.Text.StringBuilder]::new()
    [void]$builder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">')
    [void]$builder.Append('<h1 style="color:#1a365d;font-size:22px;">Controle de sessões VPN IPsec expiradas</h1>')
    [void]$builder.Append("<p>Coleta: <strong>$(Encode-Html $CollectedAt.ToString('dd/MM/yyyy HH:mm:ss'))</strong><br>FortiGate: <strong>$(Encode-Html $FortiGateIP)</strong><br>VDOM: <strong>$(Encode-Html $Vdom)</strong><br>Modo: <strong>$(Encode-Html $Modo)</strong><br>Limite: <strong>$LimiteHoras hora(s)</strong><br>Sessões elegíveis: <strong>$(@($Rows).Count)</strong></p>")

    if (-not [string]::IsNullOrWhiteSpace($BlockReason)) {
        [void]$builder.Append("<p style=""padding:12px;background:#fff5f5;border:1px solid #fc8181;color:#9b2c2c;""><strong>Execução bloqueada:</strong> $(Encode-Html $BlockReason)</p>")
    }

    if (@($Rows).Count -eq 0) {
        [void]$builder.Append('<p style="padding:12px;background:#f7fafc;border:1px solid #e2e8f0;">Nenhuma sessão acima do limite foi encontrada.</p>')
    }
    else {
        [void]$builder.Append('<table style="border-collapse:collapse;width:100%;max-width:1150px;border:1px solid #ccc;font-size:12px;line-height:1.2;"><thead><tr style="background:#1a365d;color:#fff;text-align:left;">')
        foreach ($label in @('Usuário', 'Início', 'Duração', 'IP de origem', 'IP do cliente', 'Túnel', 'Resultado')) {
            [void]$builder.Append(('<th style="padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;">{0}</th>' -f (Encode-Html $label)))
        }
        [void]$builder.Append('</tr></thead><tbody>')
        foreach ($row in $Rows) {
            $startText = if ($null -eq $row.Inicio) { '—' } else { $row.Inicio.ToString('dd/MM/yyyy HH:mm:ss') }
            [void]$builder.Append('<tr>')
            foreach ($value in @($row.Usuario, $startText, $row.Duracao, $row.IPOrigem, $row.IPCliente, $row.Tunel, $row.Resultado)) {
                $displayValue = if ([string]::IsNullOrWhiteSpace([string]$value)) { '—' } else { $value }
                [void]$builder.Append(('<td style="padding:4px 6px;border:1px solid #e2e8f0;">{0}</td>' -f (Encode-Html $displayValue)))
            }
            [void]$builder.Append('</tr>')
        }
        [void]$builder.Append('</tbody></table>')
    }

    $sentAtText = (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')
    [void]$builder.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #e2e8f0;color:#718096;font-size:12px;line-height:1.5;"">Enviado em: <strong>$(Encode-Html $sentAtText)</strong><br>Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(Encode-Html $routineName)</strong><br>Servidor: <strong>$(Encode-Html ([System.Environment]::MachineName))</strong></div>")
    [void]$builder.Append('</body></html>')
    return $builder.ToString()
}

try {
    $collectedAt = Get-Date
    Write-Host "Consultando sessoes VPN IPsec com limite de $LimiteHoras hora(s)..."
    $initialSessions = @(Get-ActiveIpsecSessions)
    $eligibleSessions = @(
        $initialSessions | Where-Object {
            $_.DuracaoSegundos -ge $LimiteSegundos -and
            $_.Estado -match '^(?i:up|connected|established)$' -and
            -not (Test-UsernameExcluded -Username $_.Usuario)
        }
    )

    $resultRows = [System.Collections.Generic.List[object]]::new()
    $blockReason = ''
    $blocked = $false

    if ($Modo -eq 'Executar' -and $eligibleSessions.Count -gt $MaximoDesconexoes) {
        $blocked = $true
        $blockReason = "Foram encontradas $($eligibleSessions.Count) sessoes elegiveis, acima do maximo permitido de $MaximoDesconexoes. Nenhuma desconexao foi solicitada."
        foreach ($session in $eligibleSessions) {
            $resultRows.Add((New-ResultRow -Session $session -Result 'Bloqueada pelo limite de segurança'))
        }
    }
    elseif ($Modo -eq 'Simular') {
        foreach ($session in $eligibleSessions) {
            $resultRows.Add((New-ResultRow -Session $session -Result 'Simulação: seria desconectada'))
        }
    }
    else {
        foreach ($target in $eligibleSessions) {
            try {
                Write-Host "Revalidando sessao de $($target.Usuario) no tunel $($target.Tunel)..."
                $currentSessions = @(Get-ActiveIpsecSessions)
                $matchingSessions = @(Get-CurrentMatchingSessions -Expected $target -CurrentSessions $currentSessions)
                if ($matchingSessions.Count -ne 1) {
                    $resultRows.Add((New-ResultRow -Session $target -Result "Ignorada: revalidação encontrou $($matchingSessions.Count) correspondência(s)"))
                    continue
                }

                $sameGatewaySessions = @($currentSessions | Where-Object { $_.Tunel -ieq $target.Tunel })
                if ([string]::IsNullOrWhiteSpace($target.Tunel) -or $sameGatewaySessions.Count -ne 1) {
                    $resultRows.Add((New-ResultRow -Session $target -Result "Ignorada: gateway dinâmico não é exclusivo ($($sameGatewaySessions.Count) sessão(ões))"))
                    continue
                }

                Write-Host "Solicitando desconexao de $($target.Usuario) no gateway $($target.Tunel)..."
                [void](Invoke-ClearIpsecGateway -GatewayName $target.Tunel)
                $resultRows.Add((New-ResultRow -Session $target -Result 'Desconexão solicitada; aguardando confirmação'))
            }
            catch {
                $resultRows.Add((New-ResultRow -Session $target -Result "Falha: $($_.Exception.Message)"))
            }
        }

        if ($IntervaloVerificacaoSegundos -gt 0 -and @($resultRows | Where-Object { $_.Resultado -like 'Desconexão solicitada*' }).Count -gt 0) {
            Start-Sleep -Seconds $IntervaloVerificacaoSegundos
        }

        $requestedRows = @($resultRows | Where-Object { $_.Resultado -like 'Desconexão solicitada*' })
        if ($requestedRows.Count -gt 0) {
            try {
                $finalSessions = @(Get-ActiveIpsecSessions)
                foreach ($row in $requestedRows) {
                    $stillActive = @($finalSessions | Where-Object {
                        $_.Usuario -ieq $row.Usuario -and
                        $_.Tunel -ieq $row.Tunel -and
                        $_.IPOrigem -ieq $row.IPOrigem -and
                        $_.IPCliente -ieq $row.IPCliente -and
                        $_.DuracaoSegundos -ge $LimiteSegundos
                    })
                    $row.Resultado = if ($stillActive.Count -eq 0) {
                        'Desconectada e confirmada'
                    }
                    else {
                        'Solicitada, mas a sessão ainda aparece ativa'
                    }
                }
            }
            catch {
                foreach ($row in $requestedRows) {
                    $row.Resultado = "Desconexão solicitada; falha ao confirmar: $($_.Exception.Message)"
                }
            }
        }
    }

    $html = New-ExpiredSessionsReportHtml -Rows @($resultRows) -CollectedAt $collectedAt -BlockReason $blockReason
    $subjectMode = if ($Modo -eq 'Simular') { 'SIMULAÇÃO' } else { 'EXECUÇÃO' }
    Send-PSPanelEmail -To $MailTo -Subject "[PSPanel] $subjectMode - sessões VPN IPsec acima de $LimiteHoras hora(s)" -Body $html -BodyAsHtml

    Write-Host "Rotina concluida. Modo: $Modo. Sessoes ativas: $($initialSessions.Count). Elegiveis: $($eligibleSessions.Count)."
    if ($blocked) { exit 1 }
    exit 0
}
catch {
    Write-Error "Falha ao controlar sessoes VPN IPsec expiradas: $($_.Exception.Message)"
    exit 1
}
