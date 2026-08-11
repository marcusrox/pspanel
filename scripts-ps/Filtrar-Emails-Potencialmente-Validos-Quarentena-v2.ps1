#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArquivoEntrada,

    [string]$DiretorioSaida = "",

    [string]$DiretorioCache = "",

    [string]$DominiosInternos = "desenbahia.ba.gov.br"
)

$ErrorActionPreference = "Stop"

$xlOpenXmlWorkbook = 51
$xlSrcRange = 1
$xlYes = 1
$xlCenter = -4108
$xlTop = -4160
$olExchangeUserAddressEntry = 0
$olExchangeDistributionListAddressEntry = 1
$olExchangeRemoteUserAddressEntry = 5
$prProxyAddressesUnicode = "http://schemas.microsoft.com/mapi/proptag/0x800F101F"
$prProxyAddressesAnsi = "http://schemas.microsoft.com/mapi/proptag/0x800F101E"

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

function Get-DominiosInternosConfigurados {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Valor
    )

    $dominios = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($dominio in ($Valor -split "[,;\s]+")) {
        $normalizado = $dominio.Trim().TrimStart("@").ToLowerInvariant()

        if (-not [string]::IsNullOrWhiteSpace($normalizado)) {
            [void]$dominios.Add($normalizado)
        }
    }

    if ($dominios.Count -eq 0) {
        throw "Informe ao menos um domínio interno para validação."
    }

    return ,$dominios
}

function Test-DominioInterno {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endereco,

        [Parameter(Mandatory = $true)]
        [object]$Dominios
    )

    $partes = $Endereco.Split("@")

    if ($partes.Count -ne 2) {
        return $false
    }

    return $Dominios.Contains($partes[1])
}

function Read-CacheEnderecos {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caminho
    )

    $enderecos = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
        return ,$enderecos
    }

    foreach ($linha in (Get-Content -LiteralPath $Caminho -Encoding UTF8)) {
        $endereco = @(Get-EnderecosEmail -Texto ([string]$linha))

        if ($endereco.Count -eq 1) {
            [void]$enderecos.Add($endereco[0])
        }
    }

    return ,$enderecos
}

function Save-CacheEnderecos {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caminho,

        [Parameter(Mandatory = $true)]
        [object]$Enderecos
    )

    $conteudo = @($Enderecos | Sort-Object)

    if ($conteudo.Count -eq 0) {
        Set-Content `
            -LiteralPath $Caminho `
            -Value @() `
            -Encoding UTF8
        return
    }

    Set-Content `
        -LiteralPath $Caminho `
        -Value $conteudo `
        -Encoding UTF8
}

function Test-EnderecoNoCatalogoOutlook {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Namespace,

        [Parameter(Mandatory = $true)]
        [string]$Endereco
    )

    $recipient = $null
    $addressEntry = $null
    $exchangeEntry = $null
    $propertyAccessor = $null

    try {
        $recipient = $Namespace.CreateRecipient($Endereco)
        [void]$recipient.Resolve()

        if (-not $recipient.Resolved) {
            return $false
        }

        try {
            $addressEntry = $recipient.AddressEntry
        }
        catch {
            return $false
        }

        if ($null -eq $addressEntry) {
            return $false
        }

        $tipo = [int]$addressEntry.AddressEntryUserType

        if ($tipo -notin @(
            $script:olExchangeUserAddressEntry,
            $script:olExchangeDistributionListAddressEntry,
            $script:olExchangeRemoteUserAddressEntry
        )) {
            return $false
        }

        $enderecosResolvidos = [Collections.Generic.HashSet[string]]::new(
            [StringComparer]::OrdinalIgnoreCase
        )

        try {
            if ($tipo -eq $script:olExchangeDistributionListAddressEntry) {
                $exchangeEntry = $addressEntry.GetExchangeDistributionList()
            }
            else {
                $exchangeEntry = $addressEntry.GetExchangeUser()
            }

            if ($null -ne $exchangeEntry) {
                foreach ($enderecoSmtp in @(
                    Get-EnderecosEmail `
                        -Texto ([string]$exchangeEntry.PrimarySmtpAddress)
                )) {
                    [void]$enderecosResolvidos.Add($enderecoSmtp)
                }
            }
        }
        catch {
            # A entrada sem SMTP primário não comprova que o endereço existe.
        }

        try {
            $propertyAccessor = $addressEntry.PropertyAccessor

            foreach ($propriedade in @(
                $script:prProxyAddressesUnicode,
                $script:prProxyAddressesAnsi
            )) {
                try {
                    $enderecosProxy = @(
                        $propertyAccessor.GetProperty($propriedade)
                    )

                    foreach ($enderecoProxy in $enderecosProxy) {
                        $valorProxy = ([string]$enderecoProxy) -replace `
                            "^(?i)smtp:", `
                            ""

                        foreach ($enderecoSmtp in @(
                            Get-EnderecosEmail -Texto $valorProxy
                        )) {
                            [void]$enderecosResolvidos.Add($enderecoSmtp)
                        }
                    }
                }
                catch {
                    # Nem todo provedor expõe a coleção de aliases SMTP.
                }
            }
        }
        catch {
            # Sem aliases, a validação permanece restrita ao SMTP primário.
        }

        $enderecoConsultado = @(Get-EnderecosEmail -Texto $Endereco)

        if ($enderecoConsultado.Count -ne 1) {
            return $false
        }

        return [bool]$enderecosResolvidos.Contains($enderecoConsultado[0])
    }
    finally {
        foreach ($objeto in @(
            $propertyAccessor,
            $exchangeEntry,
            $addressEntry,
            $recipient
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

function Test-DestinatariosNoCatalogo {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro,

        [Parameter(Mandatory = $true)]
        [object]$Namespace,

        [Parameter(Mandatory = $true)]
        [object]$Dominios,

        [Parameter(Mandatory = $true)]
        [object]$CacheValidos,

        [Parameter(Mandatory = $true)]
        [object]$CacheInvalidos,

        [Parameter(Mandatory = $true)]
        [hashtable]$Estatisticas
    )

    $destinatarios = @(
        Get-DestinatariosRegistro `
            -Para ([string]$Registro.Para) `
            -WebActions ([string]$Registro.WebActions)
    )
    $internos = @(
        $destinatarios |
            Where-Object {
                Test-DominioInterno `
                    -Endereco $_ `
                    -Dominios $Dominios
            }
    )

    # Endereços externos não são esperados no catálogo corporativo.
    if ($internos.Count -eq 0) {
        return [PSCustomObject]@{
            Valido = $true
            Motivo = "Sem destinatário interno para validar no catálogo"
        }
    }

    foreach ($endereco in $internos) {
        if ($CacheValidos.Contains($endereco)) {
            $Estatisticas.CacheValidos++
            continue
        }

        if ($CacheInvalidos.Contains($endereco)) {
            $Estatisticas.CacheInvalidos++
            return [PSCustomObject]@{
                Valido = $false
                Motivo = "Destinatário interno não encontrado no catálogo do Outlook"
            }
        }

        $Estatisticas.ConsultasOutlook++
        $existe = Test-EnderecoNoCatalogoOutlook `
            -Namespace $Namespace `
            -Endereco $endereco

        if ($existe) {
            [void]$CacheValidos.Add($endereco)
            continue
        }

        [void]$CacheInvalidos.Add($endereco)
        return [PSCustomObject]@{
            Valido = $false
            Motivo = "Destinatário interno não encontrado no catálogo do Outlook"
        }
    }

    return [PSCustomObject]@{
        Valido = $true
        Motivo = "Destinatário interno encontrado no catálogo"
    }
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
$outlook = $null
$namespace = $null

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

    if ([string]::IsNullOrWhiteSpace($DiretorioCache)) {
        $DiretorioCache = Join-Path `
            -Path $diretorioResolvido `
            -ChildPath "cache-outlook"
    }

    if (-not (Test-Path -LiteralPath $DiretorioCache)) {
        New-Item `
            -Path $DiretorioCache `
            -ItemType Directory `
            -Force | Out-Null
    }

    $diretorioCacheResolvido = (Resolve-Path -LiteralPath $DiretorioCache).Path
    $dataCache = (Get-Date).ToString("yyyy-MM-dd")
    $arquivoCacheValidos = Join-Path `
        -Path $diretorioCacheResolvido `
        -ChildPath "Destinatarios-Validos-CatalogoExato-$dataCache.txt"
    $arquivoCacheInvalidos = Join-Path `
        -Path $diretorioCacheResolvido `
        -ChildPath "Destinatarios-Invalidos-CatalogoExato-$dataCache.txt"
    $cacheValidos = Read-CacheEnderecos -Caminho $arquivoCacheValidos
    $cacheInvalidos = Read-CacheEnderecos -Caminho $arquivoCacheInvalidos
    $dominiosConfigurados = Get-DominiosInternosConfigurados `
        -Valor $DominiosInternos
    $estatisticasCatalogo = @{
        ConsultasOutlook = 0
        CacheValidos = 0
        CacheInvalidos = 0
    }
    $nomeBase = [IO.Path]::GetFileNameWithoutExtension($caminhoEntrada)
    $horaArquivo = (Get-Date).ToString("HHmmss")
    $arquivoSaida = Join-Path `
        -Path $diretorioResolvido `
        -ChildPath "$nomeBase-Potencialmente-Validos-Catalogo-$horaArquivo.xlsx"

    Write-Host "Lendo a planilha de quarentena..." -ForegroundColor Cyan

    $outlook = New-Object -ComObject Outlook.Application
    $namespace = $outlook.GetNamespace("MAPI")
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
            $classificacao = Test-DestinatariosNoCatalogo `
                -Registro $registro `
                -Namespace $namespace `
                -Dominios $dominiosConfigurados `
                -CacheValidos $cacheValidos `
                -CacheInvalidos $cacheInvalidos `
                -Estatisticas $estatisticasCatalogo
        }

        if ($classificacao.Valido) {
            $registrosValidos.Add($registro)
            continue
        }

        if (-not $motivosDescarte.ContainsKey($classificacao.Motivo)) {
            $motivosDescarte[$classificacao.Motivo] = 0
        }

        $motivosDescarte[$classificacao.Motivo]++
    }

    Save-CacheEnderecos `
        -Caminho $arquivoCacheValidos `
        -Enderecos $cacheValidos
    Save-CacheEnderecos `
        -Caminho $arquivoCacheInvalidos `
        -Enderecos $cacheInvalidos

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
    Write-Host "Consultas ao catálogo do Outlook: $($estatisticasCatalogo.ConsultasOutlook)"
    Write-Host "Resultados obtidos do cache: $($estatisticasCatalogo.CacheValidos + $estatisticasCatalogo.CacheInvalidos)"

    foreach ($motivo in ($motivosDescarte.Keys | Sort-Object)) {
        Write-Host "  - $motivo`: $($motivosDescarte[$motivo])"
    }

    Write-Host "Arquivo criado: $arquivoSaida"
    Write-Host "Cache de existentes: $arquivoCacheValidos"
    Write-Host "Cache de inexistentes: $arquivoCacheInvalidos"
}
catch {
    Write-Error @"
Não foi possível validar a planilha de quarentena.

Erro: $($_.Exception.Message)

Confirme que:
1. O arquivo de entrada é um .xlsx gerado pelo exportador da quarentena.
2. O arquivo possui as colunas Para, Date, From, Subject, Web Actions e Email Actions.
3. O Microsoft Excel está instalado.
4. O Outlook clássico está instalado, configurado e autenticado.
5. O arquivo de entrada não está corrompido ou protegido por senha.
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
        $excel,
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
