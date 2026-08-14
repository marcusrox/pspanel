<#
.SYNOPSIS
    Consulta situacoes de bloqueio, senha expirada e desativacao de contas no Active Directory.

.DESCRIPTION
    Descobre o dominio atual, consulta todos os seus controladores de dominio e consolida
    as contas de usuario bloqueadas por autenticacao invalida e os atributos locais de
    senha incorreta. No PDC Emulator, tambem consulta contas com senha expirada e contas
    desativadas. O relatorio HTML apresenta cada situacao em um topico independente. O
    script e somente leitura e envia o relatorio mesmo quando as listas estao vazias.

.PARAMETER MailTo
    Um ou mais destinatarios. Enderecos em uma unica string podem ser separados por
    virgula ou ponto e virgula.

.EXAMPLE
    .\Relatorio-ContasAD-Bloqueadas.ps1 -MailTo 'seguranca@exemplo.local'

.EXAMPLE
    .\Relatorio-ContasAD-Bloqueadas.ps1 -MailTo 'seguranca@exemplo.local;suporte@exemplo.local'

.INPUTS
    Nenhum.

.OUTPUTS
    Mensagens de resumo no pipeline e um relatorio HTML enviado por email.

.NOTES
    Requer Windows PowerShell, modulo ActiveDirectory, acesso de leitura ao dominio e
    configuracao valida do modulo PSPanel.Email.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$MailTo
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
        return "N$([char]0x00E3)o informado"
    }
}

function ConvertFrom-ActiveDirectoryFileTime {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $fileTime = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$fileTime) -or $fileTime -le 0) {
        return $null
    }

    try {
        return [datetime]::FromFileTimeUtc($fileTime).ToLocalTime()
    }
    catch {
        return $null
    }
}

function ConvertFrom-ActiveDirectoryExpirationTime {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $fileTime = 0L
    if (-not [long]::TryParse([string]$Value, [ref]$fileTime)) {
        return $null
    }
    if ($fileTime -le 0 -or $fileTime -eq [long]::MaxValue) {
        return $null
    }

    try {
        return [datetime]::FromFileTimeUtc($fileTime).ToLocalTime()
    }
    catch {
        return $null
    }
}

function ConvertTo-HtmlEncodedMultilineText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $encodedValue = [System.Net.WebUtility]::HtmlEncode($Value)
    return ($encodedValue -replace '\r\n|\r|\n', '<br>')
}

function Add-AccountStatusTableHtml {
    param(
        [Parameter(Mandatory = $true)]
        [System.Text.StringBuilder]$Builder,

        [Parameter(Mandatory = $true)]
        [int]$SectionNumber,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Description,

        [Parameter(Mandatory = $true)]
        [string]$EmptyMessage,

        [Parameter(Mandatory = $false)]
        [switch]$ShowDeletionCandidate,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Accounts
    )

    $accountList = @($Accounts)
    [void]$Builder.Append("<h2 style=""margin:28px 0 10px;color:#243b53;font-size:18px;"">$SectionNumber. $(ConvertTo-HtmlEncodedText $Title)</h2>")
    [void]$Builder.Append("<p style=""margin:0 0 12px;color:#52606d;"">$(ConvertTo-HtmlEncodedText $Description)</p>")

    if ($accountList.Count -eq 0) {
        [void]$Builder.Append("<p style=""padding:14px;background:#ecfdf3;border:1px solid #86d7a2;border-radius:4px;color:#166534;font-weight:600;"">$(ConvertTo-HtmlEncodedText $EmptyMessage)</p>")
        return
    }

    [void]$Builder.Append("<p style=""padding:14px;background:#fff4e5;border:1px solid #f5bd65;border-radius:4px;color:#8a4b08;font-weight:600;"">Foram encontradas $($accountList.Count) conta(s).</p>")
    [void]$Builder.Append('<div style="overflow-x:auto;"><table style="border-collapse:collapse;width:100%;border:1px solid #bcccdc;font-size:12px;">')
    [void]$Builder.Append('<thead><tr style="background:#334e68;color:#ffffff;text-align:left;">')
    $headings = if ($ShowDeletionCandidate) {
        @('Conta', 'Nome', 'Senha expirada', '&Uacute;ltima altera&ccedil;&atilde;o da senha', 'Cria&ccedil;&atilde;o', 'Candidata &agrave; exclus&atilde;o')
    }
    else {
        @('Conta', 'Nome', 'UPN', 'Habilitada', 'Senha expirada', '&Uacute;ltima altera&ccedil;&atilde;o da senha', 'Cria&ccedil;&atilde;o', 'Distinguished Name')
    }
    foreach ($heading in $headings) {
        [void]$Builder.Append("<th style=""padding:7px 8px;border:1px solid #486581;white-space:nowrap;"">$heading</th>")
    }
    [void]$Builder.Append('</tr></thead><tbody>')

    $rowIndex = 0
    foreach ($account in $accountList) {
        $background = if (($rowIndex % 2) -eq 0) { '#f8fafc' } else { '#eef2f6' }
        $rowIndex++
        [void]$Builder.Append("<tr style=""background:$background;"">")
        $rowValues = if ($ShowDeletionCandidate) {
            @(
                $account.SamAccountName,
                $account.DisplayName,
                $(if ($account.PasswordExpired) { 'Sim' } else { "N$([char]0x00E3)o" }),
                (ConvertTo-ReportDateText $account.PasswordLastSet),
                (ConvertTo-ReportDateText $account.CreatedDate),
                $(if ($account.DeletionCandidate) { 'Sim' } else { "N$([char]0x00E3)o" })
            )
        }
        else {
            @(
                $account.SamAccountName,
                $account.DisplayName,
                $account.UserPrincipalName,
                $(if ($account.Enabled) { 'Sim' } else { "N$([char]0x00E3)o" }),
                $(if ($account.PasswordExpired) { 'Sim' } else { "N$([char]0x00E3)o" }),
                (ConvertTo-ReportDateText $account.PasswordLastSet),
                (ConvertTo-ReportDateText $account.CreatedDate),
                $account.DistinguishedName
            )
        }
        $valueIndex = 0
        foreach ($value in $rowValues) {
            $candidateStyle = if ($ShowDeletionCandidate -and $account.DeletionCandidate -and $valueIndex -eq ($rowValues.Count - 1)) {
                'color:#b91c1c;font-weight:700;'
            }
            else {
                ''
            }
            [void]$Builder.Append("<td style=""padding:6px 8px;border:1px solid #d9e2ec;vertical-align:top;overflow-wrap:anywhere;$candidateStyle"">$(ConvertTo-HtmlEncodedText $value)</td>")
            $valueIndex++
        }
        [void]$Builder.Append('</tr>')
    }

    [void]$Builder.Append('</tbody>')
    if ($ShowDeletionCandidate) {
        [void]$Builder.Append('<tfoot><tr><td colspan="6" style="padding:10px 12px;border:1px solid #bcccdc;background:#f8fafc;color:#52606d;line-height:1.5;"><strong>Crit&eacute;rio para candidatura &agrave; exclus&atilde;o:</strong> o campo Notes deve conter uma das palavras <strong>candidato</strong> ou <strong>candidata</strong>.</td></tr></tfoot>')
    }
    [void]$Builder.Append('</table></div>')
}

function Get-AccountStatusDetails {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Accounts,

        [Parameter(Mandatory = $true)]
        [string]$Server
    )

    return @(
        foreach ($account in @($Accounts)) {
            $user = Get-ADUser `
                -Identity $account.DistinguishedName `
                -Server $Server `
                -Properties DisplayName, UserPrincipalName, Enabled, PasswordExpired, whenCreated, pwdLastSet, info, DistinguishedName `
                -ErrorAction Stop
            $notes = [string]$user.info

            [PSCustomObject]@{
                SamAccountName = [string]$user.SamAccountName
                DisplayName = [string]$user.DisplayName
                UserPrincipalName = [string]$user.UserPrincipalName
                Enabled = [bool]$user.Enabled
                PasswordExpired = [bool]$user.PasswordExpired
                PasswordLastSet = ConvertFrom-ActiveDirectoryFileTime $user.pwdLastSet
                CreatedDate = $user.whenCreated
                DistinguishedName = [string]$user.DistinguishedName
                Notes = $notes
                DeletionCandidate = $notes -match '\b(?:candidat[oa]|canditad[oa])\b'
            }
        }
    )
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

function New-AccountStatusEmailHtml {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$LockedAccounts,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$PasswordExpiredAccounts,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$DisabledAccounts,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ControllerResults,

        [Parameter(Mandatory = $true)]
        [string]$DomainName,

        [Parameter(Mandatory = $true)]
        [string]$PdcEmulator,

        [Parameter(Mandatory = $true)]
        [datetime]$CollectedAt,

        [Parameter(Mandatory = $true)]
        [datetime]$SentAt
    )

    $accountList = @($LockedAccounts)
    $passwordExpiredList = @($PasswordExpiredAccounts)
    $disabledList = @($DisabledAccounts)
    $controllerList = @($ControllerResults)
    $count = $accountList.Count
    $routineName = [System.IO.Path]::GetFileName($PSCommandPath)
    $collectedAtText = $CollectedAt.ToString('dd/MM/yyyy HH:mm:ss')
    $sentAtText = $SentAt.ToString('dd/MM/yyyy HH:mm:ss')
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.Append('<!DOCTYPE html><html><head><meta charset="utf-8"></head>')
    [void]$builder.Append('<body style="margin:0;padding:24px;background:#f5f7fa;font-family:Segoe UI,Calibri,Arial,sans-serif;font-size:14px;color:#1f2933;">')
    [void]$builder.Append('<div style="max-width:1200px;margin:0 auto;background:#ffffff;border:1px solid #d9e2ec;border-radius:8px;padding:24px;">')
    [void]$builder.Append('<h1 style="margin:0 0 18px;color:#173f5f;font-size:24px;">Situa&ccedil;&otilde;es de contas no Active Directory</h1>')
    [void]$builder.Append('<table role="presentation" style="border-collapse:collapse;margin-bottom:18px;">')
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Bloqueadas por autentica&ccedil;&atilde;o inv&aacute;lida:</td><td style=""padding:3px 0;font-weight:600;"">$count</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Com senha expirada:</td><td style=""padding:3px 0;font-weight:600;"">$($passwordExpiredList.Count)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Desativadas:</td><td style=""padding:3px 0;font-weight:600;"">$($disabledList.Count)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Dom&iacute;nio:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $DomainName)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">PDC Emulator:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $PdcEmulator)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Controladores consultados:</td><td style=""padding:3px 0;font-weight:600;"">$($controllerList.Count)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Hor&aacute;rio da coleta:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $collectedAtText)</td></tr>")
    [void]$builder.Append('</table>')
    [void]$builder.Append('<p style="padding:12px;background:#eaf2f8;border:1px solid #9fb3c8;border-radius:4px;color:#243b53;">Uma mesma conta pode aparecer em mais de um t&oacute;pico quando atender a mais de um crit&eacute;rio. O estado pode mudar durante ou depois da coleta.</p>')

    [void]$builder.Append('<h2 style="margin:28px 0 10px;color:#243b53;font-size:18px;">1. Contas bloqueadas por autentica&ccedil;&atilde;o inv&aacute;lida</h2>')
    [void]$builder.Append('<p style="margin:0 0 12px;color:#52606d;">Contas bloqueadas pela pol&iacute;tica do Active Directory ap&oacute;s tentativas de autentica&ccedil;&atilde;o inv&aacute;lidas. Os atributos <strong>badPasswordTime</strong> e <strong>badPwdCount</strong> n&atilde;o s&atilde;o replicados; a consolida&ccedil;&atilde;o usa o hor&aacute;rio mais recente e o maior contador local observados, sem somar contadores.</p>')

    [void]$builder.Append('<h2 style="margin:24px 0 10px;color:#243b53;font-size:18px;">Controladores consultados</h2>')
    [void]$builder.Append('<div style="overflow-x:auto;"><table style="border-collapse:collapse;width:100%;border:1px solid #bcccdc;font-size:12px;">')
    [void]$builder.Append('<thead><tr style="background:#334e68;color:#ffffff;text-align:left;">')
    foreach ($heading in @('Controlador', 'PDC', 'Site', 'Somente leitura', 'Contas bloqueadas', 'Hor&aacute;rio da consulta')) {
        [void]$builder.Append("<th style=""padding:7px 8px;border:1px solid #486581;white-space:nowrap;"">$heading</th>")
    }
    [void]$builder.Append('</tr></thead><tbody>')
    $controllerIndex = 0
    foreach ($controller in $controllerList) {
        $background = if (($controllerIndex % 2) -eq 0) { '#f8fafc' } else { '#eef2f6' }
        $controllerIndex++
        [void]$builder.Append("<tr style=""background:$background;"">")
        foreach ($value in @(
            $controller.Controller,
            $(if ($controller.IsPdc) { 'Sim' } else { "N$([char]0x00E3)o" }),
            $controller.Site,
            $(if ($controller.IsReadOnly) { 'Sim' } else { "N$([char]0x00E3)o" }),
            $controller.LockedAccountCount,
            (ConvertTo-ReportDateText $controller.QueriedAt)
        )) {
            [void]$builder.Append("<td style=""padding:6px 8px;border:1px solid #d9e2ec;vertical-align:top;"">$(ConvertTo-HtmlEncodedText $value)</td>")
        }
        [void]$builder.Append('</tr>')
    }
    [void]$builder.Append('</tbody></table></div>')

    if ($count -eq 0) {
        [void]$builder.Append('<p style="padding:14px;background:#ecfdf3;border:1px solid #86d7a2;border-radius:4px;color:#166534;font-weight:600;">Nenhuma conta estava bloqueada por autentica&ccedil;&atilde;o inv&aacute;lida no momento da coleta.</p>')
    }
    else {
        [void]$builder.Append("<p style=""padding:14px;background:#fff4e5;border:1px solid #f5bd65;border-radius:4px;color:#8a4b08;font-weight:600;"">Foram encontradas $count conta(s) bloqueada(s) por autentica&ccedil;&atilde;o inv&aacute;lida.</p>")
        [void]$builder.Append('<h2 style="margin:24px 0 12px;color:#243b53;font-size:18px;">Listagem detalhada por conta</h2>')

        $rowIndex = 0
        foreach ($account in $accountList) {
            $background = if (($rowIndex % 2) -eq 0) { '#f8fafc' } else { '#eef2f6' }
            $rowIndex++
            $enabledText = if ($account.Enabled) { 'Sim' } else { "N$([char]0x00E3)o" }
            $accountTitle = ConvertTo-HtmlEncodedText $account.SamAccountName
            if (-not [string]::IsNullOrWhiteSpace([string]$account.DisplayName)) {
                $accountTitle = "$accountTitle &mdash; $(ConvertTo-HtmlEncodedText $account.DisplayName)"
            }

            [void]$builder.Append("<div style=""margin:0 0 14px;padding:16px 18px;background:$background;border:1px solid #bcccdc;border-left:5px solid #d64545;border-radius:6px;"">")
            [void]$builder.Append("<h3 style=""margin:0 0 12px;color:#173f5f;font-size:17px;overflow-wrap:anywhere;"">$accountTitle</h3>")
            [void]$builder.Append('<div style="margin-bottom:12px;">')
            [void]$builder.Append("<span style=""display:inline-block;margin:0 8px 6px 0;padding:4px 8px;background:#eaf2f8;border-radius:12px;color:#243b53;font-size:12px;"">Habilitada: <strong>$enabledText</strong></span>")
            [void]$builder.Append("<span style=""display:inline-block;margin:0 8px 6px 0;padding:4px 8px;background:#fff4e5;border-radius:12px;color:#8a4b08;font-size:12px;"">Bloqueada em DCs: <strong>$($account.LockedControllerCount) de $($controllerList.Count)</strong></span>")
            [void]$builder.Append('</div>')

            [void]$builder.Append('<div style="margin-bottom:12px;padding-bottom:12px;border-bottom:1px solid #d9e2ec;line-height:1.7;">')
            [void]$builder.Append("<div><strong>UPN:</strong> $(ConvertTo-HtmlEncodedText $account.UserPrincipalName)</div>")
            [void]$builder.Append("<div style=""overflow-wrap:anywhere;""><strong>Distinguished Name:</strong> $(ConvertTo-HtmlEncodedText $account.DistinguishedName)</div>")
            [void]$builder.Append('</div>')

            [void]$builder.Append('<div style="margin-bottom:12px;padding-bottom:12px;border-bottom:1px solid #d9e2ec;line-height:1.7;">')
            [void]$builder.Append('<div style="margin-bottom:4px;color:#52606d;font-size:12px;font-weight:700;text-transform:uppercase;">Ciclo da conta</div>')
            [void]$builder.Append("<div><strong>Data de cria&ccedil;&atilde;o:</strong> $(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $account.CreatedDate))</div>")
            if ($null -ne $account.AccountExpirationDate) {
                [void]$builder.Append("<div><strong>Data de expira&ccedil;&atilde;o:</strong> $(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $account.AccountExpirationDate))</div>")
            }
            [void]$builder.Append("<div><strong>&Uacute;ltima altera&ccedil;&atilde;o da senha:</strong> $(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $account.PasswordLastSet))</div>")
            [void]$builder.Append('</div>')

            [void]$builder.Append('<div style="line-height:1.7;">')
            [void]$builder.Append('<div style="margin-bottom:4px;color:#52606d;font-size:12px;font-weight:700;text-transform:uppercase;">Ocorr&ecirc;ncias de senha incorreta</div>')
            [void]$builder.Append("<div><strong>&Uacute;ltima senha incorreta no dom&iacute;nio:</strong> $(ConvertTo-HtmlEncodedText (ConvertTo-ReportDateText $account.LastBadPasswordAttempt))</div>")
            [void]$builder.Append("<div><strong>Controlador da &uacute;ltima tentativa:</strong> $(ConvertTo-HtmlEncodedText $account.LastBadPasswordController)</div>")
            [void]$builder.Append("<div><strong>Maior contador local:</strong> $(ConvertTo-HtmlEncodedText $account.HighestBadPasswordCount)</div>")
            [void]$builder.Append("<div><strong>Controlador do maior contador:</strong> $(ConvertTo-HtmlEncodedText $account.HighestBadPasswordCountController)</div>")
            [void]$builder.Append('</div>')

            if (-not [string]::IsNullOrWhiteSpace([string]$account.Notes)) {
                [void]$builder.Append('<div style="margin-top:12px;padding:10px 12px;background:#ffffff;border:1px solid #d9e2ec;border-radius:4px;line-height:1.6;overflow-wrap:anywhere;">')
                [void]$builder.Append("<strong>Notes:</strong><br>$(ConvertTo-HtmlEncodedMultilineText ([string]$account.Notes))")
                [void]$builder.Append('</div>')
            }

            [void]$builder.Append('</div>')
        }
    }

    Add-AccountStatusTableHtml `
        -Builder $builder `
        -SectionNumber 2 `
        -Title 'Contas com senha expirada' `
        -Description 'Contas cuja senha expirou e que precisam trocar a senha para voltar a autenticar normalmente.' `
        -EmptyMessage 'Nenhuma conta com senha expirada foi encontrada no momento da coleta.' `
        -Accounts $passwordExpiredList

    Add-AccountStatusTableHtml `
        -Builder $builder `
        -SectionNumber 3 `
        -Title 'Contas desativadas' `
        -Description 'Contas de usuario desabilitadas administrativamente no Active Directory. A candidatura a exclusao considera os termos candidato ou candidata no campo Notes.' `
        -EmptyMessage 'Nenhuma conta desativada foi encontrada no momento da coleta.' `
        -ShowDeletionCandidate `
        -Accounts $disabledList

    [void]$builder.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #d9e2ec;color:#627d98;font-size:12px;line-height:1.6;"">Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(ConvertTo-HtmlEncodedText $routineName)</strong><br>Enviado em: <strong>$(ConvertTo-HtmlEncodedText $sentAtText)</strong></div>")
    [void]$builder.Append('</div></body></html>')

    return $builder.ToString()
}

$stage = 'validacao dos destinatarios'

try {
    Test-MailRecipients -Addresses $MailTo

    $stage = 'carregamento do modulo ActiveDirectory'
    Import-Module ActiveDirectory -ErrorAction Stop

    $stage = 'descoberta do dominio e dos controladores'
    $domain = Get-ADDomain -ErrorAction Stop
    $domainName = [string]$domain.DNSRoot
    $pdcEmulator = [string]$domain.PDCEmulator

    if ([string]::IsNullOrWhiteSpace($domainName)) {
        throw 'O dominio atual nao possui um nome DNS disponivel.'
    }
    if ([string]::IsNullOrWhiteSpace($pdcEmulator)) {
        throw 'O PDC Emulator do dominio atual nao foi identificado.'
    }

    $domainControllers = @(
        Get-ADDomainController -Filter * -Server $pdcEmulator -ErrorAction Stop |
            Sort-Object @{ Expression = { ([string]$_.HostName).ToLowerInvariant() } }
    )
    if ($domainControllers.Count -eq 0) {
        throw 'Nenhum controlador de dominio foi encontrado.'
    }

    $stage = 'consulta de contas bloqueadas em todos os controladores'
    $candidateAccounts = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $controllerResults = @(
        foreach ($domainController in $domainControllers) {
            $controllerName = [string]$domainController.HostName
            if ([string]::IsNullOrWhiteSpace($controllerName)) {
                $controllerName = [string]$domainController.Name
            }
            if ([string]::IsNullOrWhiteSpace($controllerName)) {
                throw 'Um controlador de dominio foi retornado sem nome.'
            }

            $lockedOnController = @(Search-ADAccount -LockedOut -UsersOnly -Server $controllerName -ErrorAction Stop)
            $lockedDns = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

            foreach ($lockedAccount in $lockedOnController) {
                $identity = [string]$lockedAccount.DistinguishedName
                if ([string]::IsNullOrWhiteSpace($identity)) {
                    throw "A consulta ao controlador $controllerName retornou uma conta sem Distinguished Name."
                }
                [void]$lockedDns.Add($identity)
                if (-not $candidateAccounts.ContainsKey($identity)) {
                    $candidateAccounts.Add($identity, $identity)
                }
            }

            [PSCustomObject]@{
                Controller = $controllerName
                IsPdc = $controllerName.Equals($pdcEmulator, [System.StringComparison]::OrdinalIgnoreCase)
                Site = [string]$domainController.Site
                IsReadOnly = [bool]$domainController.IsReadOnly
                LockedAccountCount = $lockedDns.Count
                QueriedAt = Get-Date
                LockedDns = $lockedDns
            }
        }
    )

    $stage = 'carregamento dos atributos locais em todos os controladores'
    $detailedObservations = @(
        foreach ($controllerResult in $controllerResults) {
            foreach ($identity in $candidateAccounts.Keys) {
                $user = Get-ADUser `
                    -Identity $identity `
                    -Server $controllerResult.Controller `
                    -Properties DisplayName, UserPrincipalName, Enabled, lockoutTime, badPasswordTime, badPwdCount, whenCreated, accountExpires, pwdLastSet, info, DistinguishedName `
                    -ErrorAction Stop

                $badPasswordCount = $null
                $parsedBadPasswordCount = 0
                if ([int]::TryParse([string]$user.badPwdCount, [ref]$parsedBadPasswordCount)) {
                    $badPasswordCount = $parsedBadPasswordCount
                }

                [PSCustomObject]@{
                    Controller = $controllerResult.Controller
                    IsPdc = $controllerResult.IsPdc
                    SamAccountName = [string]$user.SamAccountName
                    DisplayName = [string]$user.DisplayName
                    UserPrincipalName = [string]$user.UserPrincipalName
                    Enabled = [bool]$user.Enabled
                    LockedOut = $controllerResult.LockedDns.Contains($identity)
                    LockoutDate = ConvertFrom-ActiveDirectoryFileTime $user.lockoutTime
                    LastBadPasswordAttempt = ConvertFrom-ActiveDirectoryFileTime $user.badPasswordTime
                    BadPasswordCount = $badPasswordCount
                    CreatedDate = $user.whenCreated
                    AccountExpirationDate = ConvertFrom-ActiveDirectoryExpirationTime $user.accountExpires
                    PasswordLastSet = ConvertFrom-ActiveDirectoryFileTime $user.pwdLastSet
                    Notes = [string]$user.info
                    DistinguishedName = [string]$user.DistinguishedName
                }
            }

            $controllerResult.QueriedAt = Get-Date
        }
    )

    $lockedAccounts = @(
        foreach ($accountGroup in ($detailedObservations | Group-Object DistinguishedName)) {
            $observations = @($accountGroup.Group)
            $profile = @($observations | Where-Object { $_.IsPdc } | Select-Object -First 1)
            if ($profile.Count -eq 0) {
                $profile = @($observations | Select-Object -First 1)
            }
            $profile = $profile[0]

            $lastBadPasswordObservation = @(
                $observations |
                    Where-Object { $null -ne $_.LastBadPasswordAttempt } |
                    Sort-Object LastBadPasswordAttempt -Descending |
                    Select-Object -First 1
            )
            $highestCountObservation = @(
                $observations |
                    Where-Object { $null -ne $_.BadPasswordCount } |
                    Sort-Object BadPasswordCount -Descending |
                    Select-Object -First 1
            )

            [PSCustomObject]@{
                SamAccountName = $profile.SamAccountName
                DisplayName = $profile.DisplayName
                UserPrincipalName = $profile.UserPrincipalName
                Enabled = $profile.Enabled
                LockedControllerCount = @($observations | Where-Object { $_.LockedOut }).Count
                LastBadPasswordAttempt = if ($lastBadPasswordObservation.Count) { $lastBadPasswordObservation[0].LastBadPasswordAttempt } else { $null }
                LastBadPasswordController = if ($lastBadPasswordObservation.Count) { $lastBadPasswordObservation[0].Controller } else { $null }
                HighestBadPasswordCount = if ($highestCountObservation.Count) { $highestCountObservation[0].BadPasswordCount } else { $null }
                HighestBadPasswordCountController = if ($highestCountObservation.Count) { $highestCountObservation[0].Controller } else { $null }
                CreatedDate = $profile.CreatedDate
                AccountExpirationDate = $profile.AccountExpirationDate
                PasswordLastSet = $profile.PasswordLastSet
                Notes = $profile.Notes
                DistinguishedName = $profile.DistinguishedName
            }
        }
    )

    $lockedAccounts = @($lockedAccounts | Sort-Object @{ Expression = { ([string]$_.SamAccountName).ToLowerInvariant() } })

    $stage = 'consulta de contas com senha expirada no PDC Emulator'
    $passwordExpiredCandidates = @(
        Search-ADAccount -PasswordExpired -UsersOnly -Server $pdcEmulator -ErrorAction Stop
    )
    $passwordExpiredAccounts = @(
        Get-AccountStatusDetails -Accounts $passwordExpiredCandidates -Server $pdcEmulator |
            Sort-Object @{ Expression = { ([string]$_.SamAccountName).ToLowerInvariant() } }
    )

    $stage = 'consulta de contas desativadas no PDC Emulator'
    $disabledCandidates = @(
        Search-ADAccount -AccountDisabled -UsersOnly -Server $pdcEmulator -ErrorAction Stop
    )
    $disabledAccounts = @(
        Get-AccountStatusDetails -Accounts $disabledCandidates -Server $pdcEmulator |
            Sort-Object @{ Expression = { ([string]$_.SamAccountName).ToLowerInvariant() } }
    )

    $stage = 'geracao do relatorio HTML'
    $collectedAt = Get-Date
    $sentAt = Get-Date
    $emailBody = New-AccountStatusEmailHtml `
        -LockedAccounts $lockedAccounts `
        -PasswordExpiredAccounts $passwordExpiredAccounts `
        -DisabledAccounts $disabledAccounts `
        -ControllerResults $controllerResults `
        -DomainName $domainName `
        -PdcEmulator $pdcEmulator `
        -CollectedAt $collectedAt `
        -SentAt $sentAt

    $emailSubject = "PS Panel - Contas AD: bloqueadas $($lockedAccounts.Count), senhas expiradas $($passwordExpiredAccounts.Count), desativadas $($disabledAccounts.Count)"

    $stage = 'carregamento do modulo de email'
    $emailModulePath = Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1'
    Import-Module $emailModulePath -Force -ErrorAction Stop

    $stage = 'envio do email'
    Send-PSPanelEmail -To $MailTo -Subject $emailSubject -Body $emailBody -BodyAsHtml -ErrorAction Stop

    Write-Output "Dominio consultado: $domainName"
    Write-Output "PDC Emulator: $pdcEmulator"
    Write-Output "Controladores consultados: $($controllerResults.Count)"
    Write-Output "Contas bloqueadas por autenticacao invalida: $($lockedAccounts.Count)"
    Write-Output "Contas com senha expirada: $($passwordExpiredAccounts.Count)"
    Write-Output "Contas desativadas: $($disabledAccounts.Count)"
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
