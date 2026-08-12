#requires -Version 5.1

<#
.SYNOPSIS
Classifica mensagens de quarentena e gera uma planilha com auditoria de risco.

.DESCRIPTION
Analisa uma exportação bruta da quarentena, atribui pontuação de risco às
mensagens e valida destinatários internos no catálogo do Outlook clássico.

O arquivo gerado contém a aba Quarentena, com as mensagens potencialmente
válidas e as que exigem revisão manual, e a aba Auditoria, com todos os
registros, classificações, pontuações, motivos e dados históricos das
campanhas. Mensagens que atingem o limite de descarte ficam somente na aba
Auditoria.

A análise usa o arquivo alvo e exportações brutas anteriores do mesmo
diretório para identificar padrões históricos. Somente as linhas do arquivo
alvo são classificadas e validadas no catálogo. Consultas ao Outlook são
armazenadas em arquivos de cache diários para evitar validações repetidas.

O script requer Windows PowerShell 5.1, Microsoft Excel e Outlook clássico
instalados. O Outlook deve estar configurado e autenticado para consultar o
catálogo corporativo.

.PARAMETER ArquivoEntrada
Caminho do arquivo XLSX bruto que será classificado. O nome deve seguir o
padrão Quarentena-Emails-AAAA-MM-DD_AAAA-MM-DD_HHMMSS.xlsx, e a primeira
planilha deve conter exatamente as colunas Para, Date, From, Subject,
Web Actions e Email Actions, iniciando na célula A1.

.PARAMETER DiretorioSaida
Diretório no qual a planilha classificada será criada. Quando omitido ou
vazio, utiliza o diretório do arquivo de entrada. O diretório é criado
automaticamente quando não existe.

.PARAMETER DiretorioCache
Diretório dos arquivos diários de cache dos destinatários encontrados e não
encontrados no catálogo do Outlook. Quando omitido ou vazio, utiliza a pasta
cache-outlook dentro do diretório de saída. A pasta é criada automaticamente
quando não existe.

.PARAMETER DominiosInternos
Lista de domínios cujos destinatários devem ser validados no catálogo do
Outlook. Aceita valores separados por vírgula, ponto e vírgula ou espaços.
O valor padrão é "desenbahia.ba.gov.br".

.PARAMETER PontuacaoRevisao
Pontuação mínima para classificar uma mensagem como "Revisão manual". Deve
ser menor que PontuacaoDescarte. O valor padrão é 50.

.PARAMETER PontuacaoDescarte
Pontuação mínima para classificar uma mensagem como "Inválida" e removê-la
da aba Quarentena. O valor padrão é 60.

.PARAMETER MinimoDestinatariosCampanha
Quantidade mínima de destinatários distintos usada pelas regras de detecção
de campanha. O valor padrão é 5.

.PARAMETER QuantidadeArquivosHistorico
Quantidade máxima de exportações brutas usadas na análise histórica,
incluindo o arquivo de entrada. Os arquivos anteriores são selecionados no
mesmo diretório, do mais recente para o mais antigo. O valor padrão é 5.

.EXAMPLE
.\Filtrar-Emails-Potencialmente-Validos-Quarentena-v4.ps1 `
    -ArquivoEntrada "$PSScriptRoot\Quarentena\Quarentena-Emails-2026-08-11_2026-08-11_114341.xlsx"

Classifica o arquivo informado usando os limites, domínios e diretórios
padrão. A saída é criada no mesmo diretório do arquivo de entrada.

.EXAMPLE
.\Filtrar-Emails-Potencialmente-Validos-Quarentena-v4.ps1 `
    -ArquivoEntrada "$PSScriptRoot\Quarentena\Quarentena-Emails-2026-08-11_2026-08-11_114341.xlsx" `
    -DiretorioSaida "D:\Relatorios\Quarentena" `
    -QuantidadeArquivosHistorico 10

Classifica o arquivo usando até dez exportações no contexto histórico e salva
o resultado em um diretório personalizado.

.EXAMPLE
.\Filtrar-Emails-Potencialmente-Validos-Quarentena-v4.ps1 `
    -ArquivoEntrada "$PSScriptRoot\Quarentena\Quarentena-Emails-2026-08-11_2026-08-11_114341.xlsx" `
    -DominiosInternos "empresa.com.br;subsidiaria.com.br" `
    -PontuacaoRevisao 40 `
    -PontuacaoDescarte 70 `
    -MinimoDestinatariosCampanha 8

Executa a classificação com domínios internos, limites de pontuação e
quantidade mínima de destinatários personalizados.

.INPUTS
Nenhum. O script não aceita objetos pela entrada do pipeline.

.OUTPUTS
Nenhum objeto é enviado ao pipeline. O script cria uma planilha XLSX com as
abas Quarentena e Auditoria, atualiza os arquivos de cache e exibe um resumo
da classificação no console.

.NOTES
Execute o script com o mesmo usuário do Windows que utiliza o perfil do
Outlook. O arquivo de entrada não pode estar corrompido ou protegido por
senha. A pontuação de revisão deve ser menor que a pontuação de descarte.
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
    [int]$PontuacaoRevisao = 60,

    [ValidateRange(1, 1000)]
    [int]$PontuacaoDescarte = 60,

    [ValidateRange(2, 1000)]
    [int]$MinimoDestinatariosCampanha = 5,

    [ValidateRange(1, 30)]
    [int]$QuantidadeArquivosHistorico = 5
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
$cabecalhosEsperados = @(
    "Para",
    "Date",
    "From",
    "Subject",
    "Web Actions",
    "Email Actions"
)

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
                Arquivos = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                Datas = [Collections.Generic.HashSet[string]]::new(
                    [StringComparer]::OrdinalIgnoreCase
                )
                PrimeiraOcorrencia = $null
                UltimaOcorrencia = $null
            }
        }

        $campanha = $campanhas[$chave]
        $campanha.Mensagens++
        [void]$campanha.Arquivos.Add([string]$registro.ArquivoOrigem)
        $dataOcorrencia = Get-DataOcorrenciaRegistro -Registro $registro
        [void]$campanha.Datas.Add(
            $dataOcorrencia.ToString("yyyy-MM-dd")
        )

        if (
            $null -eq $campanha.PrimeiraOcorrencia -or
            $dataOcorrencia -lt $campanha.PrimeiraOcorrencia
        ) {
            $campanha.PrimeiraOcorrencia = $dataOcorrencia
        }

        if (
            $null -eq $campanha.UltimaOcorrencia -or
            $dataOcorrencia -gt $campanha.UltimaOcorrencia
        ) {
            $campanha.UltimaOcorrencia = $dataOcorrencia
        }

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
    $pontuacaoHistorica = 0
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
        $pontuacaoHistorica += 35
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
        $pontuacao += 25
        $motivos.Add("Linguagem de urgência, ameaça ou pendência (+25)")
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
        $pontuacao += 50
        $motivos.Add("Assunto em alfabeto incomum para o contexto corporativo (+50)")
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

    if ($Campanha.Arquivos.Count -ge 3) {
        $pontuacao += 15
        $pontuacaoHistorica += 15
        $motivos.Add(
            "Padrão presente em $($Campanha.Arquivos.Count) arquivos distintos (+15)"
        )
    }

    if ($Campanha.Datas.Count -ge 3) {
        $pontuacao += 15
        $pontuacaoHistorica += 15
        $motivos.Add(
            "Padrão recorrente em $($Campanha.Datas.Count) datas distintas (+15)"
        )
    }

    if ($Campanha.Destinatarios.Count -ge 10) {
        $pontuacao += 15
        $pontuacaoHistorica += 15
        $motivos.Add(
            "Padrão histórico alcançou $($Campanha.Destinatarios.Count) destinatários distintos (+15)"
        )
    }

    $pontuacaoNaoHistorica = $pontuacao - $pontuacaoHistorica

    if (
        (
            $Campanha.Arquivos.Count -ge 2 -or
            $Campanha.Datas.Count -ge 2
        ) -and
        $pontuacaoNaoHistorica -ge 40
    ) {
        $pontuacao += 20
        $pontuacaoHistorica += 20
        $motivos.Add(
            "Padrão recorrente combinado com outros sinais de risco (+20)"
        )
    }

    return [PSCustomObject]@{
        Pontuacao = $pontuacao
        Motivos = @($motivos)
        AssuntoCanonico = $assuntoCanonico
        DominioRemetente = $dominioRemetente
        QuantidadeCampanha = $Campanha.Mensagens
        DestinatariosCampanha = $Campanha.Destinatarios.Count
        ArquivosCampanha = $Campanha.Arquivos.Count
        DatasCampanha = $Campanha.Datas.Count
        PrimeiraOcorrencia = $Campanha.PrimeiraOcorrencia
        UltimaOcorrencia = $Campanha.UltimaOcorrencia
        PontuacaoHistorica = $pontuacaoHistorica
    }
}

function Get-InformacaoArquivoQuarentena {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caminho
    )

    $caminhoResolvido = (Resolve-Path -LiteralPath $Caminho).Path
    $nome = [IO.Path]::GetFileName($caminhoResolvido)
    $padrao = "^Quarentena-Emails-(?<dataMensagens>\d{4}-\d{2}-\d{2})_(?<dataExecucao>\d{4}-\d{2}-\d{2})_(?<horaExecucao>\d{6})[.]xlsx$"

    if ($nome -notmatch $padrao) {
        return $null
    }

    $dataMensagens = [datetime]::MinValue
    $dataExecucao = [datetime]::MinValue
    $cultura = [Globalization.CultureInfo]::InvariantCulture
    $estilos = [Globalization.DateTimeStyles]::None
    $valorDataExecucao = "$($Matches.dataExecucao)_$($Matches.horaExecucao)"

    if (
        -not [datetime]::TryParseExact(
            $Matches.dataMensagens,
            "yyyy-MM-dd",
            $cultura,
            $estilos,
            [ref]$dataMensagens
        ) -or
        -not [datetime]::TryParseExact(
            $valorDataExecucao,
            "yyyy-MM-dd_HHmmss",
            $cultura,
            $estilos,
            [ref]$dataExecucao
        )
    ) {
        return $null
    }

    return [PSCustomObject]@{
        Caminho = $caminhoResolvido
        Nome = $nome
        DataMensagens = $dataMensagens.Date
        DataExecucao = $dataExecucao
    }
}

function Get-ArquivosContextoHistorico {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CaminhoEntrada,

        [Parameter(Mandatory = $true)]
        [int]$Quantidade
    )

    $arquivoAlvo = Get-InformacaoArquivoQuarentena `
        -Caminho $CaminhoEntrada

    if ($null -eq $arquivoAlvo) {
        throw @"
O arquivo de entrada não segue o padrão esperado:
Quarentena-Emails-AAAA-MM-DD_AAAA-MM-DD_HHMMSS.xlsx
"@
    }

    $diretorio = Split-Path -Parent $arquivoAlvo.Caminho
    $candidatos = [Collections.Generic.List[object]]::new()

    foreach ($arquivo in @(
        Get-ChildItem `
            -LiteralPath $diretorio `
            -Filter "*.xlsx" `
            -File
    )) {
        $informacao = Get-InformacaoArquivoQuarentena `
            -Caminho $arquivo.FullName

        if (
            $null -eq $informacao -or
            $informacao.Caminho -ieq $arquivoAlvo.Caminho -or
            $informacao.DataExecucao -gt $arquivoAlvo.DataExecucao
        ) {
            continue
        }

        $candidatos.Add($informacao)
    }

    $selecionados = [Collections.Generic.List[object]]::new()
    $selecionados.Add($arquivoAlvo)

    if ($Quantidade -gt 1) {
        foreach ($candidato in @(
            $candidatos |
                Sort-Object DataExecucao -Descending |
                Select-Object -First ($Quantidade - 1)
        )) {
            $selecionados.Add($candidato)
        }
    }

    return @($selecionados)
}

function Read-RegistrosQuarentenaExcel {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Excel,

        [Parameter(Mandatory = $true)]
        [object]$Arquivo
    )

    $workbookLeitura = $null
    $worksheetLeitura = $null
    $usedRangeLeitura = $null

    try {
        $workbookLeitura = $Excel.Workbooks.Open(
            $Arquivo.Caminho,
            0,
            $true
        )
        $worksheetLeitura = $workbookLeitura.Worksheets.Item(1)
        $usedRangeLeitura = $worksheetLeitura.UsedRange

        if (
            $usedRangeLeitura.Row -ne 1 -or
            $usedRangeLeitura.Column -ne 1
        ) {
            throw "A tabela deve começar na célula A1: $($Arquivo.Nome)"
        }

        if ($usedRangeLeitura.Columns.Count -ne 6) {
            throw "A planilha deve possuir exatamente seis colunas: $($Arquivo.Nome)"
        }

        $valoresEntrada = $usedRangeLeitura.Value2
        $primeiraLinha = $valoresEntrada.GetLowerBound(0)
        $ultimaLinha = $valoresEntrada.GetUpperBound(0)
        $primeiraColuna = $valoresEntrada.GetLowerBound(1)

        for ($indice = 0; $indice -lt $script:cabecalhosEsperados.Count; $indice++) {
            $valorCabecalho = [string]$valoresEntrada[
                $primeiraLinha,
                ($primeiraColuna + $indice)
            ]

            if ($valorCabecalho -cne $script:cabecalhosEsperados[$indice]) {
                throw "Cabeçalho inválido na coluna $($indice + 1) de '$($Arquivo.Nome)': esperado '$($script:cabecalhosEsperados[$indice])'."
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

                if (
                    $null -ne $valores[$coluna] -and
                    [string]$valores[$coluna] -ne ""
                ) {
                    $possuiConteudo = $true
                }
            }

            if (-not $possuiConteudo) {
                continue
            }

            $registros.Add([PSCustomObject]@{
                Para = [string]$valores[0]
                Date = $valores[1]
                From = [string]$valores[2]
                Subject = [string]$valores[3]
                WebActions = [string]$valores[4]
                EmailActions = [string]$valores[5]
                Valores = $valores
                LinhaOrigem = $linha
                ArquivoOrigem = $Arquivo.Nome
                DataArquivo = $Arquivo.DataMensagens
            })
        }

        return [PSCustomObject]@{
            Registros = @($registros)
        }
    }
    finally {
        if ($null -ne $workbookLeitura) {
            try {
                $workbookLeitura.Close($false)
            }
            catch {
                # Ignora erros ao fechar uma planilha usada no histórico.
            }
        }

        foreach ($objeto in @(
            $usedRangeLeitura,
            $worksheetLeitura,
            $workbookLeitura
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

function Get-AssinaturaRegistro {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro
    )

    $cultura = [Globalization.CultureInfo]::InvariantCulture
    $partes = @(
        $Registro.Para,
        [Convert]::ToString($Registro.Date, $cultura),
        $Registro.From,
        $Registro.Subject,
        $Registro.WebActions,
        $Registro.EmailActions
    )

    return (($partes | ForEach-Object { ([string]$_).Trim() }) -join [char]0x1F)
}

function Get-DataOcorrenciaRegistro {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro
    )

    if (
        $Registro.Date -is [double] -or
        $Registro.Date -is [decimal] -or
        $Registro.Date -is [int]
    ) {
        try {
            return [datetime]::FromOADate([double]$Registro.Date)
        }
        catch {
            # Usa a data do arquivo quando o número não for uma data Excel.
        }
    }

    $data = [datetimeoffset]::MinValue

    if (
        [datetimeoffset]::TryParse(
            [string]$Registro.Date,
            [Globalization.CultureInfo]::GetCultureInfo("pt-BR"),
            [Globalization.DateTimeStyles]::AllowWhiteSpaces,
            [ref]$data
        )
    ) {
        return $data.DateTime
    }

    return [datetime]$Registro.DataArquivo
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
        -ChildPath "$nomeBase-Classificados-$horaArquivo.xlsx"

    $arquivosHistorico = @(
        Get-ArquivosContextoHistorico `
            -CaminhoEntrada $caminhoEntrada `
            -Quantidade $QuantidadeArquivosHistorico
    )

    Write-Host "Lendo o arquivo alvo e o histórico..." -ForegroundColor Cyan

    foreach ($arquivoHistorico in $arquivosHistorico) {
        Write-Host "  - $($arquivoHistorico.Nome)"
    }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $registros = [Collections.Generic.List[object]]::new()
    $registrosHistorico = [Collections.Generic.List[object]]::new()
    $assinaturasHistorico = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::Ordinal
    )
    $registrosDuplicadosHistorico = 0

    foreach ($arquivoHistorico in $arquivosHistorico) {
        $leitura = Read-RegistrosQuarentenaExcel `
            -Excel $excel `
            -Arquivo $arquivoHistorico

        if ($arquivoHistorico.Caminho -ieq $caminhoEntrada) {
            foreach ($registroAlvo in $leitura.Registros) {
                $registros.Add($registroAlvo)
            }
        }

        foreach ($registroHistorico in $leitura.Registros) {
            $assinatura = Get-AssinaturaRegistro `
                -Registro $registroHistorico

            if ($assinaturasHistorico.Add($assinatura)) {
                $registrosHistorico.Add($registroHistorico)
            }
            else {
                $registrosDuplicadosHistorico++
            }
        }
    }

    $totalRegistros = $registros.Count
    $campanhas = Get-EstatisticasCampanhas `
        -Registros @($registrosHistorico)

    $outlook = New-Object -ComObject Outlook.Application
    $namespace = $outlook.GetNamespace("MAPI")
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
            ArquivosCampanha = $avaliacao.ArquivosCampanha
            DatasCampanha = $avaliacao.DatasCampanha
            PrimeiraOcorrencia = $avaliacao.PrimeiraOcorrencia
            UltimaOcorrencia = $avaliacao.UltimaOcorrencia
            PontuacaoHistorica = $avaliacao.PontuacaoHistorica
            ResultadoCatalogo = $resultadoCatalogo
        })
    }

    Save-CacheEnderecos `
        -Caminho $arquivoCacheValidos `
        -Enderecos $cacheValidos
    Save-CacheEnderecos `
        -Caminho $arquivoCacheInvalidos `
        -Enderecos $cacheInvalidos

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
        "Arquivos no Histórico",
        "Datas no Histórico",
        "Primeira Ocorrência",
        "Última Ocorrência",
        "Pontuação Histórica",
        "Validação no Catálogo"
    )
    $headerRangeAuditoria = $worksheetAuditoria.Range("A1", "S1")
    $matrizCabecalhosAuditoria = New-Object "object[,]" 1, 19

    for ($coluna = 0; $coluna -lt 19; $coluna++) {
        $matrizCabecalhosAuditoria[0, $coluna] = `
            $cabecalhosAuditoria[$coluna]
    }

    $headerRangeAuditoria.Value2 = $matrizCabecalhosAuditoria

    if ($auditoria.Count -gt 0) {
        $matrizAuditoria = New-Object "object[,]" $auditoria.Count, 19

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
            $matrizAuditoria[$linha, 13] = $itemAuditoria.ArquivosCampanha
            $matrizAuditoria[$linha, 14] = $itemAuditoria.DatasCampanha

            if ($null -ne $itemAuditoria.PrimeiraOcorrencia) {
                $matrizAuditoria[$linha, 15] = `
                    $itemAuditoria.PrimeiraOcorrencia.ToOADate()
            }

            if ($null -ne $itemAuditoria.UltimaOcorrencia) {
                $matrizAuditoria[$linha, 16] = `
                    $itemAuditoria.UltimaOcorrencia.ToOADate()
            }

            $matrizAuditoria[$linha, 17] = `
                $itemAuditoria.PontuacaoHistorica
            $matrizAuditoria[$linha, 18] = `
                $itemAuditoria.ResultadoCatalogo
        }

        $ultimaLinhaAuditoria = $auditoria.Count + 1
        $dataRangeAuditoria = $worksheetAuditoria.Range(
            "A2",
            "S$ultimaLinhaAuditoria"
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
        $worksheetAuditoria.Range(
            "P2",
            "Q$ultimaLinhaAuditoria"
        ).NumberFormat = "dd/mm/yyyy hh:mm:ss"
        $usedRangeAuditoria = $worksheetAuditoria.Range(
            "A1",
            "S$ultimaLinhaAuditoria"
        )
        $listObjectAuditoria = $worksheetAuditoria.ListObjects.Add(
            $xlSrcRange,
            $usedRangeAuditoria,
            $null,
            $xlYes
        )
        $listObjectAuditoria.Name = "TabelaAuditoriaQuarentenaV4"
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
    $worksheetAuditoria.Columns.Item("N").ColumnWidth = 20
    $worksheetAuditoria.Columns.Item("O").ColumnWidth = 18
    $worksheetAuditoria.Columns.Item("P").ColumnWidth = 22
    $worksheetAuditoria.Columns.Item("Q").ColumnWidth = 22
    $worksheetAuditoria.Columns.Item("R").ColumnWidth = 20
    $worksheetAuditoria.Columns.Item("S").ColumnWidth = 48
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
    Write-Host "Arquivos usados no histórico: $($arquivosHistorico.Count)"
    Write-Host "Registros históricos após deduplicação: $($registrosHistorico.Count)"
    Write-Host "Duplicidades históricas ignoradas: $registrosDuplicadosHistorico"
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
1. O arquivo de entrada é um .xlsx bruto gerado pelo exportador da quarentena.
2. O arquivo possui as colunas Para, Date, From, Subject, Web Actions e Email Actions.
3. O Microsoft Excel está instalado.
4. O Outlook clássico está instalado, configurado e autenticado.
5. O arquivo de entrada não está corrompido ou protegido por senha.
6. O nome segue Quarentena-Emails-AAAA-MM-DD_AAAA-MM-DD_HHMMSS.xlsx.
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
