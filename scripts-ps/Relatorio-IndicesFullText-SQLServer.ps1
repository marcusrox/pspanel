#requires -Version 5.1

<#
.SYNOPSIS
    Localiza indices Full-Text nos bancos de uma instancia SQL Server e envia um relatorio quando houver resultados.

.DESCRIPTION
    Conecta ao SQL Server usando autenticacao integrada do Windows, confirma que o recurso
    Full-Text Search esta instalado, enumera todos os bancos online visiveis e conectaveis,
    exceto tempdb, e consulta os catalogos de sistema de cada banco. A rotina e somente
    leitura. Quando encontra indices Full-Text, envia um unico relatorio HTML pelo modulo
    compartilhado PSPanel.Email. Quando nao encontra indices, encerra com sucesso sem email.

.PARAMETER SqlServer
    Nome da instancia SQL Server. O valor padrao e SERV01D. Nao aceita valor vazio nem
    caracteres de controle. A conexao usa autenticacao integrada e criptografia, com
    TrustServerCertificate habilitado para a instancia corporativa.

.PARAMETER MailTo
    Um ou mais destinatarios. O valor padrao e dba@desenbahia.ba.gov.br. Enderecos em uma
    unica string podem ser separados por virgula ou ponto e virgula.

.EXAMPLE
    .\scripts-ps\Relatorio-IndicesFullText-SQLServer.ps1

    Consulta SERV01D e, quando houver indices, envia o relatorio ao destinatario padrao.

.INPUTS
    Nenhum.

.OUTPUTS
    Mensagens de resumo no pipeline e, quando houver indices, um relatorio HTML por email.

.NOTES
    Requer Windows PowerShell 5.1 ou superior, acesso integrado ao SQL Server, permissao
    VIEW ANY DATABASE, acesso aos catalogos de sistema de todos os bancos online, Full-Text
    Search instalado e configuracao valida do PSPanel.Email. A conexao SQL usa
    TrustServerCertificate e nao valida a cadeia nem o nome do certificado apresentado.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SqlServer = 'SERV01D',

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string[]]$MailTo = @('dba@desenbahia.ba.gov.br')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function ConvertTo-HtmlEncodedText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$Value,

        [Parameter(Mandatory = $false)]
        [string]$Fallback = 'Nao informado'
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return [System.Net.WebUtility]::HtmlEncode($Fallback)
    }

    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function ConvertTo-SafeSubjectText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $result = ($Value -replace '[\x00-\x1f\x7f]', ' ').Trim()
    if ($result.Length -gt 128) {
        return $result.Substring(0, 128)
    }
    return $result
}

function Test-ReportParameters {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string[]]$Recipients
    )

    if ([string]::IsNullOrWhiteSpace($Server) -or $Server -match '[\x00-\x1f\x7f]') {
        throw 'O parametro SqlServer e obrigatorio e nao pode conter caracteres de controle.'
    }
    if ($Server.Length -gt 255) {
        throw 'O parametro SqlServer excede 255 caracteres.'
    }

    $parsedRecipients = @(
        foreach ($recipientGroup in $Recipients) {
            foreach ($recipient in ([string]$recipientGroup -split '[;,]')) {
                $trimmedRecipient = $recipient.Trim()
                if ($trimmedRecipient) {
                    $trimmedRecipient
                }
            }
        }
    )

    if ($parsedRecipients.Count -eq 0) {
        throw 'O parametro MailTo deve conter ao menos um destinatario.'
    }
    if ($parsedRecipients.Count -gt 100) {
        throw 'O parametro MailTo excede o limite de 100 destinatarios.'
    }
    foreach ($recipient in $parsedRecipients) {
        if (
            $recipient -match '[\r\n]' -or
            $recipient.Length -gt 320 -or
            $recipient -notmatch '^[^\s@<>"\\]+@[^\s@<>"\\]+\.[^\s@<>"\\]+$'
        ) {
            throw 'O parametro MailTo contem um endereco de email invalido.'
        }
    }
}

function New-SqlConnectionString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database
    )

    $builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
    $builder['Data Source'] = $Server
    $builder['Initial Catalog'] = $Database
    $builder['Integrated Security'] = $true
    $builder['Encrypt'] = $true
    $builder['TrustServerCertificate'] = $true
    $builder['Connect Timeout'] = 15
    $builder['Application Name'] = 'PS Panel - Relatorio Full-Text'
    return $builder.ConnectionString
}

function Invoke-SqlScalarReadOnly {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $command = $null
    try {
        $connection.ConnectionString = New-SqlConnectionString -Server $Server -Database $Database
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 60
        return $command.ExecuteScalar()
    }
    finally {
        if ($null -ne $command) {
            $command.Dispose()
        }
        if ($null -ne $connection) {
            if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
                $connection.Close()
            }
            $connection.Dispose()
        }
    }
}

function Invoke-SqlTableReadOnly {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database,

        [Parameter(Mandatory = $true)]
        [string]$Query
    )

    $connection = New-Object System.Data.SqlClient.SqlConnection
    $command = $null
    $reader = $null
    try {
        $connection.ConnectionString = New-SqlConnectionString -Server $Server -Database $Database
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 60
        $reader = $command.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)
        Write-Output -NoEnumerate $table
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        if ($null -ne $command) {
            $command.Dispose()
        }
        if ($null -ne $connection) {
            if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
                $connection.Close()
            }
            $connection.Dispose()
        }
    }
}

function Get-FullTextIndexesFromDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [string]$Database
    )

    $query = @'
SELECT
    fi.object_id AS ObjectId,
    s.name AS SchemaName,
    t.name AS TableName,
    ftc.name AS CatalogName,
    ui.name AS UniqueKeyIndexName,
    fi.is_enabled AS IsEnabled,
    fi.change_tracking_state_desc AS ChangeTrackingState,
    fic.column_id AS ColumnId,
    c.name AS ColumnName,
    ftl.name AS LanguageName
FROM sys.fulltext_indexes AS fi
INNER JOIN sys.tables AS t
    ON t.object_id = fi.object_id
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
INNER JOIN sys.fulltext_catalogs AS ftc
    ON ftc.fulltext_catalog_id = fi.fulltext_catalog_id
INNER JOIN sys.indexes AS ui
    ON ui.object_id = fi.object_id
    AND ui.index_id = fi.unique_index_id
INNER JOIN sys.fulltext_index_columns AS fic
    ON fic.object_id = fi.object_id
INNER JOIN sys.columns AS c
    ON c.object_id = fic.object_id
    AND c.column_id = fic.column_id
LEFT JOIN sys.fulltext_languages AS ftl
    ON ftl.lcid = fic.language_id
ORDER BY s.name, t.name, fic.column_id;
'@

    $rows = Invoke-SqlTableReadOnly -Server $Server -Database $Database -Query $query
    $results = @(
        foreach ($indexGroup in (@($rows.Rows) | Group-Object ObjectId)) {
            $firstRow = @($indexGroup.Group)[0]
            $columns = @(
                foreach ($row in (@($indexGroup.Group) | Sort-Object ColumnId)) {
                    $columnName = [string]$row.ColumnName
                    $languageName = [string]$row.LanguageName
                    if ([string]::IsNullOrWhiteSpace($languageName)) {
                        $columnName
                    }
                    else {
                        "$columnName ($languageName)"
                    }
                }
            )

            [PSCustomObject]@{
                DatabaseName = $Database
                SchemaName = [string]$firstRow.SchemaName
                TableName = [string]$firstRow.TableName
                CatalogName = [string]$firstRow.CatalogName
                UniqueKeyIndexName = [string]$firstRow.UniqueKeyIndexName
                IsEnabled = [System.Convert]::ToBoolean($firstRow.IsEnabled)
                ChangeTrackingState = [string]$firstRow.ChangeTrackingState
                Columns = $columns
            }
        }
    )

    return $results
}

function New-FullTextReportHtml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Server,

        [Parameter(Mandatory = $true)]
        [object[]]$Indexes,

        [Parameter(Mandatory = $true)]
        [int]$EnumeratedDatabaseCount,

        [Parameter(Mandatory = $true)]
        [int]$QueriedDatabaseCount,

        [Parameter(Mandatory = $true)]
        [datetime]$CollectedAt,

        [Parameter(Mandatory = $true)]
        [datetime]$SentAt
    )

    $builder = New-Object System.Text.StringBuilder
    $collectedAtText = $CollectedAt.ToString('dd/MM/yyyy HH:mm:ss')
    $sentAtText = $SentAt.ToString('dd/MM/yyyy HH:mm:ss')
    $routineName = Split-Path -Leaf $PSCommandPath
    $databaseGroups = @($Indexes | Group-Object DatabaseName | Sort-Object Name)

    [void]$builder.Append('<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8"></head>')
    [void]$builder.Append('<body style="margin:0;padding:20px;background:#f4f7fa;color:#243b53;font-family:Arial,sans-serif;">')
    [void]$builder.Append('<div style="max-width:1100px;margin:0 auto;background:#ffffff;border:1px solid #d9e2ec;border-radius:6px;padding:24px;">')
    [void]$builder.Append('<h1 style="margin:0 0 8px;color:#102a43;font-size:24px;">&Iacute;ndices Full-Text encontrados no SQL Server</h1>')
    [void]$builder.Append('<p style="margin:0 0 20px;color:#52606d;">Coleta informativa do estado observado no instante indicado.</p>')
    [void]$builder.Append('<table style="border-collapse:collapse;margin-bottom:22px;font-size:14px;">')
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Servidor:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $Server)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Hor&aacute;rio da coleta:</td><td style=""padding:3px 0;font-weight:600;"">$(ConvertTo-HtmlEncodedText $collectedAtText)</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Bancos enumerados:</td><td style=""padding:3px 0;font-weight:600;"">$EnumeratedDatabaseCount</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">Bancos consultados:</td><td style=""padding:3px 0;font-weight:600;"">$QueriedDatabaseCount</td></tr>")
    [void]$builder.Append("<tr><td style=""padding:3px 18px 3px 0;color:#52606d;"">&Iacute;ndices encontrados:</td><td style=""padding:3px 0;font-weight:600;"">$($Indexes.Count)</td></tr></table>")

    [void]$builder.Append('<h2 style="margin:0 0 10px;color:#243b53;font-size:18px;">Resumo por banco</h2>')
    [void]$builder.Append('<ul style="margin:0 0 22px;padding-left:22px;">')
    foreach ($databaseGroup in $databaseGroups) {
        [void]$builder.Append("<li><strong>$(ConvertTo-HtmlEncodedText $databaseGroup.Name)</strong>: $($databaseGroup.Count) &iacute;ndice(s)</li>")
    }
    [void]$builder.Append('</ul>')

    [void]$builder.Append('<div style="overflow-x:auto;"><table style="border-collapse:collapse;width:100%;border:1px solid #bcccdc;font-size:12px;">')
    [void]$builder.Append('<thead><tr style="background:#334e68;color:#ffffff;text-align:left;">')
    foreach ($heading in @('Banco', 'Objeto', 'Cat&aacute;logo', '&Iacute;ndice chave', 'Estado', 'Colunas e idiomas')) {
        [void]$builder.Append("<th style=""padding:7px 8px;border:1px solid #486581;"">$heading</th>")
    }
    [void]$builder.Append('</tr></thead><tbody>')

    $rowIndex = 0
    foreach ($index in $Indexes) {
        $background = if (($rowIndex % 2) -eq 0) { '#ffffff' } else { '#f0f4f8' }
        $enabledText = if ($index.IsEnabled) { 'Habilitado' } else { 'Desabilitado' }
        $stateText = "$enabledText / $($index.ChangeTrackingState)"
        $objectName = "$($index.SchemaName).$($index.TableName)"
        $columnsText = $index.Columns -join '; '
        [void]$builder.Append("<tr style=""background:$background;"">")
        foreach ($value in @($index.DatabaseName, $objectName, $index.CatalogName, $index.UniqueKeyIndexName, $stateText, $columnsText)) {
            [void]$builder.Append("<td style=""padding:7px 8px;border:1px solid #d9e2ec;vertical-align:top;overflow-wrap:anywhere;"">$(ConvertTo-HtmlEncodedText $value)</td>")
        }
        [void]$builder.Append('</tr>')
        $rowIndex++
    }
    [void]$builder.Append('</tbody></table></div>')
    [void]$builder.Append("<div style=""margin-top:24px;padding-top:12px;border-top:1px solid #d9e2ec;color:#627d98;font-size:12px;line-height:1.6;"">Enviado em: <strong>$(ConvertTo-HtmlEncodedText $sentAtText)</strong><br>Sistema: <strong>PS Panel</strong><br>Rotina: <strong>$(ConvertTo-HtmlEncodedText $routineName)</strong><br>Servidor: <strong>$(ConvertTo-HtmlEncodedText ([System.Environment]::MachineName))</strong></div>")
    [void]$builder.Append('</div></body></html>')
    return $builder.ToString()
}

$stage = 'validacao dos parametros'

try {
    Test-ReportParameters -Server $SqlServer -Recipients $MailTo

    $stage = 'verificacao da permissao de visibilidade dos bancos'
    $viewAnyDatabase = Invoke-SqlScalarReadOnly `
        -Server $SqlServer `
        -Database 'master' `
        -Query "SELECT HAS_PERMS_BY_NAME(NULL, NULL, 'VIEW ANY DATABASE');"
    if ($null -eq $viewAnyDatabase -or $viewAnyDatabase -eq [DBNull]::Value -or [int]$viewAnyDatabase -ne 1) {
        throw 'A identidade de execucao nao possui VIEW ANY DATABASE; nao e possivel comprovar uma varredura completa.'
    }

    $stage = 'verificacao do recurso Full-Text Search'
    $isFullTextInstalled = Invoke-SqlScalarReadOnly `
        -Server $SqlServer `
        -Database 'master' `
        -Query "SELECT CAST(FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') AS int);"
    if ($null -eq $isFullTextInstalled -or $isFullTextInstalled -eq [DBNull]::Value) {
        throw 'Nao foi possivel determinar se o recurso Full-Text Search esta instalado.'
    }
    if ([int]$isFullTextInstalled -ne 1) {
        throw 'O recurso Full-Text Search nao esta instalado na instancia consultada.'
    }

    $stage = 'enumeracao dos bancos online'
    $databaseQuery = @'
SELECT
    name AS DatabaseName,
    HAS_DBACCESS(name) AS HasDatabaseAccess
FROM sys.databases
WHERE state_desc = N'ONLINE'
    AND name <> N'tempdb'
ORDER BY name;
'@
    $databaseRows = Invoke-SqlTableReadOnly -Server $SqlServer -Database 'master' -Query $databaseQuery
    $databases = @($databaseRows.Rows)
    if ($databases.Count -eq 0) {
        throw 'Nenhum banco online elegivel foi enumerado na instancia.'
    }

    $inaccessibleDatabases = @(
        $databases | Where-Object {
            $_.HasDatabaseAccess -eq [DBNull]::Value -or [int]$_.HasDatabaseAccess -ne 1
        }
    )
    if ($inaccessibleDatabases.Count -gt 0) {
        throw "A identidade de execucao nao possui acesso a $($inaccessibleDatabases.Count) banco(s) online enumerado(s)."
    }

    $stage = 'consulta dos catalogos Full-Text'
    $queriedDatabaseCount = 0
    $indexes = @(
        foreach ($databaseRow in $databases) {
            $databaseName = [string]$databaseRow.DatabaseName
            $stage = "consulta do banco $databaseName"
            Get-FullTextIndexesFromDatabase -Server $SqlServer -Database $databaseName
            $queriedDatabaseCount++
        }
    )
    $indexes = @(
        $indexes | Sort-Object `
            @{ Expression = { ([string]$_.DatabaseName).ToLowerInvariant() } }, `
            @{ Expression = { ([string]$_.SchemaName).ToLowerInvariant() } }, `
            @{ Expression = { ([string]$_.TableName).ToLowerInvariant() } }
    )

    if ($indexes.Count -eq 0) {
        Write-Output "Servidor consultado: $SqlServer"
        Write-Output "Bancos consultados: $queriedDatabaseCount"
        Write-Output 'Indices Full-Text encontrados: 0'
        Write-Output 'Email enviado: nao'
        exit 0
    }

    $stage = 'carregamento do modulo de email'
    $emailModulePath = Join-Path $PSScriptRoot 'modules\PSPanel.Email\PSPanel.Email.psm1'
    Import-Module $emailModulePath -Force -ErrorAction Stop

    $stage = 'geracao do relatorio HTML'
    $collectedAt = Get-Date
    $sentAt = Get-Date
    $emailBody = New-FullTextReportHtml `
        -Server $SqlServer `
        -Indexes $indexes `
        -EnumeratedDatabaseCount $databases.Count `
        -QueriedDatabaseCount $queriedDatabaseCount `
        -CollectedAt $collectedAt `
        -SentAt $sentAt
    $safeServerName = ConvertTo-SafeSubjectText -Value $SqlServer
    $emailSubject = "PS Panel - Indices Full-Text encontrados em $safeServerName ($($indexes.Count))"

    $stage = 'envio do email'
    Send-PSPanelEmail -To $MailTo -Subject $emailSubject -Body $emailBody -BodyAsHtml -ErrorAction Stop

    Write-Output "Servidor consultado: $SqlServer"
    Write-Output "Bancos consultados: $queriedDatabaseCount"
    Write-Output "Indices Full-Text encontrados: $($indexes.Count)"
    Write-Output 'Email enviado: sim'
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
