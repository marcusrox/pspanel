#requires -Version 5.1

<#
.SYNOPSIS
Classifica mensagens exportadas da quarentena e gera uma planilha auditável.

.DESCRIPTION
Mantém na aba Quarentena as mensagens potencialmente válidas e as que exigem
revisão manual. Mensagens que atingem o limite de descarte ficam apenas na aba
Auditoria, com pontuação, motivos, assunto normalizado e dados da campanha.

A análise usa somente as seis colunas do exportador atual. A existência de
destinatários internos continua sendo validada exatamente no catálogo do
Outlook, com caches separados de endereços existentes e inexistentes.

.EXAMPLE
.\Filtrar-Emails-Potencialmente-Validos-Quarentena-v3.ps1 `
    -ArquivoEntrada "C:\temp\quarentena\Quarentena-Emails.xlsx"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ArquivoEntrada,

    [string]$DiretorioSaida = "",

    [string]$DiretorioCache = "",

    [string]$DominiosInternos = "desenbahia.ba.gov.br",

    [ValidateRange(1, 1000)]
    [int]$PontuacaoRevisao = 40,

    [ValidateRange(1, 1000)]
    [int]$PontuacaoDescarte = 80,

    [ValidateRange(2, 1000)]
    [int]$MinimoDestinatariosCampanha = 3
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

        if (
            $categoria -ne [Globalization.UnicodeCategory]::NonSpacingMark -and
            $categoria -ne [Globalization.UnicodeCategory]::Format
        ) {
            [void]$semAcentos.Append($caractere)
        }
    }

    return (($semAcentos.ToString() -replace "\s+", " ").Trim().ToLowerInvariant())
}

function ConvertTo-AssuntoCanonico {
    param(
        [AllowEmptyString()]
        [string]$Assunto
    )

    $canonico = ConvertTo-TextoComparavel -Texto $Assunto

    if ([string]::IsNullOrWhiteSpace($canonico)) {
        return ""
    }

    $canonico = $canonico -replace `
        "(?i)[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}", `
        "<email>"
    $canonico = $canonico -replace "\bfllename\b", "filename"
    $canonico = $canonico -replace "\b\d+(?:[./:-]\d+)+\b", "<numero>"
    $canonico = $canonico -replace "\b\d+\b", "<numero>"
    $canonico = $canonico -replace "(?:\s*<numero>\s*)+", " <numero> "
    $canonico = $canonico -replace "\s+", " "

    return $canonico.Trim()
}

function Get-DominioEndereco {
    param(
        [AllowEmptyString()]
        [string]$Endereco
    )

    $enderecos = @(Get-EnderecosEmail -Texto $Endereco)

    if ($enderecos.Count -eq 0) {
        return ""
    }

    return $enderecos[0].Split("@")[1].ToLowerInvariant()
}

function Test-DominioIgualOuSubdominio {
    param(
        [AllowEmptyString()]
        [string]$Dominio,

        [Parameter(Mandatory = $true)]
        [string[]]$DominiosPermitidos
    )

    foreach ($permitido in $DominiosPermitidos) {
        if (
            $Dominio -ieq $permitido -or
            $Dominio.EndsWith(".$permitido", [StringComparison]::OrdinalIgnoreCase)
        ) {
            return $true
        }
    }

    return $false
}

function Get-IncompatibilidadeMarcaDominio {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AssuntoComparavel,

        [AllowEmptyString()]
        [string]$DominioRemetente
    )

    $marcas = @(
        [PSCustomObject]@{
            Nome = "Itaú"
            Padrao = "\bitau\b"
            Dominios = @("itau.com.br", "itau-unibanco.com.br")
        },
        [PSCustomObject]@{
            Nome = "Banco do Brasil"
            Padrao = "\bbanco do brasil\b|\bbb pj\b|\bchave j\b"
            Dominios = @("bb.com.br")
        },
        [PSCustomObject]@{
            Nome = "Gov.br"
            Padrao = "(?<![a-z0-9.-])gov[.]?br(?![a-z0-9.-])"
            Dominios = @("gov.br")
        },
        [PSCustomObject]@{
            Nome = "TikTok"
            Padrao = "\btiktok\b"
            Dominios = @("tiktok.com")
        }
    )

    foreach ($marca in $marcas) {
        if (
            $AssuntoComparavel -match $marca.Padrao -and
            -not (Test-DominioIgualOuSubdominio `
                -Dominio $DominioRemetente `
                -DominiosPermitidos $marca.Dominios)
        ) {
            return $marca.Nome
        }
    }

    return ""
}

function Get-ChaveCampanha {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro
    )

    $dominio = Get-DominioEndereco -Endereco ([string]$Registro.From)

    if ([string]::IsNullOrWhiteSpace($dominio)) {
        $dominio = "(sem dominio)"
    }

    $assuntoCanonico = ConvertTo-AssuntoCanonico `
        -Assunto ([string]$Registro.Subject)

    return "$dominio|$assuntoCanonico"
}

function Get-EstatisticasCampanhas {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Registros
    )

    $campanhas = @{}

    foreach ($registro in $Registros) {
        $chave = Get-ChaveCampanha -Registro $registro

        if (-not $campanhas.ContainsKey($chave)) {
            $campanhas[$chave] = [PSCustomObject]@{
                Mensagens = 0
                Destinatarios = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
            }
        }

        $campanha = $campanhas[$chave]
        $campanha.Mensagens++

        foreach ($destinatario in @(
            Get-DestinatariosRegistro `
                -Para ([string]$registro.Para) `
                -WebActions ([string]$registro.WebActions)
        )) {
            [void]$campanha.Destinatarios.Add($destinatario)
        }
    }

    return $campanhas
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

function Get-AvaliacaoRisco {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro,

        [Parameter(Mandatory = $true)]
        [object]$Campanha,

        [Parameter(Mandatory = $true)]
        [int]$MinimoDestinatarios
    )

    $assunto = ConvertTo-TextoComparavel -Texto ([string]$Registro.Subject)
    $assuntoCanonico = ConvertTo-AssuntoCanonico `
        -Assunto ([string]$Registro.Subject)
    $remetenteComparavel = ConvertTo-TextoComparavel `
        -Texto ([string]$Registro.From)
    $textoMarca = "$assuntoCanonico $remetenteComparavel"
    $remetentes = @(Get-EnderecosEmail -Texto ([string]$Registro.From))
    $destinatarios = @(
        Get-DestinatariosRegistro `
            -Para ([string]$Registro.Para) `
            -WebActions ([string]$Registro.WebActions)
    )
    $dominioRemetente = Get-DominioEndereco `
        -Endereco ([string]$Registro.From)
    $pontuacao = 0
    $motivos = [Collections.Generic.List[string]]::new()

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
            $pontuacao += 100
            $motivos.Add("Resposta automática de erro de entrega (+100)")
            break
        }
    }

    if ($assunto -match "^you got recorded!?[.]?$" ) {
        $pontuacao += 100
        $motivos.Add("Assunto de golpe conhecido: YOU GOT RECORDED! (+100)")
    }

    if ($remetentes.Count -eq 0) {
        $pontuacao += 80
        $motivos.Add("Remetente sem endereço de e-mail válido (+80)")
    }

    foreach ($remetente in $remetentes) {
        $nomeCaixa = $remetente.Split("@")[0]

        if ($nomeCaixa -in @("mailer-daemon", "mail-daemon", "postmaster")) {
            $pontuacao += 100
            $motivos.Add("Remetente automático do sistema de e-mail (+100)")
            break
        }

        if ($destinatarios -contains $remetente) {
            $pontuacao += 80
            $motivos.Add("Remetente e destinatário possuem o mesmo endereço (+80)")
            break
        }
    }

    $marcaIncompativel = Get-IncompatibilidadeMarcaDominio `
        -AssuntoComparavel $textoMarca `
        -DominioRemetente $dominioRemetente

    if (-not [string]::IsNullOrWhiteSpace($marcaIncompativel)) {
        $pontuacao += 40
        $motivos.Add(
            "Marca $marcaIncompativel incompatível com o domínio do remetente (+40)"
        )

        if ($assunto -match "\b(chave j|bb pj|itau uniclass)\b") {
            $pontuacao += 30
            $motivos.Add("Imitação de serviço bancário sensível (+30)")
        }
    }

    if (
        $Campanha.Destinatarios.Count -ge $MinimoDestinatarios -and
        -not [string]::IsNullOrWhiteSpace($assuntoCanonico)
    ) {
        $pontuacao += 35
        $motivos.Add(
            "Campanha para $($Campanha.Destinatarios.Count) destinatários com assunto normalizado equivalente (+35)"
        )
    }

    $assuntoContemDestinatario = $false

    foreach ($destinatario in $destinatarios) {
        if (
            -not [string]::IsNullOrWhiteSpace($destinatario) -and
            ([string]$Registro.Subject).IndexOf(
                $destinatario,
                [StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        ) {
            $assuntoContemDestinatario = $true
            break
        }
    }

    if ($assuntoContemDestinatario) {
        $pontuacao += 15
        $motivos.Add("Assunto personalizado com o endereço do destinatário (+15)")
    }

    if (
        $assunto -match `
            "\b(senha|password|login|credencial|acesso|validar|verificar conta|chave j)\b"
    ) {
        $pontuacao += 15
        $motivos.Add("Termos relacionados a credenciais ou acesso (+15)")
    }

    if (
        $assunto -match `
            "\b(fatura|pagamento|payment|invoice|boleto|pix|precatorio|liquidez)\b"
    ) {
        $pontuacao += 15
        $motivos.Add("Termos financeiros ou de pagamento (+15)")
    }

    if (
        $assunto -match `
            "\b(acao necessaria|urgente|imediata|imediato|ultima notificacao|bloqueio|suspensao|irregularidade|pendente)\b"
    ) {
        $pontuacao += 15
        $motivos.Add("Linguagem de urgência, ameaça ou pendência (+15)")
    }

    if (
        $assunto -match `
            "clique.+validar.+e-?mail|verify.+account|confirme.+senha"
    ) {
        $pontuacao += 35
        $motivos.Add("Chamada típica de captura de credenciais (+35)")
    }

    if ($assunto -match "payment[ -]?instruction") {
        $pontuacao += 35
        $motivos.Add("Instrução de pagamento em solicitação de assinatura (+35)")
    }

    if ($assunto -match "\bkindly sign\b") {
        $pontuacao += 25
        $motivos.Add("Solicitação de assinatura com expressão suspeita (+25)")
    }

    if ($assunto -match "sign here.+docusign.+document.+pdf") {
        $pontuacao += 30
        $motivos.Add("Modelo suspeito de assinatura DocuSign com documento genérico (+30)")
    }

    if ($assuntoCanonico -match "contact\s*-\s*<email>") {
        $pontuacao += 20
        $motivos.Add("Modelo inclui destinatário após marcador 'contact' (+20)")
    }

    if (
        $assunto -match `
            "\b(oferta|promocao|marketing|newsletter|liquidez imediata|e-commerce|vendas b2b)\b"
    ) {
        $pontuacao += 10
        $motivos.Add("Conteúdo comercial ou promocional não solicitado (+10)")
    }

    if ($assunto -match "[\u4E00-\u9FFF\u3040-\u30FF]") {
        $pontuacao += 30
        $motivos.Add("Assunto em alfabeto incomum para o contexto corporativo (+30)")
    }

    if (-not [string]::IsNullOrWhiteSpace($dominioRemetente)) {
        if (
            $dominioRemetente -match `
                "(?:^|[.])(system-mailing|alert-center|billing-mailing|newsletter-sys|noreply-mailing|[a-z]+\d{3,}[a-z0-9]*)(?:[.]|$)"
        ) {
            $pontuacao += 10
            $motivos.Add("Estrutura incomum do domínio remetente (+10)")
        }
    }

    return [PSCustomObject]@{
        Pontuacao = $pontuacao
        Motivos = @($motivos)
        AssuntoCanonico = $assuntoCanonico
        DominioRemetente = $dominioRemetente
        QuantidadeCampanha = $Campanha.Mensagens
        DestinatariosCampanha = $Campanha.Destinatarios.Count
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
$worksheetAuditoria = $null
$headerRange = $null
$headerRangeAuditoria = $null
$dataRange = $null
$dataRangeAuditoria = $null
$usedRangeSaida = $null
$usedRangeAuditoria = $null
$listObject = $null
$listObjectAuditoria = $null
$hyperlinks = $null
$outlook = $null
$namespace = $null

try {
    if ($PontuacaoRevisao -ge $PontuacaoDescarte) {
        throw "A pontuação de revisão deve ser menor que a pontuação de descarte."
    }

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
        -ChildPath "$nomeBase-Potencialmente-Validos-v3-$horaArquivo.xlsx"

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

    $registros = [Collections.Generic.List[object]]::new()

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

        $registro = [PSCustomObject]@{
            Para = [string]$valores[0]
            Date = $valores[1]
            From = [string]$valores[2]
            Subject = [string]$valores[3]
            WebActions = [string]$valores[4]
            EmailActions = [string]$valores[5]
            Valores = $valores
            LinhaOrigem = $linha
        }
        $registros.Add($registro)
    }

    $totalRegistros = $registros.Count
    $campanhas = Get-EstatisticasCampanhas -Registros @($registros)
    $registrosValidos = [Collections.Generic.List[object]]::new()
    $auditoria = [Collections.Generic.List[object]]::new()
    $motivosDescarte = @{}
    $quantidadePotencialmenteValidas = 0
    $quantidadeRevisao = 0
    $quantidadeInvalidas = 0

    foreach ($registro in $registros) {
        $chaveCampanha = Get-ChaveCampanha -Registro $registro
        $avaliacao = Get-AvaliacaoRisco `
            -Registro $registro `
            -Campanha $campanhas[$chaveCampanha] `
            -MinimoDestinatarios $MinimoDestinatariosCampanha
        $pontuacao = $avaliacao.Pontuacao
        $motivos = [Collections.Generic.List[string]]::new()

        foreach ($motivo in $avaliacao.Motivos) {
            $motivos.Add($motivo)
        }

        $resultadoCatalogo = "Não consultado: mensagem já atingiu o limite de descarte"

        if ($pontuacao -lt $PontuacaoDescarte) {
            $validacaoCatalogo = Test-DestinatariosNoCatalogo `
                -Registro $registro `
                -Namespace $namespace `
                -Dominios $dominiosConfigurados `
                -CacheValidos $cacheValidos `
                -CacheInvalidos $cacheInvalidos `
                -Estatisticas $estatisticasCatalogo
            $resultadoCatalogo = $validacaoCatalogo.Motivo

            if (-not $validacaoCatalogo.Valido) {
                $pontuacao += 100
                $motivos.Add("$($validacaoCatalogo.Motivo) (+100)")
            }
        }

        if ($motivos.Count -eq 0) {
            $motivos.Add("Nenhum indicador de risco identificado")
        }

        if ($pontuacao -ge $PontuacaoDescarte) {
            $classificacaoFinal = "Inválida"
            $quantidadeInvalidas++

            foreach ($motivo in $motivos) {
                if (-not $motivosDescarte.ContainsKey($motivo)) {
                    $motivosDescarte[$motivo] = 0
                }

                $motivosDescarte[$motivo]++
            }
        }
        elseif ($pontuacao -ge $PontuacaoRevisao) {
            $classificacaoFinal = "Revisão manual"
            $quantidadeRevisao++
            $registrosValidos.Add($registro)
        }
        else {
            $classificacaoFinal = "Potencialmente válida"
            $quantidadePotencialmenteValidas++
            $registrosValidos.Add($registro)
        }

        $auditoria.Add([PSCustomObject]@{
            Registro = $registro
            Pontuacao = $pontuacao
            Classificacao = $classificacaoFinal
            Motivos = ($motivos -join "; ")
            AssuntoCanonico = $avaliacao.AssuntoCanonico
            DominioRemetente = $avaliacao.DominioRemetente
            QuantidadeCampanha = $avaliacao.QuantidadeCampanha
            DestinatariosCampanha = $avaliacao.DestinatariosCampanha
            ResultadoCatalogo = $resultadoCatalogo
        })
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

    $worksheetAuditoria = $workbookSaida.Worksheets.Add()
    $worksheetAuditoria.Name = "Auditoria"
    $cabecalhosAuditoria = @(
        "Para",
        "Date",
        "From",
        "Subject",
        "Web Actions",
        "Email Actions",
        "Pontuação",
        "Classificação",
        "Motivos",
        "Assunto Normalizado",
        "Domínio do Remetente",
        "Mensagens na Campanha",
        "Destinatários na Campanha",
        "Validação no Catálogo"
    )
    $headerRangeAuditoria = $worksheetAuditoria.Range("A1", "N1")
    $matrizCabecalhosAuditoria = New-Object "object[,]" 1, 14

    for ($coluna = 0; $coluna -lt 14; $coluna++) {
        $matrizCabecalhosAuditoria[0, $coluna] = `
            $cabecalhosAuditoria[$coluna]
    }

    $headerRangeAuditoria.Value2 = $matrizCabecalhosAuditoria

    if ($auditoria.Count -gt 0) {
        $matrizAuditoria = New-Object "object[,]" $auditoria.Count, 14

        for ($linha = 0; $linha -lt $auditoria.Count; $linha++) {
            $itemAuditoria = $auditoria[$linha]

            for ($coluna = 0; $coluna -lt 6; $coluna++) {
                $matrizAuditoria[$linha, $coluna] = `
                    $itemAuditoria.Registro.Valores[$coluna]
            }

            $matrizAuditoria[$linha, 6] = $itemAuditoria.Pontuacao
            $matrizAuditoria[$linha, 7] = $itemAuditoria.Classificacao
            $matrizAuditoria[$linha, 8] = $itemAuditoria.Motivos
            $matrizAuditoria[$linha, 9] = $itemAuditoria.AssuntoCanonico
            $matrizAuditoria[$linha, 10] = $itemAuditoria.DominioRemetente
            $matrizAuditoria[$linha, 11] = `
                $itemAuditoria.QuantidadeCampanha
            $matrizAuditoria[$linha, 12] = `
                $itemAuditoria.DestinatariosCampanha
            $matrizAuditoria[$linha, 13] = `
                $itemAuditoria.ResultadoCatalogo
        }

        $ultimaLinhaAuditoria = $auditoria.Count + 1
        $dataRangeAuditoria = $worksheetAuditoria.Range(
            "A2",
            "N$ultimaLinhaAuditoria"
        )
        $dataRangeAuditoria.Value2 = $matrizAuditoria
        $dataRangeAuditoria.VerticalAlignment = $xlTop
        $dataRangeAuditoria.WrapText = $true
        $worksheetAuditoria.Range(
            "B2",
            "B$ultimaLinhaAuditoria"
        ).NumberFormat = "dd/mm/yyyy hh:mm:ss"
        $worksheetAuditoria.Range(
            "G2",
            "G$ultimaLinhaAuditoria"
        ).NumberFormat = "0"
        $usedRangeAuditoria = $worksheetAuditoria.Range(
            "A1",
            "N$ultimaLinhaAuditoria"
        )
        $listObjectAuditoria = $worksheetAuditoria.ListObjects.Add(
            $xlSrcRange,
            $usedRangeAuditoria,
            $null,
            $xlYes
        )
        $listObjectAuditoria.Name = "TabelaAuditoriaQuarentenaV3"
        $listObjectAuditoria.TableStyle = "TableStyleMedium2"

        for ($linha = 0; $linha -lt $auditoria.Count; $linha++) {
            $linhaExcel = $linha + 2
            $celulaClassificacao = $worksheetAuditoria.Range(
                "H$linhaExcel"
            )

            switch ($auditoria[$linha].Classificacao) {
                "Inválida" {
                    $celulaClassificacao.Interior.Color = 13421812
                }
                "Revisão manual" {
                    $celulaClassificacao.Interior.Color = 13431551
                }
                default {
                    $celulaClassificacao.Interior.Color = 13888217
                }
            }

            [void][Runtime.InteropServices.Marshal]::ReleaseComObject(
                $celulaClassificacao
            )
        }
    }
    else {
        $headerRangeAuditoria.Interior.Color = 12879428
        $headerRangeAuditoria.Font.Color = 16777215
        $headerRangeAuditoria.Font.Bold = $true
        [void]$headerRangeAuditoria.AutoFilter()
    }

    $headerRangeAuditoria.HorizontalAlignment = $xlCenter
    $headerRangeAuditoria.VerticalAlignment = $xlCenter
    $worksheetAuditoria.Columns.Item("A").ColumnWidth = 32
    $worksheetAuditoria.Columns.Item("B").ColumnWidth = 22
    $worksheetAuditoria.Columns.Item("C").ColumnWidth = 36
    $worksheetAuditoria.Columns.Item("D").ColumnWidth = 45
    $worksheetAuditoria.Columns.Item("E").ColumnWidth = 18
    $worksheetAuditoria.Columns.Item("F").ColumnWidth = 18
    $worksheetAuditoria.Columns.Item("G").ColumnWidth = 12
    $worksheetAuditoria.Columns.Item("H").ColumnWidth = 22
    $worksheetAuditoria.Columns.Item("I").ColumnWidth = 70
    $worksheetAuditoria.Columns.Item("J").ColumnWidth = 60
    $worksheetAuditoria.Columns.Item("K").ColumnWidth = 30
    $worksheetAuditoria.Columns.Item("L").ColumnWidth = 20
    $worksheetAuditoria.Columns.Item("M").ColumnWidth = 22
    $worksheetAuditoria.Columns.Item("N").ColumnWidth = 48
    $worksheetAuditoria.Rows.Item(1).RowHeight = 24
    $worksheetAuditoria.Activate()
    $excel.ActiveWindow.SplitRow = 1
    $excel.ActiveWindow.FreezePanes = $true

    $worksheetSaida.Activate()
    $excel.ActiveWindow.SplitRow = 1
    $excel.ActiveWindow.FreezePanes = $true

    $workbookSaida.SaveAs($arquivoSaida, $xlOpenXmlWorkbook)
    $workbookSaida.Close($false)
    $excel.Quit()

    Write-Host ""
    Write-Host "Validação concluída." -ForegroundColor Green
    Write-Host "Registros analisados: $totalRegistros"
    Write-Host "Potencialmente válidos: $quantidadePotencialmenteValidas"
    Write-Host "Para revisão manual: $quantidadeRevisao"
    Write-Host "Descartados como inválidos: $quantidadeInvalidas"
    Write-Host "Linhas mantidas na aba Quarentena: $($registrosValidos.Count)"
    Write-Host "Limite para revisão: $PontuacaoRevisao pontos"
    Write-Host "Limite para descarte: $PontuacaoDescarte pontos"
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
        $listObjectAuditoria,
        $listObject,
        $usedRangeAuditoria,
        $usedRangeSaida,
        $dataRangeAuditoria,
        $dataRange,
        $headerRangeAuditoria,
        $headerRange,
        $worksheetAuditoria,
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
