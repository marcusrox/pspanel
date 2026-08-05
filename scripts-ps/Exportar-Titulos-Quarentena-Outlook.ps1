#requires -Version 5.1

[CmdletBinding()]
param(
    [string]$CaixaCompartilhada = "quarentena-email@desenbahia.ba.gov.br",
    [string]$DiretorioSaida = "C:\Temp\quarentena"
)

$ErrorActionPreference = "Stop"

# Constantes do Outlook e do Excel.
$olFolderInbox = 6
$olMailItem = 43
$xlOpenXmlWorkbook = 51

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
                    $linha[$cabecalho] = ConvertTo-TextoNormalizado `
                        -NoHtml $celulas.item($indicesColunas[$cabecalho])
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

try {
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

    $inicioHoje = (Get-Date).Date
    $inicioAmanha = $inicioHoje.AddDays(1)

    Write-Host "Lendo mensagens de $($inicioHoje.ToString('dd/MM/yyyy'))..."

    $items = $inbox.Items

    # Ordena da mensagem mais recente para a mais antiga.
    $items.Sort("[ReceivedTime]", $true)

    $resultado = [System.Collections.Generic.List[object]]::new()
    $mensagensDoDia = 0
    $mensagensSemTabela = 0

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
            if ($dataRecebimento -lt $inicioHoje) {
                break
            }

            if ($dataRecebimento -ge $inicioAmanha) {
                continue
            }

            $mensagensDoDia++
            $destinatarios = ([string]$item.To).Trim()

            if ([string]::IsNullOrWhiteSpace($destinatarios)) {
                $destinatarios = "(não informado)"
            }

            $linhasMensagem = @(
                Get-LinhasTabelaQuarentena -Mensagem $item
            )

            if ($linhasMensagem.Count -eq 0) {
                $mensagensSemTabela++
                continue
            }

            for ($ordem = 0; $ordem -lt $linhasMensagem.Count; $ordem++) {
                $linhaMensagem = $linhasMensagem[$ordem]

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

    $dataArquivo = $inicioHoje.ToString("yyyy-MM-dd")
    $horaArquivo = (Get-Date).ToString("HHmmss")
    $arquivoSaida = Join-Path `
        -Path $DiretorioSaida `
        -ChildPath "Quarentena-Emails-$dataArquivo-$horaArquivo.xlsx"

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
    Write-Host "Mensagens encontradas hoje: $mensagensDoDia"
    Write-Host "Mensagens sem a tabela esperada: $mensagensSemTabela"
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
