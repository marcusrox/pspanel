Set-StrictMode -Version 2.0

$script:ProjectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:ConfigPath = Join-Path $script:ProjectRoot 'database\email-settings.json'
$script:LibraryPath = Join-Path $PSScriptRoot 'lib'

function Import-PSPanelEmailAssemblies {
    $assemblies = @(
        @{ TypeName = 'Org.BouncyCastle.Crypto.CryptoException'; FileName = 'BouncyCastle.Cryptography.dll' },
        @{ TypeName = 'MimeKit.MimeMessage'; FileName = 'MimeKit.dll' },
        @{ TypeName = 'MailKit.Net.Smtp.SmtpClient'; FileName = 'MailKit.dll' }
    )

    foreach ($assembly in $assemblies) {
        if ($null -ne ([System.Management.Automation.PSTypeName]$assembly.TypeName).Type) {
            continue
        }

        $assemblyPath = Join-Path $script:LibraryPath $assembly.FileName
        if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
            throw "Biblioteca de email ausente: $($assembly.FileName)."
        }

        try {
            Add-Type -Path $assemblyPath -ErrorAction Stop
        }
        catch {
            throw "Nao foi possivel carregar a biblioteca de email $($assembly.FileName): $($_.Exception.Message)"
        }
    }
}

function Get-PSPanelEmailConfiguration {
    if (-not (Test-Path -LiteralPath $script:ConfigPath -PathType Leaf)) {
        throw 'Configuracao SMTP ainda nao foi salva no PS Panel.'
    }

    try {
        $config = Get-Content -LiteralPath $script:ConfigPath -Raw -Encoding utf8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'Nao foi possivel ler o arquivo de configuracao SMTP.'
    }

    if ($config.version -ne 2 -or $null -eq $config.smtp) {
        throw 'Versao ou estrutura do arquivo de configuracao SMTP invalida.'
    }

    $smtp = $config.smtp
    $port = 0
    if (-not [int]::TryParse([string]$smtp.port, [ref]$port) -or $port -notin @(465, 587)) {
        throw 'Porta SMTP invalida. Use 587 ou 465.'
    }

    $expectedSecurity = if ($port -eq 465) { 'tls' } else { 'starttls' }
    if ([string]$smtp.security -ne $expectedSecurity) {
        throw 'A porta SMTP e o modo de seguranca configurado sao incompativeis.'
    }

    foreach ($field in @(
        'host',
        'username',
        'password',
        'fromAddress',
        'fromName'
    )) {
        if ([string]::IsNullOrWhiteSpace([string]$smtp.$field)) {
            throw "Configuracao SMTP incompleta: $field."
        }
        if ([string]$smtp.$field -match '[\r\n]') {
            throw "Configuracao SMTP invalida: $field contem quebra de linha."
        }
    }

    $fromAddress = [string]$smtp.fromAddress
    if (
        $fromAddress -notmatch `
            '^[^\s@<>\"]+@[^\s@<>\"]+\.[^\s@<>\"]+$'
    ) {
        throw 'Configuracao SMTP invalida: fromAddress deve conter somente o endereco de email.'
    }

    $fromName = ([string]$smtp.fromName).Trim()
    if ($fromName.Length -gt 256) {
        throw 'Configuracao SMTP invalida: fromName excede 256 caracteres.'
    }

    return [PSCustomObject]@{
        Host = [string]$smtp.host
        Port = $port
        Security = $expectedSecurity
        Username = [string]$smtp.username
        Password = [string]$smtp.password
        FromAddress = $fromAddress
        FromName = $fromName
    }
}

function ConvertTo-PSPanelMailboxAddresses {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Addresses,

        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    $result = [System.Collections.Generic.List[MimeKit.MailboxAddress]]::new()
    foreach ($addressGroup in $Addresses) {
        foreach ($address in ([string]$addressGroup -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if ($address -match '[\r\n]') {
                throw "Endereco invalido em ${FieldName}."
            }

            try {
                $result.Add([MimeKit.MailboxAddress]::Parse($address))
            }
            catch {
                throw "Endereco de email invalido em ${FieldName}."
            }
        }
    }

    return $result
}

function Send-PSPanelEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$To,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Subject,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory = $false)]
        [switch]$BodyAsHtml,

        [Parameter(Mandatory = $false)]
        [string[]]$Cc,

        [Parameter(Mandatory = $false)]
        [string[]]$Bcc,

        [Parameter(Mandatory = $false)]
        [string[]]$ReplyTo,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string]$FromName = '',

        [Parameter(Mandatory = $false)]
        [string[]]$AttachmentPath
    )

    if ($Subject -match '[\r\n]') {
        throw 'O assunto do email nao pode conter quebra de linha.'
    }
    if ($Subject.Length -gt 998) {
        throw 'O assunto do email excede o limite permitido.'
    }
    if ($Body.Length -gt 5242880) {
        throw 'O corpo do email excede o limite de 5 MB.'
    }
    if ($FromName -match '[\r\n]') {
        throw 'O nome do remetente nao pode conter quebra de linha.'
    }
    if ($FromName.Length -gt 256) {
        throw 'O nome do remetente excede o limite de 256 caracteres.'
    }

    Import-PSPanelEmailAssemblies
    $config = Get-PSPanelEmailConfiguration
    $message = [MimeKit.MimeMessage]::new()
    $client = $null

    try {
        $effectiveFromName = if ([string]::IsNullOrWhiteSpace($FromName)) {
            $config.FromName
        }
        else {
            $FromName.Trim()
        }
        $fromMailbox = [MimeKit.MailboxAddress]::new(
            $effectiveFromName,
            $config.FromAddress
        )
        $message.From.Add($fromMailbox)
        foreach ($address in (ConvertTo-PSPanelMailboxAddresses -Addresses $To -FieldName 'To')) { $message.To.Add($address) }
        if ($message.To.Count -eq 0) { throw 'Nenhum destinatario de email valido foi informado.' }
        if ($Cc) { foreach ($address in (ConvertTo-PSPanelMailboxAddresses -Addresses $Cc -FieldName 'Cc')) { $message.Cc.Add($address) } }
        if ($Bcc) { foreach ($address in (ConvertTo-PSPanelMailboxAddresses -Addresses $Bcc -FieldName 'Bcc')) { $message.Bcc.Add($address) } }
        if ($ReplyTo) { foreach ($address in (ConvertTo-PSPanelMailboxAddresses -Addresses $ReplyTo -FieldName 'ReplyTo')) { $message.ReplyTo.Add($address) } }
        $recipientCount = $message.To.Count + $message.Cc.Count + $message.Bcc.Count + $message.ReplyTo.Count
        if ($recipientCount -gt 100) { throw 'O email excede o limite de 100 destinatarios.' }

        $message.Subject = $Subject
        $builder = [MimeKit.BodyBuilder]::new()
        if ($BodyAsHtml) {
            $builder.HtmlBody = $Body
        }
        else {
            $builder.TextBody = $Body
        }
        if ($AttachmentPath) {
            foreach ($path in $AttachmentPath) {
                if ([string]::IsNullOrWhiteSpace($path)) {
                    throw 'O caminho de um anexo esta vazio.'
                }

                $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
                if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
                    throw "Arquivo de anexo nao encontrado: $path"
                }
                [void]$builder.Attachments.Add($resolvedPath)
            }
        }
        $message.Body = $builder.ToMessageBody()

        $socketOption = if ($config.Port -eq 465) {
            [MailKit.Security.SecureSocketOptions]::SslOnConnect
        }
        else {
            [MailKit.Security.SecureSocketOptions]::StartTls
        }

        $client = [MailKit.Net.Smtp.SmtpClient]::new()
        $client.CheckCertificateRevocation = $true
        $client.Timeout = 60000
        $client.Connect($config.Host, $config.Port, $socketOption)
        $client.Authenticate($config.Username, $config.Password)
        [void]$client.Send($message)
        $client.Disconnect($true)
    }
    catch {
        throw "Falha ao enviar email: $($_.Exception.Message)"
    }
    finally {
        if ($null -ne $client) {
            if ($client.IsConnected) {
                try { $client.Disconnect($false) } catch { }
            }
            $client.Dispose()
        }
        $message.Dispose()
    }
}

Import-PSPanelEmailAssemblies
Export-ModuleMember -Function Send-PSPanelEmail
