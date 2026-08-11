#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArquivoEntrada,

    [string]$DiretorioSaida = ""
)

$ErrorActionPreference = "Stop"

$xlOpenXmlWorkbook = 51
$xlSrcRange = 1
$xlYes = 1
$xlCenter = -4108
$xlTop = -4160

function ConvertTo-TextoComparavel {
    param(
        [AllowEmptyString()]
        [string]$Texto
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) {
        return ""
    }

    $normalizado = $Texto.Normalize(
        [Text.NormalizationForm]::FormD
    )
    $semAcentos = [Text.StringBuilder]::new()

    foreach ($caractere in $normalizado.ToCharArray()) {
        $categoria = [Globalization.CharUnicodeInfo]::GetUnicodeCategory(
            $caractere
        )

        if ($categoria -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$semAcentos.Append($caractere)
        }
    }

    return (($semAcentos.ToString() -replace "\s+", " ").Trim().ToLowerInvariant())
}

function Get-EnderecosEmail {
    param(
        [AllowEmptyString()]
        [string]$Texto
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) {
        return @()
    }

    $padrao = "(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}"
    $enderecos = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($ocorrencia in [regex]::Matches($Texto, $padrao)) {
        try {
            $endereco = [Net.Mail.MailAddress]::new(
                $ocorrencia.Value
            ).Address.ToLowerInvariant()
            [void]$enderecos.Add($endereco)
        }
        catch {
            # Ignora trechos que se parecem com e-mail, mas são inválidos.
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
            $enderecos = @(Get-EnderecosEmail -Texto $Matches[1])

            if ($enderecos.Count -gt 0) {
                return $enderecos[0]
            }
        }
    }

    return ""
}

function Get-DestinatariosRegistro {
    param(
        [AllowEmptyString()]
        [string]$Para,

        [AllowEmptyString()]
        [string]$WebActions
    )

    $destinatarios = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($endereco in @(Get-EnderecosEmail -Texto $Para)) {
        [void]$destinatarios.Add($endereco)
    }

    $enderecoUrl = Get-DestinatarioDaUrlRelease -Url $WebActions

    if (-not [string]::IsNullOrWhiteSpace($enderecoUrl)) {
        [void]$destinatarios.Add($enderecoUrl)
    }

    return @($destinatarios)
}

function Test-EmailPotencialmenteValido {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro
    )

    $assunto = ConvertTo-TextoComparavel -Texto ([string]$Registro.Subject)
    $remetentes = @(Get-EnderecosEmail -Texto ([string]$Registro.From))
    $destinatarios = @(
        Get-DestinatariosRegistro `
            -Para ([string]$Registro.Para) `
            -WebActions ([string]$Registro.WebActions)
    )

    $padroesRespostaAutomatica = @(
        "\bdelivery status notification\b",
        "\bundeliverable\b",
        "\bundelivered mail returned to sender\b",
        "\bmail delivery (failed|failure)\b",
        "\bdelivery failure\b",
        "\breturned mail\b",
        "\bfailure notice\b",
        "\bmensagem nao entregue\b",
        "\bfalha (na|de) entrega\b",
        "\bnao foi possivel entregar\b"
    )

    foreach ($padrao in $padroesRespostaAutomatica) {
        if ($assunto -match $padrao) {
            return [PSCustomObject]@{
                Valido = $false
                Motivo = "Resposta automática de erro de entrega"
            }
        }
    }

    if ($assunto -match "^you got recorded!?[.]?$" ) {
        return [PSCustomObject]@{
            Valido = $false
            Motivo = "Assunto de golpe conhecido: YOU GOT RECORDED!"
        }
    }

    if ($remetentes.Count -eq 0) {
        return [PSCustomObject]@{
            Valido = $false
            Motivo = "Remetente sem endereço de e-mail válido"
        }
    }

    foreach ($remetente in $remetentes) {
        $nomeCaixa = $remetente.Split("@")[0]

        if ($nomeCaixa -in @("mailer-daemon", "mail-daemon", "postmaster")) {
            return [PSCustomObject]@{
                Valido = $false
                Motivo = "Remetente automático do sistema de e-mail"
            }
        }

        if ($destinatarios -contains $remetente) {
            return [PSCustomObject]@{
                Valido = $false
                Motivo = "Remetente e destinatário possuem o mesmo endereço"
            }
        }
    }

    return [PSCustomObject]@{
        Valido = $true
        Motivo = "Sem indicador conclusivo de mensagem inválida"
    }
}

function Add-HyperlinkSeguro {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Planilha,

        [Parameter(Mandatory = $true)]
        [object]$Hyperlinks,

        [Parameter(Mandatory = $true)]
        [string]$EnderecoCelula,

        [AllowEmptyString()]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$EsquemaEsperado
    )

    $uri = $null

    if (
        -not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ine $EsquemaEsperado
    ) {
        return
    }

    $celula = $null

    try {
        $celula = $Planilha.Range($EnderecoCelula)
        [void]$Hyperlinks.Add(
            $celula,
            $Url,
            "",
            "Abrir ação Release",
            $Url
        )
    }
    finally {
        if ($null -ne $celula) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                $celula
            )
        }
    }
}

$excel = $null
$workbookEntrada = $null
$worksheetEntrada = $null
$usedRangeEntrada = $null
$workbookSaida = $null
$worksheetSaida = $null
$headerRange = $null
$dataRange = $null
$usedRangeSaida = $null
$listObject = $null
$hyperlinks = $null

try {
    if (-not (Test-Path -LiteralPath $ArquivoEntrada -PathType Leaf)) {
        throw "O arquivo de entrada não foi encontrado: $ArquivoEntrada"
    }

    $caminhoEntrada = (Resolve-Path -LiteralPath $ArquivoEntrada).Path

    if ([IO.Path]::GetExtension($caminhoEntrada) -ine ".xlsx") {
        throw "O arquivo de entrada deve possuir a extensão .xlsx."
    }

    if ([string]::IsNullOrWhiteSpace($DiretorioSaida)) {
        $DiretorioSaida = Split-Path -Parent $caminhoEntrada
    }

    if (-not (Test-Path -LiteralPath $DiretorioSaida)) {
        New-Item `
            -Path $DiretorioSaida `
            -ItemType Directory `
            -Force | Out-Null
    }

    $diretorioResolvido = (Resolve-Path -LiteralPath $DiretorioSaida).Path
    $nomeBase = [IO.Path]::GetFileNameWithoutExtension($caminhoEntrada)
    $horaArquivo = (Get-Date).ToString("HHmmss")
    $arquivoSaida = Join-Path `
        -Path $diretorioResolvido `
        -ChildPath "$nomeBase-Potencialmente-Validos-$horaArquivo.xlsx"

    Write-Host "Lendo a planilha de quarentena..." -ForegroundColor Cyan

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $workbookEntrada = $excel.Workbooks.Open($caminhoEntrada, 0, $true)
    $worksheetEntrada = $workbookEntrada.Worksheets.Item(1)
    $usedRangeEntrada = $worksheetEntrada.UsedRange

    if ($usedRangeEntrada.Row -ne 1 -or $usedRangeEntrada.Column -ne 1) {
        throw "A tabela de entrada deve começar na célula A1."
    }

    $valoresEntrada = $usedRangeEntrada.Value2
    $primeiraLinha = $valoresEntrada.GetLowerBound(0)
    $ultimaLinha = $valoresEntrada.GetUpperBound(0)
    $primeiraColuna = $valoresEntrada.GetLowerBound(1)
    $ultimaColuna = $valoresEntrada.GetUpperBound(1)
    $cabecalhosEsperados = @(
        "Para",
        "Date",
        "From",
        "Subject",
        "Web Actions",
        "Email Actions"
    )

    if ($ultimaColuna - $primeiraColuna + 1 -ne $cabecalhosEsperados.Count) {
        throw "A planilha deve possuir exatamente as seis colunas esperadas."
    }

    for ($indice = 0; $indice -lt $cabecalhosEsperados.Count; $indice++) {
        $valorCabecalho = [string]$valoresEntrada[
            $primeiraLinha,
            ($primeiraColuna + $indice)
        ]

        if ($valorCabecalho -cne $cabecalhosEsperados[$indice]) {
            throw "Cabeçalho inválido na coluna $($indice + 1): esperado '$($cabecalhosEsperados[$indice])'."
        }
    }

    $registrosValidos = [Collections.Generic.List[object]]::new()
    $totalRegistros = 0
    $motivosDescarte = @{}

    for ($linha = $primeiraLinha + 1; $linha -le $ultimaLinha; $linha++) {
        $valores = New-Object "object[]" 6
        $possuiConteudo = $false

        for ($coluna = 0; $coluna -lt 6; $coluna++) {
            $valores[$coluna] = $valoresEntrada[
                $linha,
                ($primeiraColuna + $coluna)
            ]

            if ($null -ne $valores[$coluna] -and [string]$valores[$coluna] -ne "") {
                $possuiConteudo = $true
            }
        }

        if (-not $possuiConteudo) {
            continue
        }

        $totalRegistros++
        $registro = [PSCustomObject]@{
            Para = [string]$valores[0]
            Date = $valores[1]
            From = [string]$valores[2]
            Subject = [string]$valores[3]
            WebActions = [string]$valores[4]
            EmailActions = [string]$valores[5]
            Valores = $valores
        }
        $classificacao = Test-EmailPotencialmenteValido -Registro $registro

        if ($classificacao.Valido) {
            $registrosValidos.Add($registro)
            continue
        }

        if (-not $motivosDescarte.ContainsKey($classificacao.Motivo)) {
            $motivosDescarte[$classificacao.Motivo] = 0
        }

        $motivosDescarte[$classificacao.Motivo]++
    }

    $workbookEntrada.Close($false)
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
        $usedRangeEntrada
    )
    $usedRangeEntrada = $null
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
        $worksheetEntrada
    )
    $worksheetEntrada = $null
    [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
        $workbookEntrada
    )
    $workbookEntrada = $null

    Write-Host "Criando a planilha com mensagens potencialmente válidas..." `
        -ForegroundColor Cyan

    $workbookSaida = $excel.Workbooks.Add()
    $worksheetSaida = $workbookSaida.Worksheets.Item(1)
    $worksheetSaida.Name = "Quarentena"
    $headerRange = $worksheetSaida.Range("A1", "F1")
    $matrizCabecalhos = New-Object "object[,]" 1, 6

    for ($coluna = 0; $coluna -lt 6; $coluna++) {
        $matrizCabecalhos[0, $coluna] = $cabecalhosEsperados[$coluna]
    }

    $headerRange.Value2 = $matrizCabecalhos

    if ($registrosValidos.Count -gt 0) {
        $matrizSaida = New-Object "object[,]" $registrosValidos.Count, 6

        for ($linha = 0; $linha -lt $registrosValidos.Count; $linha++) {
            for ($coluna = 0; $coluna -lt 6; $coluna++) {
                $matrizSaida[$linha, $coluna] = `
                    $registrosValidos[$linha].Valores[$coluna]
            }
        }

        $ultimaLinhaSaida = $registrosValidos.Count + 1
        $dataRange = $worksheetSaida.Range(
            "A2",
            "F$ultimaLinhaSaida"
        )
        $dataRange.Value2 = $matrizSaida
        $dataRange.VerticalAlignment = $xlTop
        $dataRange.WrapText = $true
        $worksheetSaida.Range(
            "B2",
            "B$ultimaLinhaSaida"
        ).NumberFormat = "dd/mm/yyyy hh:mm:ss"
        $usedRangeSaida = $worksheetSaida.Range(
            "A1",
            "F$ultimaLinhaSaida"
        )
        $listObject = $worksheetSaida.ListObjects.Add(
            $xlSrcRange,
            $usedRangeSaida,
            $null,
            $xlYes
        )
        $listObject.Name = "TabelaQuarentenaValidos"
        $listObject.TableStyle = "TableStyleMedium2"
        $hyperlinks = $worksheetSaida.Hyperlinks

        for ($linha = 0; $linha -lt $registrosValidos.Count; $linha++) {
            $linhaExcel = $linha + 2
            Add-HyperlinkSeguro `
                -Planilha $worksheetSaida `
                -Hyperlinks $hyperlinks `
                -EnderecoCelula "E$linhaExcel" `
                -Url $registrosValidos[$linha].WebActions `
                -EsquemaEsperado "https"
            Add-HyperlinkSeguro `
                -Planilha $worksheetSaida `
                -Hyperlinks $hyperlinks `
                -EnderecoCelula "F$linhaExcel" `
                -Url $registrosValidos[$linha].EmailActions `
                -EsquemaEsperado "mailto"
        }
    }
    else {
        $headerRange.Interior.Color = 12879428
        $headerRange.Font.Color = 16777215
        $headerRange.Font.Bold = $true
        [void]$headerRange.AutoFilter()
    }

    $headerRange.HorizontalAlignment = $xlCenter
    $headerRange.VerticalAlignment = $xlCenter
    $worksheetSaida.Columns.Item("A").ColumnWidth = 32
    $worksheetSaida.Columns.Item("B").ColumnWidth = 22
    $worksheetSaida.Columns.Item("C").ColumnWidth = 36
    $worksheetSaida.Columns.Item("D").ColumnWidth = 45
    $worksheetSaida.Columns.Item("E").ColumnWidth = 22
    $worksheetSaida.Columns.Item("F").ColumnWidth = 22
    $worksheetSaida.Rows.Item(1).RowHeight = 24
    $worksheetSaida.Activate()
    $excel.ActiveWindow.SplitRow = 1
    $excel.ActiveWindow.FreezePanes = $true

    $workbookSaida.SaveAs($arquivoSaida, $xlOpenXmlWorkbook)
    $workbookSaida.Close($false)
    $excel.Quit()

    Write-Host ""
    Write-Host "Validação concluída." -ForegroundColor Green
    Write-Host "Registros analisados: $totalRegistros"
    Write-Host "Potencialmente válidos: $($registrosValidos.Count)"
    Write-Host "Descartados: $($totalRegistros - $registrosValidos.Count)"

    foreach ($motivo in ($motivosDescarte.Keys | Sort-Object)) {
        Write-Host "  - $motivo`: $($motivosDescarte[$motivo])"
    }

    Write-Host "Arquivo criado: $arquivoSaida"
}
catch {
    Write-Error @"
Não foi possível validar a planilha de quarentena.

Erro: $($_.Exception.Message)

Confirme que:
1. O arquivo de entrada é um .xlsx gerado pelo exportador da quarentena.
2. O arquivo possui as colunas Para, Date, From, Subject, Web Actions e Email Actions.
3. O Microsoft Excel está instalado.
4. O arquivo de entrada não está corrompido ou protegido por senha.
"@

    exit 1
}
finally {
    foreach ($workbook in @($workbookSaida, $workbookEntrada)) {
        if ($null -ne $workbook) {
            try {
                $workbook.Close($false)
            }
            catch {
                # Ignora erros durante o fechamento das pastas de trabalho.
            }
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
        $hyperlinks,
        $listObject,
        $usedRangeSaida,
        $dataRange,
        $headerRange,
        $worksheetSaida,
        $workbookSaida,
        $usedRangeEntrada,
        $worksheetEntrada,
        $workbookEntrada,
        $excel
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
