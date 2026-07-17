<#
.SYNOPSIS
    Monitora sessões SSL VPN no FortiGate e envia alerta por e-mail quando a duração excede o limite.

.DESCRIPTION
    Conecta por SSH (Posh-SSH), executa "get vpn ssl monitor", interpreta a tabela "SSL-VPN sessions"
    (duração em segundos) e, se houver usuários acima do limite configurado, monta um e-mail HTML e envia
    pelo modulo compartilhado PSPanel.Email. O usuário e a senha do FortiGate são recebidos por parâmetros obrigatórios,
    enquanto o endereço do equipamento e o destinatário do alerta podem ser substituídos opcionalmente.

.PARAMETER FortiUser
    Usuário SSH do FortiGate.

.PARAMETER FortiPassword
    Senha SSH do FortiGate.

.PARAMETER FortiGateIP
    Endereço IP ou nome do FortiGate. O valor padrão é 10.35.0.1.

.PARAMETER MailTo
    Destinatário do alerta por e-mail. O valor padrão é analistasusi@desenbahia.ba.gov.br.

.EXAMPLE
    .\Monitoramento-VPN.ps1 -FortiUser "usuario" -FortiPassword "senha"
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiUser,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiPassword,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FortiGateIP = "10.35.0.1",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$MailTo = 'analistasusi@desenbahia.ba.gov.br'
)

# ---------- CONFIGURAÇÕES ----------
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
    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $sentAtText = $Quando.ToString('dd/MM/yyyy HH:mm:ss')

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head><body style="font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#222;">')
    [void]$sb.Append('<h1 style="color:#1a365d;font-size:22px;">Alerta de usuários SSL VPN</h1>')
    [void]$sb.Append("<p>Coleta: <strong>$(Encode-Html $sentAtText)</strong><br>FortiGate: <strong>$(Encode-Html $FortiIp)</strong><br>Usuários encontrados: <strong>$n</strong><br>Limite configurado: <strong>$(Encode-Html ([string]$LimiteHorasRef)) horas</strong></p>")
    [void]$sb.Append("<p style=""padding:12px;background:#fffaf0;border:1px solid #ed8936;color:#7b341e;"">Foram encontrados <strong>$n</strong> usuário(s) conectados há mais tempo que o limite configurado.</p>")
    [void]$sb.Append('<table style="border-collapse:collapse;width:100%;max-width:1050px;border:1px solid #ccc;font-size:12px;line-height:1.2;">')
    [void]$sb.Append('<thead><tr style="background:#1a365d;color:#fff;text-align:left;">')
    foreach ($h in @('Usuário', 'IP de origem', 'IP do túnel', 'Duração', 'Horas conectado', 'Segundos')) {
        [void]$sb.Append("<th style=""padding:5px 6px;border:1px solid #2c5282;white-space:nowrap;"">$h</th>")
    }
    [void]$sb.Append('</tr></thead><tbody>')
    $i = 0
    foreach ($u in $lista) {
        $bg = if (($i % 2) -eq 0) { '#f7fafc' } else { '#edf2f7' }
        $i++
        [void]$sb.Append("<tr style=""background:$bg;"">")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;"">$(Encode-Html $u.Usuario)</td>")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;font-family:Consolas,monospace;"">$(Encode-Html $u.IP)</td>")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;font-family:Consolas,monospace;"">$(Encode-Html $u.TunnelIP)</td>")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;"">$(Encode-Html $u.Duracao)</td>")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;text-align:right;"">$(Encode-Html ([string]$u.Horas))</td>")
        [void]$sb.Append("<td style=""padding:4px 6px;border:1px solid #e2e8f0;text-align:right;"">$(Encode-Html ([string]$u.Duracao_s))</td>")
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    [void]$sb.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #e2e8f0;color:#718096;font-size:12px;line-height:1.5;"">Enviado em: <strong>$(Encode-Html $sentAtText)</strong><br>Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(Encode-Html $routineName)</strong></div>")
    [void]$sb.Append('</body></html>')
    return $sb.ToString()
}

# Requer o módulo Posh-SSH 4.x prerelease ou superior para compatibilidade SSH com o FortiGate.
# Instale com: Install-Module -Name Posh-SSH -AllowPrerelease -Force
$RequiredPoshSshVersion = [version]"4.0.0"
$InstalledPoshSsh = Get-Module -ListAvailable -Name Posh-SSH |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $InstalledPoshSsh -or $InstalledPoshSsh.Version -lt $RequiredPoshSshVersion) {
    Write-Host "Módulo Posh-SSH 4.x não encontrado. Instalando versão prerelease..."
    try {
        Install-Module -Name Posh-SSH -AllowPrerelease -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        Write-Host "Módulo Posh-SSH instalado com sucesso."
    }
    catch {
        Write-Error "Erro ao instalar o módulo Posh-SSH: $_"
        exit 1
    }
}

try {
    Import-Module Posh-SSH -Force -ErrorAction Stop
}
catch {
    Write-Error "Erro ao carregar o módulo Posh-SSH: $_"
    exit 1
}

Import-Module (Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1') -Force -ErrorAction Stop

# ---------- CRIA CREDENCIAL SSH ----------
$SecurePassword = ConvertTo-SecureString $FortiPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($FortiUser, $SecurePassword)
$SSHSession = $null

try {

    # ---------- CONEXÃO SSH ----------
    $SSHSession = New-SSHSession `
        -ComputerName $FortiGateIP `
        -Credential $Credential `
        -AcceptKey `
        -Force `
        -ConnectionTimeout 30 `
        -ErrorAction Stop

    if ($null -eq $SSHSession -or $null -eq $SSHSession.SessionId) {
        throw "Sessão SSH não foi criada."
    }

    # ---------- EXECUTA COMANDO ----------
    $Command = "get vpn ssl monitor"

    $Result = Invoke-SSHCommand `
        -SessionId $SSHSession.SessionId `
        -Command $Command `
        -ErrorAction Stop

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

        try {
            Send-PSPanelEmail `
                -To $MailTo `
                -Subject "[ALERTA] Usuários SSL VPN conectados há mais de $LimiteHoras horas" `
                -Body $BodyHtml `
                -BodyAsHtml
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
        Remove-SSHSession -SessionId $SSHSession.SessionId -ErrorAction SilentlyContinue | Out-Null
    }
}
