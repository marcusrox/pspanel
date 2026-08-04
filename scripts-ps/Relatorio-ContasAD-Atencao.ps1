<#
.SYNOPSIS
    Identifica contas do Active Directory que merecem atencao e envia um relatorio por email.

.DESCRIPTION
    Consulta usuarios do dominio atual, avalia criterios de seguranca e qualidade cadastral,
    consolida os achados por conta e envia um relatorio HTML. O script e somente leitura e
    tambem envia um estado satisfatorio quando nenhuma ocorrencia e encontrada.

.PARAMETER MailTo
    Um ou mais destinatarios. Enderecos em uma unica string podem ser separados por
    virgula ou ponto e virgula.

.PARAMETER InactiveDays
    Quantidade de dias sem logon para considerar uma conta comum inativa.

.PARAMETER PrivilegedInactiveDays
    Quantidade de dias sem logon para considerar uma conta privilegiada inativa.

.PARAMETER PasswordAgeDays
    Idade maxima da senha usada pelos criterios do relatorio.

.PARAMETER NeverLoggedGraceDays
    Tolerancia, em dias desde a criacao, para contas que nunca realizaram logon.

.EXAMPLE
    .\Relatorio-ContasAD-Atencao.ps1 -MailTo 'seguranca@exemplo.local'

.EXAMPLE
    .\Relatorio-ContasAD-Atencao.ps1 -MailTo 'seguranca@exemplo.local;rh@exemplo.local'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$MailTo,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$InactiveDays = 90,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$PrivilegedInactiveDays = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$PasswordAgeDays = 365,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$NeverLoggedGraceDays = 15
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-HtmlEncodedText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Fallback = ''
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        if ([string]::IsNullOrWhiteSpace($Fallback)) {
            $Fallback = "N$([char]0x00E3)o informado"
        }
        return [System.Net.WebUtility]::HtmlEncode($Fallback)
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-ReportDateText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return "N$([char]0x00E3)o informado"
    }

    try {
        return ([datetime]$Value).ToLocalTime().ToString('dd/MM/yyyy HH:mm:ss')
    }
    catch {
        throw 'Foi encontrada uma data invalida durante a geracao do relatorio.'
    }
}

function ConvertTo-NormalizedText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Trim().ToLowerInvariant()
}

function Get-CanonicalEmployeeType {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    $normalizedValue = ConvertTo-NormalizedText $Value
    switch ($normalizedValue) {
        'service' { return 'Service' }
        'funcionario' { return 'Funcionario' }
        'estagiario' { return 'Estagiario' }
        'terceirizado' { return 'Terceirizado' }
        default { return 'Sem tipo definido' }
    }
}

function Test-IsBlank {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    return ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value))
}

function Get-AgeInDays {
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Value,

        [Parameter(Mandatory = $true)]
        [datetime]$ReferenceTime
    )

    return [int][Math]::Floor(($ReferenceTime - $Value.ToLocalTime()).TotalDays)
}

function Get-OrganizationalPath {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [string]$DistinguishedName
    )

    if ([string]::IsNullOrWhiteSpace($DistinguishedName)) {
        return "N$([char]0x00E3)o informado"
    }

    $parts = @($DistinguishedName -split '(?<!\\),', 2)
    if ($parts.Count -lt 2) {
        return $DistinguishedName
    }

    return $parts[1]
}

function ConvertTo-MaskedIdentifier {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $trimmedValue = $Value.Trim()
    $atIndex = $trimmedValue.IndexOf('@')
    if ($atIndex -gt 0 -and $atIndex -lt ($trimmedValue.Length - 1)) {
        $localPart = $trimmedValue.Substring(0, $atIndex)
        $domainPart = $trimmedValue.Substring($atIndex + 1)
        $visiblePrefix = if ($localPart.Length -gt 1) { $localPart.Substring(0, 1) } else { $localPart }
        return "$visiblePrefix***@$domainPart"
    }

    if ($trimmedValue.Length -le 2) {
        return '***'
    }

    return "$($trimmedValue.Substring(0, 1))***$($trimmedValue.Substring($trimmedValue.Length - 1, 1))"
}

function Test-MailRecipients {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Addresses
    )

    $recipientCount = 0
    foreach ($addressGroup in $Addresses) {
        foreach ($address in ([string]$addressGroup -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($address -match '[\r\n]') {
                throw 'Um destinatario de email contem quebra de linha.'
            }

            try {
                [void][System.Net.Mail.MailAddress]::new($address)
            }
            catch {
                throw "Destinatario de email invalido: $address"
            }

            $recipientCount++
        }
    }

    if ($recipientCount -eq 0) {
        throw 'Nenhum destinatario de email foi informado.'
    }
    if ($recipientCount -gt 100) {
        throw 'O email excede o limite de 100 destinatarios.'
    }
}

function Add-AccountFinding {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Account,

        [Parameter(Mandatory = $true)]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Seguranca', 'Cadastro')]
        [string]$Category,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Critica', 'Alta', 'Media', 'Informativa')]
        [string]$Severity,

        [Parameter(Mandatory = $true)]
        [string]$Evidence,

        [Parameter(Mandatory = $true)]
        [string]$RecommendedAction
    )

    $severityRank = switch ($Severity) {
        'Critica' { 4 }
        'Alta' { 3 }
        'Media' { 2 }
        default { 1 }
    }

    $Account.Findings.Add([PSCustomObject]@{
        Code = $Code
        Category = $Category
        Severity = $Severity
        SeverityRank = $severityRank
        Evidence = $Evidence
        RecommendedAction = $RecommendedAction
    })

    if ($severityRank -gt $Account.MaxSeverityRank) {
        $Account.MaxSeverityRank = $severityRank
        $Account.MaxSeverity = $Severity
    }
}

function Get-SeverityStyle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Severity
    )

    switch ($Severity) {
        'Critica' { return @{ Background = '#fee2e2'; Border = '#b91c1c'; Text = '#991b1b' } }
        'Alta' { return @{ Background = '#ffedd5'; Border = '#ea580c'; Text = '#9a3412' } }
        'Media' { return @{ Background = '#fef3c7'; Border = '#d97706'; Text = '#92400e' } }
        default { return @{ Background = '#dbeafe'; Border = '#2563eb'; Text = '#1e40af' } }
    }
}

function New-AttentionReportHtml {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$AffectedAccounts,

        [Parameter(Mandatory = $true)]
        [int]$EvaluatedUserCount,

        [Parameter(Mandatory = $true)]
        [string]$DomainName,

        [Parameter(Mandatory = $true)]
        [string]$PdcEmulator,

        [Parameter(Mandatory = $true)]
        [datetime]$CollectedAt,

        [Parameter(Mandatory = $true)]
        [datetime]$SentAt,

        [Parameter(Mandatory = $true)]
        [int]$InactiveThreshold,

        [Parameter(Mandatory = $true)]
        [int]$PrivilegedInactiveThreshold,

        [Parameter(Mandatory = $true)]
        [int]$PasswordAgeThreshold,

        [Parameter(Mandatory = $true)]
        [int]$NeverLoggedGraceThreshold,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$AccountTypeSummary
    )

    $accounts = @($AffectedAccounts)
    $allFindings = @($accounts | ForEach-Object { $_.Findings })
    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $builder = [System.Text.StringBuilder]::new()
    $criterionDescriptions = @{
        'SEC-001' = "Conta habilitada cujo &uacute;ltimo logon aproximado ocorreu h&aacute; mais de $InactiveThreshold dias."
        'SEC-002' = "Conta habilitada, criada h&aacute; mais de $NeverLoggedGraceThreshold dias, que ainda n&atilde;o possui registro de logon."
        'SEC-003' = "Conta habilitada cuja senha foi alterada h&aacute; mais de $PasswordAgeThreshold dias ou que n&atilde;o possui PasswordLastSet v&aacute;lido."
        'SEC-004' = 'Conta habilitada, exceto Terceirizado e Service, com PasswordNeverExpires, permitindo que a senha nunca expire.'
        'SEC-005' = 'Conta habilitada com PasswordNotRequired, indicando que uma senha n&atilde;o &eacute; exigida.'
        'SEC-006' = 'Conta habilitada com a pr&eacute;-autentica&ccedil;&atilde;o Kerberos desabilitada.'
        'SEC-007' = 'Conta cuja data de expira&ccedil;&atilde;o j&aacute; passou, mas que permanece habilitada.'
        'SEC-008' = "Conta habilitada e privilegiada sem logon h&aacute; mais de $PrivilegedInactiveThreshold dias, ou sem qualquer logon depois da toler&acirc;ncia de $NeverLoggedGraceThreshold dias."
        'SEC-010' = "Conta habilitada com employeeType Service cuja senha excede $PasswordAgeThreshold dias ou n&atilde;o possui PasswordLastSet v&aacute;lido, independentemente da presen&ccedil;a de SPN."
        'CAD-001' = 'Conta habilitada com campos obrigat&oacute;rios ausentes conforme seu tipo. Service exige Description; Funcionario, Estagiario e contas sem tipo exigem Department, Title e Manager; Terceirizado exige Company e Manager.'
        'CAD-002' = 'Conta habilitada cujo atributo Manager aponta para um usu&aacute;rio desabilitado ou para uma refer&ecirc;ncia que n&atilde;o pode ser resolvida.'
        'CAD-003' = 'Conta envolvida em duplicidade de mail, UserPrincipalName ou employeeID, comparados sem diferenciar mai&uacute;sculas, min&uacute;sculas e espa&ccedil;os externos.'
        'CAD-004' = 'Conta habilitada com employeeType Estagiario ou Terceirizado, mas sem AccountExpirationDate.'
        'CAD-005' = 'Conta habilitada com employeeType vazio ou diferente dos valores permitidos, ou sem respons&aacute;vel identific&aacute;vel conforme seu tipo.'
        'CAD-006' = 'Conta que possui SPN, mas cujo employeeType n&atilde;o &eacute; Service. A aus&ecirc;ncia de SPN em uma conta Service n&atilde;o &eacute; considerada problema.'
    }

    [void]$builder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head>')
    [void]$builder.Append('<body style="margin:0;padding:24px;background:#f3f6f9;font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#1f2933;">')
    [void]$builder.Append('<div style="max-width:1100px;margin:0 auto;background:#ffffff;border:1px solid #d9e2ec;border-radius:8px;padding:24px;">')
    [void]$builder.Append('<h1 style="margin:0 0 18px;color:#173f5f;font-size:24px;">Contas do Active Directory que merecem aten&ccedil;&atilde;o</h1>')
    [void]$builder.Append('<table role="presentation" style="border-collapse:collapse;margin-bottom:18px;">')
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Dom&iacute;nio:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $DomainName)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">PDC Emulator:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $PdcEmulator)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Hor&aacute;rio da coleta:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $CollectedAt))</td></tr>")
    [void]$builder.Append('</table>')

    [void]$builder.Append('<div style="display:flex;flex-wrap:wrap;gap:10px;margin:0 0 18px;">')
    foreach ($metric in @(
        @{ Label = 'Usu&aacute;rios avaliados'; Value = $EvaluatedUserCount; Color = '#334e68' },
        @{ Label = 'Contas afetadas'; Value = $accounts.Count; Color = '#b45309' },
        @{ Label = 'Ocorr&ecirc;ncias'; Value = $allFindings.Count; Color = '#b91c1c' }
    )) {
        [void]$builder.Append("<div style=""min-width:150px;padding:12px 14px;border:1px solid #d9e2ec;border-top:4px solid $($metric.Color);border-radius:5px;background:#f8fafc;""><div style=""color:#52606d;font-size:12px;"">$($metric.Label)</div><div style=""margin-top:3px;font-size:22px;font-weight:700;color:$($metric.Color);"">$($metric.Value)</div></div>")
    }
    [void]$builder.Append('</div>')

    [void]$builder.Append('<h2 style="margin:24px 0 10px;color:#243b53;font-size:18px;">Contas avaliadas por tipo</h2>')
    [void]$builder.Append('<div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:18px;">')
    foreach ($typeSummary in $AccountTypeSummary) {
        [void]$builder.Append("<span style=""padding:6px 10px;background:#eaf2f8;border:1px solid #9fb3c8;border-radius:14px;color:#243b53;font-weight:700;"">$(ConvertTo-HtmlEncodedText $typeSummary.AccountType): $($typeSummary.Count)</span>")
    }
    [void]$builder.Append('</div>')

    [void]$builder.Append("<p style=""padding:12px;background:#eaf2f8;border:1px solid #9fb3c8;border-radius:4px;color:#243b53;line-height:1.6;""><strong>Limiares:</strong> inatividade comum: $InactiveThreshold dias; inatividade privilegiada: $PrivilegedInactiveThreshold dias; idade da senha: $PasswordAgeThreshold dias; toler&acirc;ncia sem primeiro logon: $NeverLoggedGraceThreshold dias.<br><strong>Tipos reconhecidos:</strong> Service, Funcionario, Estagiario e Terceirizado. Valores vazios ou diferentes s&atilde;o apresentados como Sem tipo definido.<br><strong>Observa&ccedil;&atilde;o:</strong> LastLogonDate deriva de um atributo replicado e representa uma data aproximada.</p>")

    if ($accounts.Count -eq 0) {
        [void]$builder.Append('<p style="padding:14px;background:#ecfdf3;border:1px solid #86d7a2;border-radius:4px;color:#166534;font-weight:600;">Nenhuma conta apresentou os crit&eacute;rios de aten&ccedil;&atilde;o avaliados nesta execu&ccedil;&atilde;o.</p>')
    }
    else {
        [void]$builder.Append('<h2 style="margin:24px 0 10px;color:#243b53;font-size:18px;">Resumo por severidade</h2>')
        [void]$builder.Append('<div style="display:flex;flex-wrap:wrap;gap:8px;margin-bottom:18px;">')
        foreach ($severity in @('Critica', 'Alta', 'Media', 'Informativa')) {
            $severityCount = @($allFindings | Where-Object { $_.Severity -eq $severity }).Count
            if ($severityCount -eq 0) {
                continue
            }
            $style = Get-SeverityStyle -Severity $severity
            [void]$builder.Append("<span style=""padding:6px 10px;background:$($style.Background);border:1px solid $($style.Border);border-radius:14px;color:$($style.Text);font-weight:700;"">$(ConvertTo-HtmlEncodedText $severity): $severityCount</span>")
        }
        [void]$builder.Append('</div>')

        [void]$builder.Append('<h2 style="margin:24px 0 10px;color:#243b53;font-size:18px;">Resumo por crit&eacute;rio</h2>')
        [void]$builder.Append('<table style="border-collapse:collapse;width:100%;margin-bottom:22px;border:1px solid #bcccdc;">')
        [void]$builder.Append('<thead><tr style="background:#334e68;color:#ffffff;text-align:left;"><th style="padding:7px 8px;border:1px solid #486581;">C&oacute;digo</th><th style="padding:7px 8px;border:1px solid #486581;">Descri&ccedil;&atilde;o do crit&eacute;rio</th><th style="padding:7px 8px;border:1px solid #486581;">Categoria</th><th style="padding:7px 8px;border:1px solid #486581;">Severidade</th><th style="padding:7px 8px;border:1px solid #486581;">Ocorr&ecirc;ncias</th></tr></thead><tbody>')
        foreach ($codeGroup in ($allFindings | Group-Object Code | Sort-Object Name)) {
            $sample = @($codeGroup.Group)[0]
            $severityLabels = @(
                $codeGroup.Group |
                    Sort-Object SeverityRank -Descending |
                    Select-Object -ExpandProperty Severity -Unique
            ) -join ' / '
            $criterionDescription = if ($criterionDescriptions.ContainsKey([string]$codeGroup.Name)) {
                [string]$criterionDescriptions[[string]$codeGroup.Name]
            }
            else {
                'Crit&eacute;rio de aten&ccedil;&atilde;o identificado durante a avalia&ccedil;&atilde;o.'
            }
            [void]$builder.Append("<tr><td style=""padding:6px 8px;border:1px solid #d9e2ec;font-weight:700;white-space:nowrap;"">$(ConvertTo-HtmlEncodedText $codeGroup.Name)</td><td style=""padding:6px 8px;border:1px solid #d9e2ec;line-height:1.5;"">$criterionDescription</td><td style=""padding:6px 8px;border:1px solid #d9e2ec;"">$(ConvertTo-HtmlEncodedText $sample.Category)</td><td style=""padding:6px 8px;border:1px solid #d9e2ec;white-space:nowrap;"">$(ConvertTo-HtmlEncodedText $severityLabels)</td><td style=""padding:6px 8px;border:1px solid #d9e2ec;text-align:center;"">$($codeGroup.Count)</td></tr>")
        }
        [void]$builder.Append('</tbody></table>')

        [void]$builder.Append('<h2 style="margin:24px 0 12px;color:#243b53;font-size:18px;">Detalhamento por conta</h2>')
        foreach ($account in $accounts) {
            $accountStyle = Get-SeverityStyle -Severity $account.MaxSeverity
            $accountTitle = ConvertTo-HtmlEncodedText $account.SamAccountName
            if (-not [string]::IsNullOrWhiteSpace([string]$account.DisplayName)) {
                $accountTitle = "$accountTitle &mdash; $(ConvertTo-HtmlEncodedText $account.DisplayName)"
            }

            [void]$builder.Append("<div style=""margin:0 0 16px;padding:16px 18px;background:#f8fafc;border:1px solid #bcccdc;border-left:5px solid $($accountStyle.Border);border-radius:6px;"">")
            [void]$builder.Append("<h3 style=""margin:0 0 10px;color:#173f5f;font-size:17px;overflow-wrap:anywhere;"">$accountTitle</h3>")
            [void]$builder.Append('<div style="margin-bottom:10px;">')
            foreach ($classification in $account.Classifications) {
                [void]$builder.Append("<span style=""display:inline-block;margin:0 6px 6px 0;padding:4px 8px;background:#eaf2f8;border-radius:12px;color:#243b53;font-size:12px;"">$(ConvertTo-HtmlEncodedText $classification)</span>")
            }
            [void]$builder.Append("<span style=""display:inline-block;margin:0 6px 6px 0;padding:4px 8px;background:$($accountStyle.Background);border-radius:12px;color:$($accountStyle.Text);font-size:12px;font-weight:700;"">Maior severidade: $(ConvertTo-HtmlEncodedText $account.MaxSeverity)</span>")
            [void]$builder.Append('</div>')
            [void]$builder.Append("<div style=""margin-bottom:12px;line-height:1.7;overflow-wrap:anywhere;""><strong>UPN:</strong> $(ConvertTo-HtmlEncodedText $account.UserPrincipalName)<br><strong>Habilitada:</strong> $(if ($account.Enabled) { 'Sim' } else { "N$([char]0x00E3)o" })")
            if ([string]$account.EmployeeType -cne [string]$account.AccountType) {
                [void]$builder.Append("<br><strong>employeeType original:</strong> $(ConvertTo-HtmlEncodedText -Value $account.EmployeeType -Fallback 'Vazio')")
            }
            [void]$builder.Append("<br><strong>Tipo principal:</strong> $(ConvertTo-HtmlEncodedText $account.AccountType)<br><strong>Unidade organizacional:</strong> $(ConvertTo-HtmlEncodedText $account.OrganizationalPath)")
            if ($account.PrivilegedGroups.Count -gt 0) {
                [void]$builder.Append("<br><strong>Grupos privilegiados:</strong> $(ConvertTo-HtmlEncodedText ($account.PrivilegedGroups -join ', '))")
            }
            [void]$builder.Append('</div>')

            foreach ($finding in ($account.Findings | Sort-Object @{ Expression = { $_.SeverityRank }; Descending = $true }, Code)) {
                $findingStyle = Get-SeverityStyle -Severity $finding.Severity
                [void]$builder.Append("<div style=""margin-top:9px;padding:10px 12px;background:$($findingStyle.Background);border:1px solid $($findingStyle.Border);border-radius:4px;line-height:1.55;"">")
                [void]$builder.Append("<div style=""font-weight:700;color:$($findingStyle.Text);"">$(ConvertTo-HtmlEncodedText $finding.Code) &mdash; $(ConvertTo-HtmlEncodedText $finding.Severity) / $(ConvertTo-HtmlEncodedText $finding.Category)</div>")
                [void]$builder.Append("<div><strong>Evid&ecirc;ncia:</strong> $(ConvertTo-HtmlEncodedText $finding.Evidence)</div>")
                [void]$builder.Append("<div><strong>A&ccedil;&atilde;o recomendada:</strong> $(ConvertTo-HtmlEncodedText $finding.RecommendedAction)</div>")
                [void]$builder.Append('</div>')
            }

            [void]$builder.Append('</div>')
        }
    }

    [void]$builder.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #d9e2ec;color:#627d98;font-size:12px;line-height:1.6;"">Este relat&oacute;rio &eacute; informativo e n&atilde;o realizou altera&ccedil;&otilde;es no Active Directory.<br>Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(ConvertTo-HtmlEncodedText $routineName)</strong><br>Enviado em: <strong>$(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $SentAt))</strong></div>")
    [void]$builder.Append('</div></body></html>')

    return $builder.ToString()
}

$stage = 'validacao dos parametros'

try {
    Test-MailRecipients -Addresses $MailTo

    $referenceTime = Get-Date

    $stage = 'carregamento do modulo ActiveDirectory'
    Import-Module ActiveDirectory -ErrorAction Stop

    $stage = 'descoberta do dominio e do PDC Emulator'
    $domain = Get-ADDomain -ErrorAction Stop
    $forest = Get-ADForest -ErrorAction Stop
    $domainName = [string]$domain.DNSRoot
    $pdcEmulator = [string]$domain.PDCEmulator
    $domainSid = [string]$domain.DomainSID.Value

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        throw 'O dominio atual nao possui um nome DNS disponivel.'
    }
    if ([string]::IsNullOrWhiteSpace($pdcEmulator)) {
        throw 'O PDC Emulator do dominio atual nao foi identificado.'
    }
    if ([string]::IsNullOrWhiteSpace($domainSid)) {
        throw 'O SID do dominio atual nao foi identificado.'
    }

    $rootDomain = if ($domainName.Equals([string]$forest.RootDomain, [System.StringComparison]::OrdinalIgnoreCase)) {
        $domain
    }
    else {
        Get-ADDomain -Identity ([string]$forest.RootDomain) -ErrorAction Stop
    }
    $rootDomainSid = [string]$rootDomain.DomainSID.Value
    $rootPdcEmulator = [string]$rootDomain.PDCEmulator
    if ([string]::IsNullOrWhiteSpace($rootDomainSid) -or [string]::IsNullOrWhiteSpace($rootPdcEmulator)) {
        throw 'Nao foi possivel identificar o dominio raiz da floresta.'
    }

    $stage = 'consulta das contas de usuario'
    $adProperties = @(
        'DisplayName',
        'UserPrincipalName',
        'mail',
        'Enabled',
        'Description',
        'employeeID',
        'employeeType',
        'Company',
        'Department',
        'Title',
        'Manager',
        'whenCreated',
        'PasswordLastSet',
        'LastLogonDate',
        'PasswordNeverExpires',
        'PasswordNotRequired',
        'DoesNotRequirePreAuth',
        'AccountExpirationDate',
        'ServicePrincipalName',
        'MemberOf',
        'PrimaryGroupID',
        'ObjectGUID',
        'DistinguishedName'
    )
    $users = @(Get-ADUser -Filter * -Server $pdcEmulator -Properties $adProperties -ErrorAction Stop)

    $usersByDn = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($user in $users) {
        $userDn = [string]$user.DistinguishedName
        if ([string]::IsNullOrWhiteSpace($userDn)) {
            throw 'A consulta retornou uma conta sem Distinguished Name.'
        }
        if ($usersByDn.ContainsKey($userDn)) {
            throw "A consulta retornou Distinguished Name duplicado para $([string]$user.SamAccountName)."
        }
        $usersByDn.Add($userDn, $user)
    }

    $stage = 'resolucao dos grupos privilegiados'
    $privilegedGroupSpecs = @(
        [PSCustomObject]@{ Sid = 'S-1-5-32-544'; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = "$domainSid-512"; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = "$rootDomainSid-519"; Server = $rootPdcEmulator },
        [PSCustomObject]@{ Sid = "$rootDomainSid-518"; Server = $rootPdcEmulator },
        [PSCustomObject]@{ Sid = 'S-1-5-32-548'; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = 'S-1-5-32-549'; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = 'S-1-5-32-551'; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = 'S-1-5-32-550'; Server = $pdcEmulator },
        [PSCustomObject]@{ Sid = "$domainSid-520"; Server = $pdcEmulator }
    )

    $privilegedGroupsByDn = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($groupSpec in $privilegedGroupSpecs) {
        $groupSidFilter = [string]$groupSpec.Sid
        $resolvedGroups = @(Get-ADGroup -Filter "SID -eq '$groupSidFilter'" -Server ([string]$groupSpec.Server) -Properties SID -ErrorAction Stop)
        foreach ($resolvedGroup in $resolvedGroups) {
            $groupDn = [string]$resolvedGroup.DistinguishedName
            if (-not $privilegedGroupsByDn.ContainsKey($groupDn)) {
                $privilegedGroupsByDn.Add($groupDn, [PSCustomObject]@{
                    Group = $resolvedGroup
                    Server = [string]$groupSpec.Server
                })
            }
        }
    }

    $dnsAdminGroups = @(Get-ADGroup -Filter "SamAccountName -eq 'DnsAdmins'" -Server $pdcEmulator -Properties SID -ErrorAction Stop)
    foreach ($dnsAdminGroup in $dnsAdminGroups) {
        $groupDn = [string]$dnsAdminGroup.DistinguishedName
        if (-not $privilegedGroupsByDn.ContainsKey($groupDn)) {
            $privilegedGroupsByDn.Add($groupDn, [PSCustomObject]@{
                Group = $dnsAdminGroup
                Server = $pdcEmulator
            })
        }
    }

    $privilegedGroupsByUserDn = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($userDn in $usersByDn.Keys) {
        $privilegedGroupsByUserDn.Add($userDn, [System.Collections.Generic.List[string]]::new())
    }

    foreach ($groupEntry in $privilegedGroupsByDn.Values) {
        $group = $groupEntry.Group
        $groupName = [string]$group.Name
        $groupSid = [string]$group.SID.Value
        $members = @(Get-ADGroupMember -Identity ([string]$group.DistinguishedName) -Recursive -Server ([string]$groupEntry.Server) -ErrorAction Stop)
        foreach ($member in $members) {
            $memberDn = [string]$member.DistinguishedName
            if ($usersByDn.ContainsKey($memberDn) -and -not $privilegedGroupsByUserDn[$memberDn].Contains($groupName)) {
                $privilegedGroupsByUserDn[$memberDn].Add($groupName)
            }
        }

        if ($groupSid.StartsWith("$domainSid-", [System.StringComparison]::OrdinalIgnoreCase)) {
            $lastDashIndex = $groupSid.LastIndexOf('-')
            $groupRid = 0
            if ($lastDashIndex -gt 0 -and [int]::TryParse($groupSid.Substring($lastDashIndex + 1), [ref]$groupRid)) {
                foreach ($user in $users) {
                    if ([int]$user.PrimaryGroupID -eq $groupRid) {
                        $userDn = [string]$user.DistinguishedName
                        if (-not $privilegedGroupsByUserDn[$userDn].Contains($groupName)) {
                            $privilegedGroupsByUserDn[$userDn].Add($groupName)
                        }
                    }
                }
            }
        }
    }

    $stage = 'classificacao das contas'
    $reportAccounts = [System.Collections.Generic.List[object]]::new()
    $reportAccountsByDn = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($user in $users) {
        $userDn = [string]$user.DistinguishedName
        $employeeType = [string]$user.employeeType
        $accountType = Get-CanonicalEmployeeType $employeeType
        $employeeTypeIssue = if ([string]::IsNullOrWhiteSpace($employeeType)) {
            'Ausente'
        }
        elseif ($accountType -eq 'Sem tipo definido') {
            'Invalido'
        }
        else {
            $null
        }
        $isService = $accountType -eq 'Service'
        $privilegedGroups = @($privilegedGroupsByUserDn[$userDn] | Sort-Object)
        $isPrivileged = $privilegedGroups.Count -gt 0
        $classifications = [System.Collections.Generic.List[string]]::new()

        $classifications.Add($accountType)
        if ($isPrivileged) { $classifications.Add('Privilegiada') }

        $account = [PSCustomObject]@{
            User = $user
            DistinguishedName = $userDn
            SamAccountName = [string]$user.SamAccountName
            DisplayName = [string]$user.DisplayName
            UserPrincipalName = [string]$user.UserPrincipalName
            EmployeeType = $employeeType
            AccountType = $accountType
            EmployeeTypeIssue = $employeeTypeIssue
            Enabled = [bool]$user.Enabled
            IsService = $isService
            IsPrivileged = $isPrivileged
            Classifications = @($classifications)
            PrivilegedGroups = $privilegedGroups
            OrganizationalPath = Get-OrganizationalPath -DistinguishedName $userDn
            Findings = [System.Collections.Generic.List[object]]::new()
            MaxSeverityRank = 0
            MaxSeverity = 'Informativa'
        }
        $reportAccounts.Add($account)
        $reportAccountsByDn.Add($userDn, $account)
    }

    $stage = 'resolucao dos gestores'
    $managerCache = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($user in $users) {
        $managerCache[[string]$user.DistinguishedName] = $user
    }
    foreach ($account in $reportAccounts) {
        $managerDn = [string]$account.User.Manager
        if ([string]::IsNullOrWhiteSpace($managerDn) -or $managerCache.ContainsKey($managerDn)) {
            continue
        }

        try {
            $resolvedManager = Get-ADUser -Identity $managerDn -Properties Enabled -ErrorAction Stop
            $managerCache[$managerDn] = $resolvedManager
        }
        catch {
            $errorType = $_.Exception.GetType().FullName
            if ($errorType -like '*ADIdentityNotFoundException') {
                $managerCache[$managerDn] = $null
            }
            else {
                throw
            }
        }
    }

    $stage = 'avaliacao dos criterios de seguranca e cadastro'
    foreach ($account in $reportAccounts) {
        $user = $account.User
        $isEnabled = [bool]$user.Enabled
        if (-not $isEnabled) {
            continue
        }

        $createdDate = if ($null -ne $user.whenCreated) { [datetime]$user.whenCreated } else { $null }
        $lastLogonDate = if ($null -ne $user.LastLogonDate) { [datetime]$user.LastLogonDate } else { $null }
        $passwordLastSet = if ($null -ne $user.PasswordLastSet) { [datetime]$user.PasswordLastSet } else { $null }
        $createdAge = if ($null -ne $createdDate) { Get-AgeInDays -Value $createdDate -ReferenceTime $referenceTime } else { $null }
        $lastLogonAge = if ($null -ne $lastLogonDate) { Get-AgeInDays -Value $lastLogonDate -ReferenceTime $referenceTime } else { $null }
        $passwordAge = if ($null -ne $passwordLastSet) { Get-AgeInDays -Value $passwordLastSet -ReferenceTime $referenceTime } else { $null }

        if ($isEnabled -and $null -ne $lastLogonAge -and $lastLogonAge -gt $InactiveDays) {
            Add-AccountFinding -Account $account -Code 'SEC-001' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence "Ultimo logon aproximado em $(ConvertTo-ReportDateText $lastLogonDate), ha $lastLogonAge dias." `
                -RecommendedAction 'Validar vinculo e necessidade da conta; desabilitar pelo processo oficial se o desuso for confirmado.'
        }

        if ($isEnabled -and $null -eq $lastLogonDate -and $null -ne $createdAge -and $createdAge -gt $NeverLoggedGraceDays) {
            Add-AccountFinding -Account $account -Code 'SEC-002' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence "Conta criada em $(ConvertTo-ReportDateText $createdDate), ha $createdAge dias, sem registro de logon." `
                -RecommendedAction 'Confirmar se a conta foi entregue e ainda e necessaria; revisar o processo de provisionamento.'
        }

        if ($isEnabled -and ($null -eq $passwordAge -or $passwordAge -gt $PasswordAgeDays)) {
            $passwordEvidence = if ($null -eq $passwordAge) {
                'PasswordLastSet ausente ou senha nunca definida.'
            }
            else {
                "Senha alterada em $(ConvertTo-ReportDateText $passwordLastSet), ha $passwordAge dias."
            }
            Add-AccountFinding -Account $account -Code 'SEC-003' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence $passwordEvidence `
                -RecommendedAction 'Revisar a necessidade e a politica aplicavel antes de qualquer troca de senha.'
        }

        if ($account.AccountType -notin @('Terceirizado', 'Service') -and [bool]$user.PasswordNeverExpires) {
            Add-AccountFinding -Account $account -Code 'SEC-004' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence 'A propriedade PasswordNeverExpires esta habilitada.' `
                -RecommendedAction 'Validar a excecao e adotar credencial gerenciada quando aplicavel.'
        }

        if ($isEnabled -and [bool]$user.PasswordNotRequired) {
            Add-AccountFinding -Account $account -Code 'SEC-005' -Category 'Seguranca' -Severity 'Critica' `
                -Evidence 'A propriedade PasswordNotRequired esta habilitada.' `
                -RecommendedAction 'Remover a configuracao insegura pelo processo de administracao autorizado.'
        }

        if ($isEnabled -and [bool]$user.DoesNotRequirePreAuth) {
            Add-AccountFinding -Account $account -Code 'SEC-006' -Category 'Seguranca' -Severity 'Critica' `
                -Evidence 'A pre-autenticacao Kerberos esta desabilitada para a conta.' `
                -RecommendedAction 'Exigir pre-autenticacao Kerberos, apos validar compatibilidade e dependencia da conta.'
        }

        if ($isEnabled -and $null -ne $user.AccountExpirationDate -and ([datetime]$user.AccountExpirationDate) -lt $referenceTime) {
            Add-AccountFinding -Account $account -Code 'SEC-007' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence "Conta expirada em $(ConvertTo-ReportDateText $user.AccountExpirationDate), mas ainda habilitada." `
                -RecommendedAction 'Confirmar o encerramento do acesso e desabilitar a conta pelo processo oficial.'
        }

        if ($isEnabled -and $account.IsPrivileged) {
            $privilegedInactive = (
                ($null -ne $lastLogonAge -and $lastLogonAge -gt $PrivilegedInactiveDays) -or
                ($null -eq $lastLogonDate -and $null -ne $createdAge -and $createdAge -gt $NeverLoggedGraceDays)
            )
            if ($privilegedInactive) {
                $privilegedEvidence = if ($null -ne $lastLogonAge) {
                    "Conta privilegiada sem logon ha $lastLogonAge dias. Grupos: $($account.PrivilegedGroups -join ', ')."
                }
                else {
                    "Conta privilegiada criada ha $createdAge dias e sem registro de logon. Grupos: $($account.PrivilegedGroups -join ', ')."
                }
                Add-AccountFinding -Account $account -Code 'SEC-008' -Category 'Seguranca' -Severity 'Critica' `
                    -Evidence $privilegedEvidence `
                    -RecommendedAction 'Revisar imediatamente a necessidade dos privilegios e remover acessos que nao sejam indispensaveis.'
            }
        }

        if ($account.IsService -and ($null -eq $passwordAge -or $passwordAge -gt $PasswordAgeDays)) {
            $serviceEvidence = "employeeType classificado como Service; $(@($user.ServicePrincipalName).Count) SPN(s); "
            if ($null -eq $passwordAge) {
                $serviceEvidence += 'PasswordLastSet ausente.'
            }
            else {
                $serviceEvidence += "senha com $passwordAge dias."
            }
            Add-AccountFinding -Account $account -Code 'SEC-010' -Category 'Seguranca' -Severity 'Alta' `
                -Evidence $serviceEvidence `
                -RecommendedAction 'Revisar uso e privilegios e avaliar migracao controlada para gMSA.'
        }

        if ($isEnabled) {
            $missingFields = [System.Collections.Generic.List[string]]::new()
            if (Test-IsBlank $user.Description) { $missingFields.Add('Description') }
            if (-not $account.IsService) {
                if ($account.AccountType -eq 'Terceirizado' -and (Test-IsBlank $user.Company)) { $missingFields.Add('Company') }
                if ($account.AccountType -ne 'Terceirizado') {
                    if (Test-IsBlank $user.Department) { $missingFields.Add('Department') }
                    if (Test-IsBlank $user.Title) { $missingFields.Add('Title') }
                }
                if (Test-IsBlank $user.Manager) { $missingFields.Add('Manager') }
            }
            if ($missingFields.Count -gt 0) {
                Add-AccountFinding -Account $account -Code 'CAD-001' -Category 'Cadastro' -Severity 'Media' `
                    -Evidence "Campos obrigatorios ausentes: $($missingFields -join ', ')." `
                    -RecommendedAction 'Completar os campos no sistema de origem responsavel pelo cadastro.'
            }

            $managerDn = [string]$user.Manager
            if (-not [string]::IsNullOrWhiteSpace($managerDn)) {
                $manager = $managerCache[$managerDn]
                if ($null -eq $manager) {
                    Add-AccountFinding -Account $account -Code 'CAD-002' -Category 'Cadastro' -Severity 'Media' `
                        -Evidence 'O Distinguished Name informado em Manager nao foi resolvido como usuario.' `
                        -RecommendedAction 'Corrigir a referencia de gestor no sistema de origem.'
                }
                elseif (-not [bool]$manager.Enabled) {
                    Add-AccountFinding -Account $account -Code 'CAD-002' -Category 'Cadastro' -Severity 'Alta' `
                        -Evidence "O gestor $([string]$manager.SamAccountName) esta desabilitado." `
                        -RecommendedAction 'Definir um gestor ativo e revisar o vinculo organizacional.'
                }
            }

            if ($account.AccountType -in @('Estagiario', 'Terceirizado') -and $null -eq $user.AccountExpirationDate) {
                Add-AccountFinding -Account $account -Code 'CAD-004' -Category 'Cadastro' -Severity 'Alta' `
                    -Evidence "Conta classificada como $($account.AccountType) sem data de expiracao." `
                    -RecommendedAction 'Definir expiracao conforme o vinculo e a politica de acesso temporario.'
            }

            $missingGovernance = [System.Collections.Generic.List[string]]::new()
            if ($account.EmployeeTypeIssue -eq 'Ausente') {
                $missingGovernance.Add('employeeType ausente')
            }
            elseif ($account.EmployeeTypeIssue -eq 'Invalido') {
                $missingGovernance.Add("employeeType invalido '$($account.EmployeeType)'")
            }
            if ($account.IsService) {
                if (Test-IsBlank $user.Description) {
                    $missingGovernance.Add('responsavel ou contexto em Description')
                }
            }
            elseif (Test-IsBlank $user.Manager) {
                $missingGovernance.Add('responsavel em Manager')
            }
            if ($missingGovernance.Count -gt 0) {
                Add-AccountFinding -Account $account -Code 'CAD-005' -Category 'Cadastro' -Severity 'Media' `
                    -Evidence "Governanca incompleta: $($missingGovernance -join ', ')." `
                    -RecommendedAction 'Registrar o tipo e o responsavel da conta no cadastro corporativo.'
            }
        }

        $servicePrincipalNameCount = @($user.ServicePrincipalName).Count
        if (-not $account.IsService -and $servicePrincipalNameCount -gt 0) {
            $typeEvidence = if ($account.AccountType -eq 'Sem tipo definido') {
                if ($account.EmployeeTypeIssue -eq 'Ausente') { 'employeeType ausente' } else { "employeeType invalido '$($account.EmployeeType)'" }
            }
            else {
                "employeeType classificado como $($account.AccountType)"
            }
            Add-AccountFinding -Account $account -Code 'CAD-006' -Category 'Cadastro' -Severity 'Media' `
                -Evidence "$typeEvidence; a conta possui $servicePrincipalNameCount SPN(s)." `
                -RecommendedAction 'Confirmar a finalidade da conta e usar employeeType Service somente se ela for de fato uma conta de servico.'
        }
    }

    $stage = 'deteccao de identificadores duplicados'
    $duplicateEvidenceByDn = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($account in $reportAccounts) {
        $duplicateEvidenceByDn.Add($account.DistinguishedName, [System.Collections.Generic.List[string]]::new())
    }

    foreach ($fieldSpec in @(
        [PSCustomObject]@{ Property = 'mail'; Label = 'mail'; Mask = $true },
        [PSCustomObject]@{ Property = 'UserPrincipalName'; Label = 'UserPrincipalName'; Mask = $true },
        [PSCustomObject]@{ Property = 'employeeID'; Label = 'employeeID'; Mask = $false }
    )) {
        $valueIndex = @{}
        foreach ($account in $reportAccounts) {
            $originalValue = [string]$account.User.($fieldSpec.Property)
            $normalizedValue = ConvertTo-NormalizedText $originalValue
            if ([string]::IsNullOrWhiteSpace($normalizedValue)) {
                continue
            }
            if (-not $valueIndex.ContainsKey($normalizedValue)) {
                $valueIndex[$normalizedValue] = [System.Collections.Generic.List[object]]::new()
            }
            $valueIndex[$normalizedValue].Add($account)
        }

        foreach ($normalizedValue in $valueIndex.Keys) {
            $duplicateAccounts = @($valueIndex[$normalizedValue])
            if ($duplicateAccounts.Count -lt 2) {
                continue
            }
            $displayValue = if ([bool]$fieldSpec.Mask) {
                ConvertTo-MaskedIdentifier -Value ([string]$duplicateAccounts[0].User.($fieldSpec.Property))
            }
            else {
                [string]$duplicateAccounts[0].User.($fieldSpec.Property)
            }
            foreach ($duplicateAccount in $duplicateAccounts) {
                $duplicateEvidenceByDn[$duplicateAccount.DistinguishedName].Add(
                    "$($fieldSpec.Label) '$displayValue' aparece em $($duplicateAccounts.Count) objetos"
                )
            }
        }
    }

    foreach ($account in $reportAccounts) {
        if (-not $account.Enabled) {
            continue
        }

        $duplicateEvidence = $duplicateEvidenceByDn[$account.DistinguishedName]
        if ($duplicateEvidence.Count -gt 0) {
            Add-AccountFinding -Account $account -Code 'CAD-003' -Category 'Cadastro' -Severity 'Alta' `
                -Evidence "$($duplicateEvidence -join '; ')." `
                -RecommendedAction 'Validar a identidade correta e eliminar duplicidades no sistema de origem.'
        }
    }

    $stage = 'consolidacao do relatorio'
    $affectedAccounts = @(
        $reportAccounts |
            Where-Object { $_.Findings.Count -gt 0 } |
            Sort-Object @{ Expression = { $_.MaxSeverityRank }; Descending = $true }, @{ Expression = { ([string]$_.SamAccountName).ToLowerInvariant() } }
    )
    $findingCount = @($affectedAccounts | ForEach-Object { $_.Findings }).Count
    $accountTypeSummary = @(
        foreach ($accountTypeName in @('Service', 'Funcionario', 'Estagiario', 'Terceirizado', 'Sem tipo definido')) {
            [PSCustomObject]@{
                AccountType = $accountTypeName
                Count = @($reportAccounts | Where-Object { $_.AccountType -eq $accountTypeName }).Count
            }
        }
    )
    $collectedAt = Get-Date
    $sentAt = Get-Date

    $stage = 'geracao do relatorio HTML'
    $emailBody = New-AttentionReportHtml `
        -AffectedAccounts $affectedAccounts `
        -EvaluatedUserCount $users.Count `
        -DomainName $domainName `
        -PdcEmulator $pdcEmulator `
        -CollectedAt $collectedAt `
        -SentAt $sentAt `
        -InactiveThreshold $InactiveDays `
        -PrivilegedInactiveThreshold $PrivilegedInactiveDays `
        -PasswordAgeThreshold $PasswordAgeDays `
        -NeverLoggedGraceThreshold $NeverLoggedGraceDays `
        -AccountTypeSummary $accountTypeSummary

    $attentionText = "aten$([char]0x00E7)$([char]0x00E3)o"
    $emailSubject = if ($affectedAccounts.Count -eq 0) {
        "PS Panel - Nenhuma conta do AD requer $attentionText"
    }
    else {
        "PS Panel - Contas do AD que merecem $attentionText ($($affectedAccounts.Count))"
    }

    $stage = 'carregamento do modulo de email'
    $emailModulePath = Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1'
    Import-Module $emailModulePath -Force -ErrorAction Stop

    $stage = 'envio do email'
    Send-PSPanelEmail -To $MailTo -Subject $emailSubject -Body $emailBody -BodyAsHtml -ErrorAction Stop

    Write-Output "Dominio consultado: $domainName"
    Write-Output "PDC Emulator: $pdcEmulator"
    Write-Output "Usuarios avaliados: $($users.Count)"
    Write-Output "Contas que merecem atencao: $($affectedAccounts.Count)"
    Write-Output "Ocorrencias encontradas: $findingCount"
    Write-Output 'Relatorio enviado por email com sucesso.'
    exit 0
}
catch {
    $errorText = [string]$_.Exception.Message
    $errorText = ($errorText -replace '[\r\n]+', ' ').Trim()
    if ($errorText.Length -gt 500) {
        $errorText = $errorText.Substring(0, 500)
    }
    [Console]::Error.WriteLine("Erro durante $stage`: $errorText")
    exit 1
}
