<#
.SYNOPSIS
Exporta para uma planilha Excel as mensagens de quarentena de uma caixa
compartilhada do Outlook.

.DESCRIPTION
Acessa a Caixa de Entrada de uma caixa compartilhada pelo Outlook clássico,
localiza as mensagens recebidas na data informada e extrai as linhas da tabela
de quarentena presente no corpo HTML de cada mensagem.

O resultado é salvo em um arquivo XLSX com destinatário, data, remetente,
assunto e links de liberação. O nome do arquivo contém a data consultada e a
data e hora da execução.

O script requer Windows PowerShell 5.1, Outlook clássico e Microsoft Excel
instalados. A conta do usuário deve estar autenticada no Outlook e possuir
permissão para acessar a caixa compartilhada.

.PARAMETER CaixaCompartilhada
Endereço SMTP da caixa compartilhada que contém as mensagens de quarentena.
O valor padrão é "quarentena-email@desenbahia.ba.gov.br".

.PARAMETER DiretorioSaida
Diretório no qual a planilha XLSX será criada. O diretório é criado
automaticamente quando não existe. O valor padrão é "C:\Temp\quarentena".

.PARAMETER DataMensagens
Data das mensagens que serão exportadas. Aceita os formatos yyyy-MM-dd e
dd/MM/yyyy. Quando omitida ou vazia, utiliza a data atual.

.EXAMPLE
.\Exportar-Quarentena-Outlook.ps1

Exporta as mensagens do dia atual usando a caixa compartilhada e o diretório
de saída padrão.

.EXAMPLE
.\Exportar-Quarentena-Outlook.ps1 -DataMensagens "2026-08-11"

Exporta as mensagens recebidas em 11/08/2026 usando o formato ISO.

.EXAMPLE
.\Exportar-Quarentena-Outlook.ps1 `
    -CaixaCompartilhada "quarentena@empresa.com.br" `
    -DiretorioSaida "D:\Relatorios\Quarentena" `
    -DataMensagens "11/08/2026"

Exporta as mensagens da caixa e da data informadas para um diretório
personalizado.

.INPUTS
Nenhum. O script não aceita objetos pela entrada do pipeline.

.OUTPUTS
Nenhum objeto é enviado ao pipeline. O script cria uma planilha XLSX e exibe
o resumo da exportação no console.

.NOTES
Execute o script com o mesmo usuário do Windows que utiliza o perfil do
Outlook. As mensagens precisam conter uma tabela HTML com os cabeçalhos Date,
From, Subject, Web Actions e Email Actions.
#>

#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$CaixaCompartilhada = "quarentena-email@desenbahia.ba.gov.br",
    [string]$DiretorioSaida = "C:\Temp\quarentena",
    [string]$DataMensagens = ""
)

$ErrorActionPreference = "Stop"

# Constantes do Outlook e do Excel.
$olFolderInbox = 6
$olMailItem = 43
$olTo = 1
$xlOpenXmlWorkbook = 51
$prSmtpAddressUnicode = "http://schemas.microsoft.com/mapi/proptag/0x39FE001F"
$prSmtpAddressAnsi = "http://schemas.microsoft.com/mapi/proptag/0x39FE001E"

function ConvertTo-DataMensagens {
    param(
        [AllowEmptyString()]
        [string]$Valor
    )

    if ([string]::IsNullOrWhiteSpace($Valor)) {
        return (Get-Date).Date
    }

    $data = [datetime]::MinValue
    $valorNormalizado = $Valor.Trim()
    $formatos = @(
        [PSCustomObject]@{
            Formato = "yyyy-MM-dd"
            Cultura = [Globalization.CultureInfo]::InvariantCulture
        },
        [PSCustomObject]@{
            Formato = "dd/MM/yyyy"
            Cultura = [Globalization.CultureInfo]::GetCultureInfo("pt-BR")
        }
    )

    foreach ($formato in $formatos) {
        if (
            [datetime]::TryParseExact(
                $valorNormalizado,
                $formato.Formato,
                $formato.Cultura,
                [Globalization.DateTimeStyles]::None,
                [ref]$data
            )
        ) {
            return $data.Date
        }
    }

    throw "Data inválida em -DataMensagens. Use yyyy-MM-dd ou dd/MM/yyyy."
}

function ConvertTo-TextoNormalizado {
    param(
        [AllowNull()]
        [object]$NoHtml
    )

    if ($null -eq $NoHtml) {
        return ""
    }

    $texto = [string]$NoHtml.innerText

    if ([string]::IsNullOrWhiteSpace($texto)) {
        return ""
    }

    $texto = [Net.WebUtility]::HtmlDecode($texto)
    $texto = $texto.Replace([char]0x00A0, " ")
    return (($texto -replace "\s+", " ").Trim())
}

function Get-UrlAcaoRelease {
    param(
        [AllowNull()]
        [object]$CelulaHtml
    )

    if ($null -eq $CelulaHtml) {
        return ""
    }

    $links = $CelulaHtml.getElementsByTagName("a")

    for ($indice = 0; $indice -lt $links.length; $indice++) {
        $link = $links.item($indice)
        $textoLink = ConvertTo-TextoNormalizado -NoHtml $link

        if ($textoLink -ine "Release") {
            continue
        }

        $url = [string]$link.getAttribute("href")

        if (-not [string]::IsNullOrWhiteSpace($url)) {
            return $url.Trim()
        }
    }

    return ""
}

function ConvertTo-EnderecoEmailValido {
    param(
        [AllowEmptyString()]
        [string]$Valor
    )

    if ([string]::IsNullOrWhiteSpace($Valor)) {
        return ""
    }

    $candidato = $Valor.Trim() -replace "^(?i)smtp:", ""

    try {
        $endereco = [Net.Mail.MailAddress]::new($candidato).Address

        if ($endereco -notmatch "@") {
            return ""
        }

        return $endereco.ToLowerInvariant()
    }
    catch {
        return ""
    }
}

function Get-EnderecoSmtpDestinatario {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Destinatario
    )

    $addressEntry = $null
    $propertyAccessor = $null
    $exchangeUser = $null
    $exchangeDistributionList = $null

    try {
        $addressEntry = $Destinatario.AddressEntry

        if ($null -eq $addressEntry) {
            return ConvertTo-EnderecoEmailValido `
                -Valor ([string]$Destinatario.Address)
        }

        $propertyAccessor = $addressEntry.PropertyAccessor

        foreach ($propriedade in @(
            $script:prSmtpAddressUnicode,
            $script:prSmtpAddressAnsi
        )) {
            try {
                $endereco = ConvertTo-EnderecoEmailValido `
                    -Valor ([string]$propertyAccessor.GetProperty($propriedade))

                if (-not [string]::IsNullOrWhiteSpace($endereco)) {
                    return $endereco
                }
            }
            catch {
                # A propriedade pode não existir em todos os tipos de destinatário.
            }
        }

        if ([string]$addressEntry.Type -ieq "EX") {
            try {
                $exchangeUser = $addressEntry.GetExchangeUser()

                if ($null -ne $exchangeUser) {
                    $endereco = ConvertTo-EnderecoEmailValido `
                        -Valor ([string]$exchangeUser.PrimarySmtpAddress)

                    if (-not [string]::IsNullOrWhiteSpace($endereco)) {
                        return $endereco
                    }
                }
            }
            catch {
                # A entrada pode não representar um usuário Exchange.
            }

            try {
                $exchangeDistributionList = `
                    $addressEntry.GetExchangeDistributionList()

                if ($null -ne $exchangeDistributionList) {
                    $endereco = ConvertTo-EnderecoEmailValido `
                        -Valor ([string]$exchangeDistributionList.PrimarySmtpAddress)

                    if (-not [string]::IsNullOrWhiteSpace($endereco)) {
                        return $endereco
                    }
                }
            }
            catch {
                # A entrada pode não representar uma lista de distribuição.
            }
        }

        $endereco = ConvertTo-EnderecoEmailValido `
            -Valor ([string]$addressEntry.Address)

        if (-not [string]::IsNullOrWhiteSpace($endereco)) {
            return $endereco
        }

        return ConvertTo-EnderecoEmailValido `
            -Valor ([string]$Destinatario.Address)
    }
    finally {
        foreach ($objeto in @(
            $exchangeDistributionList,
            $exchangeUser,
            $propertyAccessor,
            $addressEntry
        )) {
            if (
                $null -ne $objeto -and
                [Runtime.InteropServices.Marshal]::IsComObject($objeto)
            ) {
                try {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                        $objeto
                    )
                }
                catch {
                    # Ignora erros durante a liberação dos objetos COM.
                }
            }
        }
    }
}

function Get-DestinatariosSmtp {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Mensagem
    )

    $recipients = $null
    $enderecos = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    try {
        $recipients = $Mensagem.Recipients

        for ($indice = 1; $indice -le $recipients.Count; $indice++) {
            $destinatario = $null

            try {
                $destinatario = $recipients.Item($indice)

                if ([int]$destinatario.Type -ne $script:olTo) {
                    continue
                }

                $endereco = Get-EnderecoSmtpDestinatario `
                    -Destinatario $destinatario

                if (-not [string]::IsNullOrWhiteSpace($endereco)) {
                    [void]$enderecos.Add($endereco)
                }
            }
            finally {
                if (
                    $null -ne $destinatario -and
                    [Runtime.InteropServices.Marshal]::IsComObject($destinatario)
                ) {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                        $destinatario
                    )
                }
            }
        }
    }
    finally {
        if (
            $null -ne $recipients -and
            [Runtime.InteropServices.Marshal]::IsComObject($recipients)
        ) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                $recipients
            )
        }
    }

    if ($enderecos.Count -eq 0) {
        foreach ($ocorrencia in [regex]::Matches(
            [string]$Mensagem.To,
            "(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"
        )) {
            $endereco = ConvertTo-EnderecoEmailValido -Valor $ocorrencia.Value

            if (-not [string]::IsNullOrWhiteSpace($endereco)) {
                [void]$enderecos.Add($endereco)
            }
        }
    }

    return @($enderecos)
}

function Get-DestinatarioDaUrlRelease {
    param(
        [AllowEmptyString()]
        [string]$Url
    )

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return ""
    }

    $uri = $null

    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri)) {
        return ""
    }

    foreach ($parte in $uri.Query.TrimStart("?").Split("&")) {
        $chaveValor = $parte.Split(@("="), 2, [StringSplitOptions]::None)

        if ($chaveValor.Count -ne 2 -or $chaveValor[0] -ine "release") {
            continue
        }

        $valor = [Uri]::UnescapeDataString(
            $chaveValor[1].Replace("+", " ")
        )

        if ($valor -match "^[01]:([^:]+@[^:]+):") {
            return ConvertTo-EnderecoEmailValido -Valor $Matches[1]
        }
    }

    return ""
}

function ConvertTo-ValorDataExcel {
    param(
        [AllowEmptyString()]
        [string]$Texto
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) {
        return ""
    }

    $cultura = [Globalization.CultureInfo]::GetCultureInfo("pt-BR")
    $estilos = [Globalization.DateTimeStyles]::AllowWhiteSpaces
    $data = [datetimeoffset]::MinValue

    if (
        [datetimeoffset]::TryParse(
            $Texto,
            $cultura,
            $estilos,
            [ref]$data
        )
    ) {
        return $data.DateTime.ToOADate()
    }

    # Alguns relatórios incluem dia da semana, a palavra "de", abreviação
    # de mês sem ponto e fuso no formato -0300.
    $textoSemDiaDaSemana = $Texto -replace "^[^,]+,\s*", ""
    $textoSemDiaDaSemana = $textoSemDiaDaSemana -replace "\s+de\s+", " "
    $textoSemDiaDaSemana = $textoSemDiaDaSemana -replace `
        "(?i)\b(jan|fev|mar|abr|mai|jun|jul|ago|set|out|nov|dez)\b\.?", `
        '$1.'
    $textoSemDiaDaSemana = $textoSemDiaDaSemana -replace `
        "([+-]\d{2})(\d{2})$", `
        '$1:$2'

    if (
        [datetimeoffset]::TryParse(
            $textoSemDiaDaSemana,
            $cultura,
            $estilos,
            [ref]$data
        )
    ) {
        return $data.DateTime.ToOADate()
    }

    # Preserva o conteúdo original quando o formato de data não for reconhecido.
    return $Texto
}

function Get-LinhasTabelaQuarentena {
    param(
        [Parameter(Mandatory)]
        [object]$Mensagem
    )

    $documento = $null

    try {
        $corpoHtml = [string]$Mensagem.HTMLBody

        if ([string]::IsNullOrWhiteSpace($corpoHtml)) {
            return @()
        }

        $documento = New-Object -ComObject "HTMLFile"
        $argumentosWrite = [object[]]@([object[]]@($corpoHtml))
        [void]$documento.GetType().InvokeMember(
            "write",
            [Reflection.BindingFlags]::InvokeMethod,
            $null,
            $documento,
            $argumentosWrite
        )
        $documento.close()

        $cabecalhosEsperados = @(
            "Date",
            "From",
            "Subject",
            "Web Actions",
            "Email Actions"
        )

        $tabelas = $documento.getElementsByTagName("table")

        for ($indiceTabela = 0; $indiceTabela -lt $tabelas.length; $indiceTabela++) {
            $tabela = $tabelas.item($indiceTabela)
            $linhas = $tabela.rows
            $indiceCabecalho = -1
            $indicesColunas = @{}

            for ($indiceLinha = 0; $indiceLinha -lt $linhas.length; $indiceLinha++) {
                $celulas = $linhas.item($indiceLinha).cells
                $indicesCandidatos = @{}

                for ($indiceCelula = 0; $indiceCelula -lt $celulas.length; $indiceCelula++) {
                    $textoCabecalho = ConvertTo-TextoNormalizado `
                        -NoHtml $celulas.item($indiceCelula)

                    foreach ($cabecalho in $cabecalhosEsperados) {
                        if ($textoCabecalho -ieq $cabecalho) {
                            $indicesCandidatos[$cabecalho] = $indiceCelula
                            break
                        }
                    }
                }

                if ($indicesCandidatos.Count -eq $cabecalhosEsperados.Count) {
                    $indiceCabecalho = $indiceLinha
                    $indicesColunas = $indicesCandidatos
                    break
                }
            }

            if ($indiceCabecalho -lt 0) {
                continue
            }

            $resultado = [System.Collections.Generic.List[object]]::new()

            for (
                $indiceLinha = $indiceCabecalho + 1;
                $indiceLinha -lt $linhas.length;
                $indiceLinha++
            ) {
                $celulas = $linhas.item($indiceLinha).cells
                $maiorIndice = (
                    $indicesColunas.Values |
                        Measure-Object -Maximum
                ).Maximum

                if ($celulas.length -le $maiorIndice) {
                    continue
                }

                $linha = [ordered]@{}

                foreach ($cabecalho in $cabecalhosEsperados) {
                    $celula = $celulas.item($indicesColunas[$cabecalho])

                    if ($cabecalho -in @("Web Actions", "Email Actions")) {
                        $linha[$cabecalho] = Get-UrlAcaoRelease `
                            -CelulaHtml $celula
                    }
                    else {
                        $linha[$cabecalho] = ConvertTo-TextoNormalizado `
                            -NoHtml $celula
                    }
                }

                $possuiConteudo = $false

                foreach ($valor in $linha.Values) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$valor)) {
                        $possuiConteudo = $true
                        break
                    }
                }

                if ($possuiConteudo) {
                    $resultado.Add([PSCustomObject]$linha)
                }
            }

            # A mensagem de quarentena contém apenas uma tabela com esses campos.
            return @($resultado)
        }

        return @()
    }
    finally {
        if ($null -ne $documento) {
            try {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                    $documento
                )
            }
            catch {
                # Ignora erros durante a liberação do documento HTML.
            }
        }
    }
}

$outlook = $null
$namespace = $null
$recipient = $null
$inbox = $null
$items = $null
$excel = $null
$workbook = $null
$worksheet = $null
$headerRange = $null
$dataRange = $null
$usedRange = $null
$listObject = $null
$hyperlinks = $null

try {
    $inicioDataMensagens = ConvertTo-DataMensagens -Valor $DataMensagens
    $fimDataMensagens = $inicioDataMensagens.AddDays(1)

    Write-Host "Acessando o perfil do Outlook..." -ForegroundColor Cyan

    # Abre ou reutiliza a instância do Outlook clássico.
    $outlook = New-Object -ComObject Outlook.Application
    $namespace = $outlook.GetNamespace("MAPI")

    # Resolve a caixa compartilhada no catálogo do Microsoft 365.
    $recipient = $namespace.CreateRecipient($CaixaCompartilhada)
    $recipient.Resolve()

    if (-not $recipient.Resolved) {
        throw "A caixa '$CaixaCompartilhada' não foi localizada no catálogo do Outlook."
    }

    # Abre a Caixa de Entrada compartilhada.
    $inbox = $namespace.GetSharedDefaultFolder(
        $recipient,
        $olFolderInbox
    )

    if ($null -eq $inbox) {
        throw "Não foi possível acessar a Caixa de Entrada compartilhada."
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida)) {
        New-Item `
            -Path $DiretorioSaida `
            -ItemType Directory `
            -Force | Out-Null
    }

    Write-Host "Lendo mensagens de $($inicioDataMensagens.ToString('dd/MM/yyyy'))..."

    $items = $inbox.Items

    # Ordena da mensagem mais recente para a mais antiga.
    $items.Sort("[ReceivedTime]", $true)

    $resultado = [System.Collections.Generic.List[object]]::new()
    $mensagensDaData = 0
    $mensagensSemTabela = 0
    $linhasSemDestinatarioSmtp = 0

    for ($indice = 1; $indice -le $items.Count; $indice++) {
        $item = $null

        try {
            $item = $items.Item($indice)

            # Considera apenas mensagens de email comuns.
            if ($item.Class -ne $olMailItem) {
                continue
            }

            $dataRecebimento = [datetime]$item.ReceivedTime

            # Como a coleção está em ordem decrescente,
            # podemos encerrar quando chegarmos ao dia anterior.
            if ($dataRecebimento -lt $inicioDataMensagens) {
                break
            }

            if ($dataRecebimento -ge $fimDataMensagens) {
                continue
            }

            $mensagensDaData++
            $destinatariosMensagem = @(
                Get-DestinatariosSmtp -Mensagem $item
            )

            $linhasMensagem = @(
                Get-LinhasTabelaQuarentena -Mensagem $item
            )

            if ($linhasMensagem.Count -eq 0) {
                $mensagensSemTabela++
                continue
            }

            for ($ordem = 0; $ordem -lt $linhasMensagem.Count; $ordem++) {
                $linhaMensagem = $linhasMensagem[$ordem]
                $destinatarios = $destinatariosMensagem -join "; "

                if ([string]::IsNullOrWhiteSpace($destinatarios)) {
                    $destinatarios = Get-DestinatarioDaUrlRelease `
                        -Url ([string]$linhaMensagem."Web Actions")
                }

                if ([string]::IsNullOrWhiteSpace($destinatarios)) {
                    $destinatarios = "(não informado)"
                    $linhasSemDestinatarioSmtp++
                }

                $resultado.Add(
                    [PSCustomObject]@{
                        Para = $destinatarios
                        Date = $linhaMensagem.Date
                        From = $linhaMensagem.From
                        Subject = $linhaMensagem.Subject
                        WebActions = $linhaMensagem."Web Actions"
                        EmailActions = $linhaMensagem."Email Actions"
                        MensagemRecebida = $dataRecebimento
                        OrdemNaMensagem = $ordem
                    }
                )
            }
        }
        finally {
            if ($null -ne $item) {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                    $item
                )
            }
        }
    }

    $linhasOrdenadas = @(
        $resultado |
            Sort-Object MensagemRecebida, OrdemNaMensagem
    )

    $dataArquivo = $inicioDataMensagens.ToString("yyyy-MM-dd")
    $dataHoraExecucaoArquivo = (Get-Date).ToString("yyyy-MM-dd_HHmmss")
    $arquivoSaida = Join-Path `
        -Path $DiretorioSaida `
        -ChildPath "Quarentena-Emails-${dataArquivo}_${dataHoraExecucaoArquivo}.xlsx"

    Write-Host "Criando a planilha Excel..." -ForegroundColor Cyan

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbook = $excel.Workbooks.Add()
    $worksheet = $workbook.Worksheets.Item(1)
    $worksheet.Name = "Quarentena"

    $cabecalhos = @(
        "Para",
        "Date",
        "From",
        "Subject",
        "Web Actions",
        "Email Actions"
    )

    $headerRange = $worksheet.Range("A1", "F1")
    $matrizCabecalhos = New-Object "object[,]" 1, $cabecalhos.Count

    for ($coluna = 0; $coluna -lt $cabecalhos.Count; $coluna++) {
        $matrizCabecalhos[0, $coluna] = $cabecalhos[$coluna]
    }

    $headerRange.Value2 = $matrizCabecalhos

    if ($linhasOrdenadas.Count -gt 0) {
        $matrizDados = New-Object "object[,]" $linhasOrdenadas.Count, 6

        for ($linha = 0; $linha -lt $linhasOrdenadas.Count; $linha++) {
            $registro = $linhasOrdenadas[$linha]
            $matrizDados[$linha, 0] = $registro.Para
            $matrizDados[$linha, 1] = ConvertTo-ValorDataExcel $registro.Date
            $matrizDados[$linha, 2] = $registro.From
            $matrizDados[$linha, 3] = $registro.Subject
            $matrizDados[$linha, 4] = $registro.WebActions
            $matrizDados[$linha, 5] = $registro.EmailActions
        }

        $ultimaLinha = $linhasOrdenadas.Count + 1
        $dataRange = $worksheet.Range("A2", "F$ultimaLinha")
        $dataRange.Value2 = $matrizDados
        $dataRange.VerticalAlignment = -4160
        $dataRange.WrapText = $true
        $worksheet.Range("B2", "B$ultimaLinha").NumberFormat = `
            "dd/mm/yyyy hh:mm:ss"
        $usedRange = $worksheet.Range("A1", "F$ultimaLinha")
        $listObject = $worksheet.ListObjects.Add(
            1,
            $usedRange,
            $null,
            1
        )
        $listObject.Name = "TabelaQuarentena"
        $listObject.TableStyle = "TableStyleMedium2"

        # Cada coluna de ação contém apenas a URL individual de Release.
        $hyperlinks = $worksheet.Hyperlinks

        for ($linha = 0; $linha -lt $linhasOrdenadas.Count; $linha++) {
            $linhaExcel = $linha + 2
            $acoes = @(
                @{
                    Coluna = "E"
                    Url = [string]$linhasOrdenadas[$linha].WebActions
                    Esquema = "https"
                },
                @{
                    Coluna = "F"
                    Url = [string]$linhasOrdenadas[$linha].EmailActions
                    Esquema = "mailto"
                }
            )

            foreach ($acao in $acoes) {
                $uri = $null

                if (
                    [Uri]::TryCreate(
                        $acao.Url,
                        [UriKind]::Absolute,
                        [ref]$uri
                    ) -and
                    $uri.Scheme -ieq $acao.Esquema
                ) {
                    $celulaAcao = $null

                    try {
                        $celulaAcao = $worksheet.Range(
                            "$($acao.Coluna)$linhaExcel"
                        )
                        [void]$hyperlinks.Add(
                            $celulaAcao,
                            $acao.Url,
                            "",
                            "Abrir ação Release",
                            $acao.Url
                        )
                    }
                    finally {
                        if ($null -ne $celulaAcao) {
                            [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                                $celulaAcao
                            )
                        }
                    }
                }
            }
        }
    }
    else {
        $headerRange.Interior.Color = 12879428
        $headerRange.Font.Color = 16777215
        $headerRange.Font.Bold = $true
        [void]$headerRange.AutoFilter()
    }

    $headerRange.HorizontalAlignment = -4108
    $headerRange.VerticalAlignment = -4108
    $worksheet.Columns.Item("A").ColumnWidth = 32
    $worksheet.Columns.Item("B").ColumnWidth = 22
    $worksheet.Columns.Item("C").ColumnWidth = 36
    $worksheet.Columns.Item("D").ColumnWidth = 45
    $worksheet.Columns.Item("E").ColumnWidth = 22
    $worksheet.Columns.Item("F").ColumnWidth = 22
    $worksheet.Rows.Item(1).RowHeight = 24

    $worksheet.Activate()
    $excel.ActiveWindow.SplitRow = 1
    $excel.ActiveWindow.FreezePanes = $true

    $workbook.SaveAs($arquivoSaida, $xlOpenXmlWorkbook)
    $workbook.Close($false)
    $workbook = $null
    $excel.Quit()

    Write-Host ""
    Write-Host "Exportação concluída." -ForegroundColor Green
    Write-Host "Caixa: $CaixaCompartilhada"
    Write-Host "Data das mensagens: $($inicioDataMensagens.ToString('dd/MM/yyyy'))"
    Write-Host "Mensagens encontradas na data: $mensagensDaData"
    Write-Host "Mensagens sem a tabela esperada: $mensagensSemTabela"
    Write-Host "Linhas sem destinatário SMTP: $linhasSemDestinatarioSmtp"
    Write-Host "Linhas exportadas: $($linhasOrdenadas.Count)"
    Write-Host "Arquivo criado: $arquivoSaida"
}
catch {
    Write-Error @"
Não foi possível exportar as mensagens da caixa compartilhada.

Erro: $($_.Exception.Message)

Confirme que:
1. O Outlook clássico e o Microsoft Excel estão instalados.
2. Sua conta está configurada e autenticada no Outlook clássico.
3. A caixa compartilhada pode ser aberta manualmente no Outlook.
4. O script está sendo executado com o mesmo usuário do Windows que utiliza o Outlook.
5. As mensagens possuem a tabela com os cabeçalhos esperados.
"@

    exit 1
}
finally {
    if ($null -ne $workbook) {
        try {
            $workbook.Close($false)
        }
        catch {
            # Ignora erros durante o fechamento da pasta de trabalho.
        }
    }

    if ($null -ne $excel) {
        try {
            $excel.Quit()
        }
        catch {
            # Ignora erros durante o encerramento do Excel.
        }
    }

    foreach ($objeto in @(
        $listObject,
        $hyperlinks,
        $usedRange,
        $dataRange,
        $headerRange,
        $worksheet,
        $workbook,
        $excel,
        $items,
        $inbox,
        $recipient,
        $namespace,
        $outlook
    )) {
        if ($null -ne $objeto) {
            try {
                [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                    $objeto
                )
            }
            catch {
                # Ignora erros durante a liberação dos objetos COM.
            }
        }
    }

    [GC]::Collect()
    [GC]::WaitForPendingFinalizers()
}
