<#
.SYNOPSIS
    Monitora sessões SSL VPN no FortiGate e envia alerta por e-mail quando a duração excede o limite.

.DESCRIPTION
    Conecta por SSH (Posh-SSH), executa "get vpn ssl monitor", interpreta a tabela "SSL-VPN sessions"
    (duração em segundos) e, se houver usuários acima do limite configurado, monta um e-mail HTML e envia
    via System.Net.Mail.SMTPClient. IPs, credenciais, SMTP e limite de horas estão nas variáveis no início.

.PARAMETER Nenhum
    Este script não declara param(). Ajuste FortiGateIP, credenciais, SMTP e LimiteHoras no corpo do arquivo.

.EXAMPLE
    .\Monitoramento-VPN.ps1
#>
# ---------- CONFIGURAÇÕES ----------
$FortiGateIP   = "10.35.0.1"
$FortiUser     = "msouza"
$FortiPassword = "mmdmmd"

# SMTP
$SmtpServer = "mail.desenbahia.ba.gov.br"
$SmtpPort   = 25
#$SmtpPort   = 587
$MailFrom   = "fortigate@desenbahia.ba.gov.br"
$MailTo     = "analistasusi@desenbahia.ba.gov.br"
#$MailTo     = "msouza@desenbahia.ba.gov.br"

# Porta 25 em relay interno: em geral sem TLS (EnableSsl = false).
# Para 587 com STARTTLS, use $true. Se o certificado for interno/inválido, só então avalie $SmtpIgnoreCertificateErrors.
$SmtpUseSsl = $false
$SmtpIgnoreCertificateErrors = $false

# Credenciais SMTP (só necessário se o servidor exigir autenticação)
$SmtpUser     = "usuario_smtp"
$SmtpPassword = "senha_smtp"
$SmtpUseCredential = $false

# Limite em horas
$LimiteHoras = 1

# ---------- FUNÇÃO PARA CONVERTER TEMPO (horas) ----------
# Aceita: segundos (inteiro, ex.: saída "Duration" de get vpn ssl monitor)
# ou texto legado: 1d, 2h, 30m
function Convert-TimeToHours {
    param([string]$Tempo)

    $Tempo = $Tempo.Trim()
    if ($Tempo -match '^\d+$') {
        return [double][int64]$Tempo / 3600.0
    }

    $dias = 0
    $horas = 0
    $minutos = 0

    if ($Tempo -match '(\d+)d') {
        $dias = [int]$matches[1]
    }

    if ($Tempo -match '(\d+)h') {
        $horas = [int]$matches[1]
    }

    if ($Tempo -match '(\d+)m') {
        $minutos = [int]$matches[1]
    }

    return ($dias * 24) + $horas + ($minutos / 60)
}

function Encode-Html {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    return [System.Net.WebUtility]::HtmlEncode($Text)
}

function New-VpnAlertEmailHtml {
    param(
        [System.Collections.IEnumerable]$Usuarios,
        [double]$LimiteHorasRef,
        [string]$FortiIp,
        [datetime]$Quando = (Get-Date)
    )

    $lista = @($Usuarios)
    $n = $lista.Count

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">')
    [void]$sb.Append("<p>Foram encontrados <strong>$n</strong> usuário(s) SSL VPN conectados há mais de <strong>$LimiteHorasRef</strong> hora(s).</p>")
    [void]$sb.Append('<table style="border-collapse:collapse;width:100%;max-width:900px;border:1px solid #ccc;">')
    [void]$sb.Append('<thead><tr style="background:#1a365d;color:#fff;text-align:left;">')
    foreach ($h in @('Usuário', 'IP de origem', 'IP do túnel', 'Duração', 'Horas conectado', 'Segundos')) {
        [void]$sb.Append("<th style=""padding:10px 12px;border:1px solid #2c5282;"">$h</th>")
    }
    [void]$sb.Append('</tr></thead><tbody>')
    $i = 0
    foreach ($u in $lista) {
        $bg = if (($i % 2) -eq 0) { '#f7fafc' } else { '#edf2f7' }
        $i++
        [void]$sb.Append("<tr style=""background:$bg;"">")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;"">$(Encode-Html $u.Usuario)</td>")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;font-family:Consolas,monospace;"">$(Encode-Html $u.IP)</td>")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;font-family:Consolas,monospace;"">$(Encode-Html $u.TunnelIP)</td>")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;"">$(Encode-Html $u.Duracao)</td>")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;text-align:right;"">$(Encode-Html ([string]$u.Horas))</td>")
        [void]$sb.Append("<td style=""padding:8px 12px;border:1px solid #e2e8f0;text-align:right;"">$(Encode-Html ([string]$u.Duracao_s))</td>")
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    [void]$sb.Append("<p style=""margin-top:16px;color:#4a5568;font-size:13px;"">Data/hora: <strong>$(Encode-Html ($Quando.ToString('yyyy-MM-dd HH:mm:ss')))</strong><br>Firewall: <strong>$(Encode-Html $FortiIp)</strong></p>")
    [void]$sb.Append('</body></html>')
    return $sb.ToString()
}

# Envio via System.Net.Mail (evita Send-MailMessage, obsoleto no PowerShell 7+).
function Send-MonitoramentoVpnMail {
    param(
        [string]$From,
        [string]$To,
        [string]$Subject,
        [string]$BodyText,
        [string]$SmtpHost,
        [int]$SmtpPortNumber,
        [bool]$UseSsl,
        [bool]$IgnoreCertificateErrors,
        [pscredential]$MailCredential = $null,
        [bool]$UseCredential = $false,
        [bool]$IsBodyHtml = $false
    )

    $mail = New-Object System.Net.Mail.MailMessage
    try {
        $mail.From = New-Object System.Net.Mail.MailAddress($From)
        foreach ($addr in ($To -split '[;,]\s*' | Where-Object { $_ })) {
            $mail.To.Add($addr.Trim())
        }
        $mail.Subject = $Subject
        $mail.Body = $BodyText
        $mail.BodyEncoding = [System.Text.UTF8Encoding]::new($false)
        $mail.SubjectEncoding = [System.Text.UTF8Encoding]::new($false)
        $mail.IsBodyHtml = $IsBodyHtml

        $client = New-Object System.Net.Mail.SmtpClient($SmtpHost, $SmtpPortNumber)
        $client.EnableSsl = $UseSsl
        if ($UseCredential -and $null -ne $MailCredential) {
            $client.Credentials = $MailCredential.GetNetworkCredential()
        }

        $prevCertCb = $null
        if ($IgnoreCertificateErrors) {
            $prevCertCb = [System.Net.ServicePointManager]::ServerCertificateValidationCallback
            [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
        try {
            $client.Send($mail)
        }
        finally {
            if ($null -ne $prevCertCb) {
                [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $prevCertCb
            }
            $client.Dispose()
        }
    }
    finally {
        $mail.Dispose()
    }
}

# ---------- CRIA CREDENCIAL SSH ----------
$SecurePassword = ConvertTo-SecureString $FortiPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($FortiUser, $SecurePassword)

# ---------- IMPORTA MÓDULO SSH ----------
Import-Module Posh-SSH

try {

    # ---------- CONEXÃO SSH ----------
    $SSHSession = New-SSHSession `
        -ComputerName $FortiGateIP `
        -Credential $Credential `
        -AcceptKey `
        -ConnectionTimeout 30

    # ---------- EXECUTA COMANDO ----------
    $Command = "get vpn ssl monitor"

    $Result = Invoke-SSHCommand `
        -SessionId $SSHSession.SessionId `
        -Command $Command

    # Saída pode vir como string multilinha ou coleção de linhas
    $textoSaida = @($Result.Output) -join "`n"
    $Linhas = $textoSaida -split "`r?`n" | ForEach-Object { $_.TrimEnd("`r") }

    # ---------- PROCESSA SAÍDA (formato tabela | do FortiOS) ----------
    # Seção relevante: "SSL-VPN sessions:" com colunas Index|User|Group|Source IP|Duration|...
    # Duration = segundos de túnel
    $UsuariosAcimaLimite = @()
    $emSessoesSsl = $false
    $pularCabecalhoTabela = $false

    foreach ($Linha in $Linhas) {
        if ([string]::IsNullOrWhiteSpace($Linha)) {
            if ($emSessoesSsl) { $emSessoesSsl = $false }
            continue
        }

        if ($Linha -match 'SSL-VPN sessions\s*:') {
            $emSessoesSsl = $true
            $pularCabecalhoTabela = $true
            continue
        }

        if (-not $emSessoesSsl) { continue }

        if ($pularCabecalhoTabela) {
            if ($Linha -match '\|Index\|') {
                $pularCabecalhoTabela = $false
            }
            continue
        }

        # Linha de dados: |idx|usuario|grupo|IP origem|duracao_seg|I/O|IP tunel|
        if ($Linha -notmatch '^\|\d+\|') { continue }

        $campos = $Linha.Trim('|').Split('|')
        if ($campos.Count -lt 6) { continue }

        $UsuarioAtual = $campos[1].Trim()
        $IPAtual      = $campos[3].Trim()
        $TempoAtual   = $campos[4].Trim()
        $TunnelIp     = if ($campos.Count -ge 7) { $campos[6].Trim() } else { '' }

        if ($UsuarioAtual -eq '' -or $TempoAtual -notmatch '^\d+$') { continue }

        $HorasConectado = Convert-TimeToHours $TempoAtual

        if ($HorasConectado -ge $LimiteHoras) {
            $ts = [TimeSpan]::FromSeconds([int64]$TempoAtual)
            $duracaoHumana = $ts.ToString()
            $UsuariosAcimaLimite += [PSCustomObject]@{
                Usuario   = $UsuarioAtual
                IP        = $IPAtual
                Duracao_s = $TempoAtual
                Duracao   = $duracaoHumana
                TunnelIP  = $TunnelIp
                Horas     = [math]::Round($HorasConectado, 2)
            }
        }
    }

    # ---------- ENVIA EMAIL ----------
    if ($UsuariosAcimaLimite.Count -gt 0) {

        $BodyHtml = New-VpnAlertEmailHtml -Usuarios $UsuariosAcimaLimite -LimiteHorasRef $LimiteHoras -FortiIp $FortiGateIP -Quando (Get-Date)

        $smtpCred = $null
        if ($SmtpUseCredential) {
            $smtpCred = New-Object System.Management.Automation.PSCredential (
                $SmtpUser,
                (ConvertTo-SecureString $SmtpPassword -AsPlainText -Force)
            )
        }

        try {
            Send-MonitoramentoVpnMail `
                -From $MailFrom `
                -To $MailTo `
                -Subject "[ALERTA] Usuários SSL VPN conectados há mais de $LimiteHoras horas" `
                -BodyText $BodyHtml `
                -SmtpHost $SmtpServer `
                -SmtpPortNumber $SmtpPort `
                -UseSsl:$SmtpUseSsl `
                -IgnoreCertificateErrors:$SmtpIgnoreCertificateErrors `
                -MailCredential $smtpCred `
                -UseCredential:$SmtpUseCredential `
                -IsBodyHtml:$true
            Write-Host "E-mail enviado com sucesso."
        }
        catch {
            Write-Host "Falha ao enviar e-mail: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Nenhum usuário acima do limite encontrado."
    }

}
catch {
    Write-Host "Erro: $($_.Exception.Message)"
}
finally {

    # ---------- FECHA SESSÃO SSH ----------
    if ($SSHSession) {
        Remove-SSHSession -SessionId $SSHSession.SessionId | Out-Null
    }
}