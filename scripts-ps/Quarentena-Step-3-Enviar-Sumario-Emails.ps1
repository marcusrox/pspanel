#requires -Version 5.1

<#
.SYNOPSIS
Envia um sumário classificado das mensagens de quarentena por destinatário.

.DESCRIPTION
Lê a planilha Auditoria de uma exportação produzida pelo classificador e envia
um único e-mail HTML para cada endereço encontrado na coluna Para. O resumo
separa as mensagens nas classificações Potencialmente válida e Inválida.

Registros com outras classificações, como Revisão manual, não são enviados e
são informados como aviso na saída do script.

Quando ArquivoEntrada não é informado, usa o arquivo classificado mais recente
do DiretorioEntrada. Com WhatIf, os grupos são mantidos separados, mas todos
os e-mails são redirecionados ao DestinatarioSimulacao.

.PARAMETER ArquivoEntrada
Caminho opcional do arquivo XLSX a processar.

.PARAMETER DiretorioEntrada
Pasta pesquisada quando ArquivoEntrada não é informado. Por padrão, usa a
subpasta Quarentena do diretório onde este script está localizado.

.PARAMETER FiltroPara
Endereço opcional da coluna Para cujas mensagens devem compor o relatório.
Quando omitido, gera um resumo para cada destinatário encontrado.

.PARAMETER WhatIf
Redireciona os e-mails ao endereço de simulação. Este parâmetro ainda realiza
o envio; ele apenas impede a entrega aos destinatários originais.

.PARAMETER DestinatarioSimulacao
Endereço que recebe os e-mails quando WhatIf é usado.

.PARAMETER NomeRemetente
Nome de exibição associado ao endereço remetente configurado no PS Panel.

.EXAMPLE
.\Quarentena-Step-3-Enviar-Sumario-Emails.ps1

.EXAMPLE
.\Quarentena-Step-3-Enviar-Sumario-Emails.ps1 `
    -ArquivoEntrada "$PSScriptRoot\Quarentena\Quarentena-Emails-2026-08-06_2026-08-06_141718-Classificados-142403.xlsx" `
    -FiltroPara "usuario@desenbahia.ba.gov.br" `
    -WhatIf `
    -DestinatarioSimulacao "msouza@desenbahia.ba.gov.br"

.INPUTS
Nenhum.

.OUTPUTS
Mensagens de progresso e aviso no pipeline de host. Envia e-mails HTML via SMTP.

.NOTES
Requer PowerShell 5.1, Microsoft Excel instalado, configuração SMTP salva no
PS Panel e o módulo local PSPanel.Email.
#>

[CmdletBinding()]
param(
    [string]$ArquivoEntrada = "",

    [ValidateNotNullOrEmpty()]
    [string]$DiretorioEntrada = (Join-Path -Path $PSScriptRoot -ChildPath "Quarentena"),

    [ValidateLength(0, 320)]
    [string]$FiltroPara = "",

    [switch]$WhatIf,

    [ValidateNotNullOrEmpty()]
    [string]$DestinatarioSimulacao = "msouza@desenbahia.ba.gov.br",

    [ValidateNotNullOrEmpty()]
    [ValidateLength(1, 256)]
    [string]$NomeRemetente = "Suporte TI - GTI Desenbahia"
)

$ErrorActionPreference = "Stop"
$script:PadraoArquivo = '^Quarentena-Emails-\d{4}-\d{2}-\d{2}_\d{4}-\d{2}-\d{2}_\d{6}-Classificados-\d{6}\.xlsx$'
$script:CabecalhosObrigatorios = @(
    "Para",
    "Date",
    "From",
    "Subject",
    "Classificação"
)

function Resolve-ArquivoEntradaQuarentena {
    param(
        [AllowEmptyString()]
        [string]$Caminho,

        [Parameter(Mandatory = $true)]
        [string]$Diretorio
    )

    if (-not [string]::IsNullOrWhiteSpace($Caminho)) {
        if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
            throw "Arquivo de entrada não encontrado: $Caminho"
        }

        $arquivo = Get-Item -LiteralPath $Caminho

        if ($arquivo.Extension -ine ".xlsx") {
            throw "O arquivo de entrada deve possuir a extensão .xlsx."
        }

        return $arquivo
    }

    if (-not (Test-Path -LiteralPath $Diretorio -PathType Container)) {
        throw "Diretório de entrada não encontrado: $Diretorio"
    }

    $arquivoMaisRecente = Get-ChildItem -LiteralPath $Diretorio -File -Filter "*.xlsx" |
        Where-Object {
            -not $_.Name.StartsWith('~$') -and
            $_.Name -match $script:PadraoArquivo
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $arquivoMaisRecente) {
        throw "Nenhum arquivo classificado foi encontrado em: $Diretorio"
    }

    return $arquivoMaisRecente
}

function Get-DataReferenciaArquivo {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Arquivo,

        [object[]]$Registros = @()
    )

    if ($Arquivo.Name -match '^Quarentena-Emails-(?<Data>\d{4}-\d{2}-\d{2})_') {
        $dataArquivo = [datetime]::MinValue

        if (
            [datetime]::TryParseExact(
                $Matches.Data,
                "yyyy-MM-dd",
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$dataArquivo
            )
        ) {
            return $dataArquivo.Date
        }
    }

    foreach ($registro in $Registros) {
        if ($null -ne $registro.DataHora) {
            return ([datetime]$registro.DataHora).Date
        }
    }

    return $Arquivo.LastWriteTime.Date
}

function ConvertTo-DataHoraQuarentena {
    param(
        [AllowNull()]
        [object]$Valor
    )

    if ($null -eq $Valor -or [string]::IsNullOrWhiteSpace([string]$Valor)) {
        return $null
    }

    if (
        $Valor -is [double] -or
        $Valor -is [decimal] -or
        $Valor -is [int] -or
        $Valor -is [long]
    ) {
        try {
            return [datetime]::FromOADate([double]$Valor)
        }
        catch {
            return $null
        }
    }

    if ($Valor -is [datetime]) {
        return [datetime]$Valor
    }

    $dataComFuso = [datetimeoffset]::MinValue
    $estilos = [Globalization.DateTimeStyles]::AllowWhiteSpaces

    foreach ($cultura in @(
        [Globalization.CultureInfo]::GetCultureInfo("pt-BR"),
        [Globalization.CultureInfo]::InvariantCulture
    )) {
        if (
            [datetimeoffset]::TryParse(
                [string]$Valor,
                $cultura,
                $estilos,
                [ref]$dataComFuso
            )
        ) {
            return $dataComFuso.LocalDateTime
        }
    }

    return $null
}

function Get-EnderecosEmail {
    param(
        [AllowEmptyString()]
        [string]$Texto
    )

    if ([string]::IsNullOrWhiteSpace($Texto)) {
        return @()
    }

    $padrao = '(?i)(?<![a-z0-9.!#$%&''*+/=?^_`{|}~-])' +
        '[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@' +
        '[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?' +
        '(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+'
    $encontrados = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($ocorrencia in [regex]::Matches($Texto, $padrao)) {
        $endereco = $ocorrencia.Value.Trim().ToLowerInvariant()

        try {
            $mailAddress = [Net.Mail.MailAddress]::new($endereco)

            if ($mailAddress.Address -ieq $endereco) {
                [void]$encontrados.Add($endereco)
            }
        }
        catch {
            # Ignora ocorrências que não representam endereços válidos.
        }
    }

    return @($encontrados)
}

function Read-RegistrosQuarentena {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$Arquivo
    )

    $excel = $null
    $workbook = $null
    $worksheet = $null
    $usedRange = $null

    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $workbook = $excel.Workbooks.Open($Arquivo.FullName, 0, $true)

        try {
            $worksheet = $workbook.Worksheets.Item("Auditoria")
        }
        catch {
            throw "A planilha 'Auditoria' não foi encontrada em '$($Arquivo.Name)'."
        }

        $usedRange = $worksheet.UsedRange

        if ($usedRange.Row -ne 1 -or $usedRange.Column -ne 1) {
            throw "A tabela da planilha 'Auditoria' deve começar na célula A1."
        }

        $quantidadeLinhas = $usedRange.Rows.Count
        $quantidadeColunas = $usedRange.Columns.Count

        if ($quantidadeLinhas -lt 1 -or $quantidadeColunas -lt 1) {
            return @()
        }

        $valores = $usedRange.Value2
        $cabecalhos = @{}

        for ($coluna = 1; $coluna -le $quantidadeColunas; $coluna++) {
            $nomeCabecalho = ([string]$valores[1, $coluna]).Trim()

            if ([string]::IsNullOrWhiteSpace($nomeCabecalho)) {
                continue
            }

            if ($cabecalhos.ContainsKey($nomeCabecalho)) {
                throw "Cabeçalho duplicado na planilha Auditoria: $nomeCabecalho"
            }

            $cabecalhos[$nomeCabecalho] = $coluna
        }

        foreach ($cabecalho in $script:CabecalhosObrigatorios) {
            if (-not $cabecalhos.ContainsKey($cabecalho)) {
                throw "Coluna obrigatória ausente na planilha Auditoria: $cabecalho"
            }
        }

        $registros = [Collections.Generic.List[object]]::new()

        for ($linha = 2; $linha -le $quantidadeLinhas; $linha++) {
            $para = ([string]$valores[$linha, $cabecalhos["Para"]]).Trim()
            $remetente = ([string]$valores[$linha, $cabecalhos["From"]]).Trim()
            $assunto = ([string]$valores[$linha, $cabecalhos["Subject"]]).Trim()
            $classificacao = (
                [string]$valores[$linha, $cabecalhos["Classificação"]]
            ).Trim()
            $dataOriginal = $valores[$linha, $cabecalhos["Date"]]

            if (
                [string]::IsNullOrWhiteSpace($para) -and
                [string]::IsNullOrWhiteSpace($remetente) -and
                [string]::IsNullOrWhiteSpace($assunto) -and
                $null -eq $dataOriginal
            ) {
                continue
            }

            $registros.Add([PSCustomObject]@{
                Linha = $linha
                Para = $para
                Date = $dataOriginal
                DataHora = ConvertTo-DataHoraQuarentena -Valor $dataOriginal
                From = $remetente
                Subject = $assunto
                Classificacao = $classificacao
            })
        }

        return @($registros)
    }
    finally {
        if ($null -ne $workbook) {
            try { $workbook.Close($false) } catch { }
        }

        if ($null -ne $excel) {
            try { $excel.Quit() } catch { }
        }

        foreach ($objeto in @($usedRange, $worksheet, $workbook, $excel)) {
            if (
                $null -ne $objeto -and
                [Runtime.InteropServices.Marshal]::IsComObject($objeto)
            ) {
                try {
                    [void][Runtime.InteropServices.Marshal]::ReleaseComObject($objeto)
                }
                catch { }
            }
        }

        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

function Group-RegistrosPorDestinatario {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Registros
    )

    $grupos = @{}
    $linhasIgnoradas = [Collections.Generic.List[int]]::new()
    $linhasClassificacaoIgnorada = [Collections.Generic.List[int]]::new()

    foreach ($registro in $Registros) {
        if ($registro.Classificacao -notin @(
            "Potencialmente válida",
            "Inválida"
        )) {
            $linhasClassificacaoIgnorada.Add([int]$registro.Linha)
            continue
        }

        $enderecos = @(Get-EnderecosEmail -Texto $registro.Para)

        if ($enderecos.Count -eq 0) {
            $linhasIgnoradas.Add([int]$registro.Linha)
            continue
        }

        foreach ($endereco in $enderecos) {
            if (-not $grupos.ContainsKey($endereco)) {
                $grupos[$endereco] = [PSCustomObject]@{
                    Destinatario = $endereco
                    Mensagens = [Collections.Generic.List[object]]::new()
                    Assinaturas = [Collections.Generic.HashSet[string]]::new(
                        [StringComparer]::Ordinal
                    )
                }
            }

            $assinatura = @(
                [string]$registro.Date,
                $registro.From,
                $registro.Subject,
                $registro.Classificacao
            ) -join [char]0x1F

            if ($grupos[$endereco].Assinaturas.Add($assinatura)) {
                $grupos[$endereco].Mensagens.Add($registro)
            }
        }
    }

    return [PSCustomObject]@{
        Grupos = @($grupos.Values | Sort-Object Destinatario)
        LinhasIgnoradas = @($linhasIgnoradas)
        LinhasClassificacaoIgnorada = @($linhasClassificacaoIgnorada)
    }
}

function ConvertTo-HtmlSeguro {
    param(
        [AllowNull()]
        [object]$Valor
    )

    if ($null -eq $Valor) {
        return ""
    }

    return [Net.WebUtility]::HtmlEncode([string]$Valor)
}

function Format-DataHoraMensagem {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Registro
    )

    if ($null -ne $Registro.DataHora) {
        return ([datetime]$Registro.DataHora).ToString("dd/MM/yyyy HH:mm:ss")
    }

    if ([string]::IsNullOrWhiteSpace([string]$Registro.Date)) {
        return "Não informada"
    }

    return [string]$Registro.Date
}

function New-SecaoMensagensQuarentena {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Titulo,

        [Parameter(Mandatory = $true)]
        [string]$Explicacao,

        [Parameter(Mandatory = $true)]
        [string]$CorDestaque,

        [Parameter(Mandatory = $true)]
        [string]$DestinatarioOriginal,

        [Parameter(Mandatory = $true)]
        [object[]]$Mensagens
    )

    $linhasTabela = [Text.StringBuilder]::new()
    $indice = 0

    foreach ($mensagem in @($Mensagens | Sort-Object @{ Expression = {
        if ($null -eq $_.DataHora) { [datetime]::MaxValue } else { $_.DataHora }
    } }, Subject)) {
        $corFundo = if (($indice % 2) -eq 0) { "#ffffff" } else { "#f5f8fc" }
        $dataHora = ConvertTo-HtmlSeguro (Format-DataHoraMensagem -Registro $mensagem)
        $para = ConvertTo-HtmlSeguro $DestinatarioOriginal
        $remetente = ConvertTo-HtmlSeguro $mensagem.From
        $assunto = ConvertTo-HtmlSeguro $mensagem.Subject

        [void]$linhasTabela.AppendLine(@"
<tr style="background-color:$corFundo;">
  <td style="padding:12px 10px;border-bottom:1px solid #d9e2ec;vertical-align:top;white-space:nowrap;color:#243b53;">$dataHora</td>
  <td style="padding:12px 10px;border-bottom:1px solid #d9e2ec;vertical-align:top;color:#243b53;word-break:break-word;">$para</td>
  <td style="padding:12px 10px;border-bottom:1px solid #d9e2ec;vertical-align:top;color:#243b53;word-break:break-word;">$remetente</td>
  <td style="padding:12px 10px;border-bottom:1px solid #d9e2ec;vertical-align:top;color:#243b53;word-break:break-word;">$assunto</td>
</tr>
"@)
        $indice++
    }

    $tituloSeguro = ConvertTo-HtmlSeguro $Titulo
    $explicacaoSegura = ConvertTo-HtmlSeguro $Explicacao
    $quantidade = $Mensagens.Count

    return @"
<div style="margin:0 0 28px;">
  <div style="margin:0 0 8px;font-size:18px;font-weight:600;color:$CorDestaque;">$tituloSeguro ($quantidade)</div>
  <div style="margin:0 0 12px;padding:12px 15px;border-left:5px solid $CorDestaque;background-color:#f7f9fb;color:#334e68;line-height:1.55;">$explicacaoSegura</div>
  <div style="width:100%;overflow-x:auto;">
    <table role="table" width="100%" cellspacing="0" cellpadding="0" border="0" style="border-collapse:collapse;border:1px solid #bcccdc;font-size:13px;line-height:1.4;">
      <thead>
        <tr style="background-color:$CorDestaque;color:#ffffff;">
          <th align="left" style="padding:11px 10px;border-right:1px solid #ffffff;white-space:nowrap;">Data/Hora</th>
          <th align="left" style="padding:11px 10px;border-right:1px solid #ffffff;">Destinatário</th>
          <th align="left" style="padding:11px 10px;border-right:1px solid #ffffff;">Remetente</th>
          <th align="left" style="padding:11px 10px;">Assunto</th>
        </tr>
      </thead>
      <tbody>
$($linhasTabela.ToString())
      </tbody>
    </table>
  </div>
</div>
"@
}

function New-CorpoEmailQuarentena {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DestinatarioOriginal,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$MensagensPotencialmenteValidas,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$MensagensInvalidas,

        [Parameter(Mandatory = $true)]
        [datetime]$DataReferencia,

        [Parameter(Mandatory = $true)]
        [string]$NomeScript,

        [Parameter(Mandatory = $true)]
        [datetime]$DataExecucao,

        [switch]$Simulacao,

        [AllowEmptyString()]
        [string]$DestinatarioEntrega = ""
    )

    $avisoSimulacao = ""

    if ($Simulacao) {
        $originalSeguro = ConvertTo-HtmlSeguro $DestinatarioOriginal
        $entregaSegura = ConvertTo-HtmlSeguro $DestinatarioEntrega
        $avisoSimulacao = @"
<div style="margin:0 0 18px;padding:12px 16px;border:1px solid #7fb3d5;background-color:#eaf4fb;color:#154360;border-radius:6px;">
  <strong>Modo de simulação:</strong> esta mensagem seria enviada para <strong>$originalSeguro</strong>, mas foi entregue a <strong>$entregaSegura</strong>.
</div>
"@
    }

    $quantidade = (
        $MensagensPotencialmenteValidas.Count + $MensagensInvalidas.Count
    )
    $descricaoQuantidade = if ($quantidade -eq 1) {
        "1 mensagem retida"
    }
    else {
        "$quantidade mensagens retidas"
    }
    $dataReferenciaTexto = $DataReferencia.ToString("dd/MM/yyyy")
    $dataExecucaoTexto = $DataExecucao.ToString("dd/MM/yyyy HH:mm:ss")
    $nomeScriptSeguro = ConvertTo-HtmlSeguro $NomeScript
    $secoesMensagens = [Text.StringBuilder]::new()

    if ($MensagensPotencialmenteValidas.Count -gt 0) {
        [void]$secoesMensagens.AppendLine((New-SecaoMensagensQuarentena `
            -Titulo "Mensagens suspeitas e retidas" `
            -Explicacao "Os remetentes não possuem as devidas configurações de segurança (SPF, DKIM ou DMARC)." `
            -CorDestaque "#2f75b5" `
            -DestinatarioOriginal $DestinatarioOriginal `
            -Mensagens $MensagensPotencialmenteValidas))
    }

    if ($MensagensInvalidas.Count -gt 0) {
        [void]$secoesMensagens.AppendLine((New-SecaoMensagensQuarentena `
            -Titulo "Mensagens com fortes indícios de invalidade" `
            -Explicacao "Estas mensagens têm alta probabilidade de serem falsas. Além de o remetente não possuir as devidas configurações de segurança, elas apresentam características de spam ou falsidade." `
            -CorDestaque "#b42318" `
            -DestinatarioOriginal $DestinatarioOriginal `
            -Mensagens $MensagensInvalidas))
    }

    return @"
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Sumário de e-mails na quarentena</title>
</head>
<body style="margin:0;padding:0;background-color:#eef2f6;font-family:Segoe UI,Arial,sans-serif;color:#243b53;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:#eef2f6;">
    <tr>
      <td align="center" style="padding:24px 12px;">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:980px;background-color:#ffffff;border:1px solid #d9e2ec;border-radius:8px;overflow:hidden;">
          <tr>
            <td style="padding:24px 28px;background-color:#174a7e;color:#ffffff;">
              <div style="font-size:13px;letter-spacing:0.5px;text-transform:uppercase;opacity:0.9;">GTI · Gerência de Tecnologia da Informação</div>
              <div style="margin-top:6px;font-size:25px;font-weight:600;line-height:1.25;">Sumário de e-mails na quarentena</div>
              <div style="margin-top:5px;font-size:15px;opacity:0.9;">Mensagens de $dataReferenciaTexto · $descricaoQuantidade</div>
            </td>
          </tr>
          <tr>
            <td style="padding:24px 28px 28px;">
              $avisoSimulacao
              <div style="margin:0 0 22px;padding:16px 18px;border-left:5px solid #d9822b;background-color:#fff7e6;color:#5c3b00;line-height:1.55;">
                <strong style="display:block;margin-bottom:5px;color:#7a4100;">Atenção</strong>
                A seguir estão as mensagens que ficaram retidas em quarentena por suspeita de fraude. Os remetentes dessas mensagens não possuem os requisitos mínimos de segurança para que elas fossem reconhecidas como autênticas. Caso queira liberar alguma dessas mensagens e recebê-la em sua caixa de entrada, abra um chamado na Central de Serviços da GTI.
              </div>
              $($secoesMensagens.ToString())
              <div style="margin:4px 0 24px;padding:16px 18px;border:1px solid #d9e2ec;background-color:#f7f9fb;color:#334e68;line-height:1.6;border-radius:6px;">
                Caso queira evitar que mensagens legítimas fiquem retidas em quarentena, notifique o remetente e solicite a configuração adequada de SPF, DKIM e DMARC.<br>
                Para mais esclarecimentos, consulte:
                <a href="https://www.cloudflare.com/pt-br/learning/email-security/dmarc-dkim-spf/" style="color:#174a7e;font-weight:600;">SPF, DKIM e DMARC</a>.
              </div>
              <div style="margin-top:24px;padding-top:18px;border-top:1px solid #d9e2ec;color:#52616b;font-size:12px;line-height:1.55;">
                <strong style="color:#334e68;">Mensagem enviada por GTI - Gerência de Tecnologia da Informação</strong><br>
                Rotina automática: $nomeScriptSeguro em $dataExecucaoTexto
              </div>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
"@
}

function Test-EnderecoEmail {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endereco
    )

    if ($Endereco -match '[\r\n]') {
        return $false
    }

    try {
        $mailAddress = [Net.Mail.MailAddress]::new($Endereco)
        return $mailAddress.Address -ieq $Endereco.Trim()
    }
    catch {
        return $false
    }
}

$arquivo = Resolve-ArquivoEntradaQuarentena `
    -Caminho $ArquivoEntrada `
    -Diretorio $DiretorioEntrada

Write-Host "Arquivo selecionado: $($arquivo.FullName)"
$registros = @(Read-RegistrosQuarentena -Arquivo $arquivo)

if ($registros.Count -eq 0) {
    Write-Host "A planilha Auditoria não possui mensagens para envio."
    return
}

$filtroParaNormalizado = ""

if (-not [string]::IsNullOrWhiteSpace($FiltroPara)) {
    $filtroParaNormalizado = $FiltroPara.Trim().ToLowerInvariant()

    if (-not (Test-EnderecoEmail -Endereco $filtroParaNormalizado)) {
        throw "Filtro da coluna Para inválido: $FiltroPara"
    }
}

$agrupamento = Group-RegistrosPorDestinatario -Registros $registros
$grupos = @($agrupamento.Grupos)

if (-not [string]::IsNullOrWhiteSpace($filtroParaNormalizado)) {
    $grupos = @($grupos | Where-Object {
        $_.Destinatario -ieq $filtroParaNormalizado
    })
    Write-Host "Filtro da coluna Para aplicado: $filtroParaNormalizado"
}

if ($agrupamento.LinhasIgnoradas.Count -gt 0) {
    Write-Warning (
        "Foram ignoradas {0} linha(s) sem endereço válido na coluna Para: {1}" -f
        $agrupamento.LinhasIgnoradas.Count,
        ($agrupamento.LinhasIgnoradas -join ", ")
    )
}

if ($agrupamento.LinhasClassificacaoIgnorada.Count -gt 0) {
    Write-Warning (
        (
            "Foram ignoradas {0} linha(s) cuja classificação não é " +
            "'Potencialmente válida' nem 'Inválida': {1}"
        ) -f
        $agrupamento.LinhasClassificacaoIgnorada.Count,
        ($agrupamento.LinhasClassificacaoIgnorada -join ", ")
    )
}

if ($grupos.Count -eq 0) {
    if (-not [string]::IsNullOrWhiteSpace($filtroParaNormalizado)) {
        throw (
            "Nenhuma mensagem com classificação 'Potencialmente válida' ou " +
            "'Inválida' foi encontrada para: $filtroParaNormalizado"
        )
    }

    throw (
        "Nenhuma mensagem com classificação 'Potencialmente válida' ou " +
        "'Inválida' e destinatário válido foi encontrada."
    )
}

if ($WhatIf -and -not (Test-EnderecoEmail -Endereco $DestinatarioSimulacao)) {
    throw "Destinatário de simulação inválido: $DestinatarioSimulacao"
}

$dataReferencia = Get-DataReferenciaArquivo `
    -Arquivo $arquivo `
    -Registros $registros
$dataExecucao = Get-Date
$nomeScript = [IO.Path]::GetFileName($PSCommandPath)
$assunto = "Sumário de e-mails na quarentena - Dia $($dataReferencia.ToString('dd/MM/yyyy'))"
$caminhoModulo = Join-Path `
    $PSScriptRoot `
    "modules\PSPanel.Email\PSPanel.Email.psm1"

if (-not (Test-Path -LiteralPath $caminhoModulo -PathType Leaf)) {
    throw "Módulo PSPanel.Email não encontrado: $caminhoModulo"
}

Import-Module $caminhoModulo -Force -ErrorAction Stop

if ($WhatIf) {
    Write-Warning (
        "Modo de simulação ativo: os {0} resumo(s) serão enviados para {1}." -f
        $grupos.Count,
        $DestinatarioSimulacao
    )
}
else {
    Write-Host "Serão enviados $($grupos.Count) resumo(s), um por destinatário."
}

$falhas = [Collections.Generic.List[string]]::new()
$enviados = 0

foreach ($grupo in $grupos) {
    $destinatarioEntrega = if ($WhatIf) {
        $DestinatarioSimulacao
    }
    else {
        $grupo.Destinatario
    }

    $mensagensPotencialmenteValidas = @(
        $grupo.Mensagens | Where-Object {
            $_.Classificacao -ieq "Potencialmente válida"
        }
    )
    $mensagensInvalidas = @(
        $grupo.Mensagens | Where-Object {
            $_.Classificacao -ieq "Inválida"
        }
    )
    $quantidadeMensagens = (
        $mensagensPotencialmenteValidas.Count + $mensagensInvalidas.Count
    )
    $corpo = New-CorpoEmailQuarentena `
        -DestinatarioOriginal $grupo.Destinatario `
        -MensagensPotencialmenteValidas $mensagensPotencialmenteValidas `
        -MensagensInvalidas $mensagensInvalidas `
        -DataReferencia $dataReferencia `
        -NomeScript $nomeScript `
        -DataExecucao $dataExecucao `
        -Simulacao:$WhatIf `
        -DestinatarioEntrega $destinatarioEntrega

    try {
        Send-PSPanelEmail `
            -To $destinatarioEntrega `
            -Subject $assunto `
            -Body $corpo `
            -BodyAsHtml `
            -FromName $NomeRemetente `
            -ErrorAction Stop

        $enviados++
        Write-Host (
            "Resumo enviado: {0} ({1} mensagem(ns); entrega: {2})" -f
            $grupo.Destinatario,
            $quantidadeMensagens,
            $destinatarioEntrega
        )
    }
    catch {
        $falhas.Add(
            "$($grupo.Destinatario): $($_.Exception.Message)"
        )
        Write-Error `
            -Message "Falha no resumo de $($grupo.Destinatario)." `
            -ErrorAction Continue
    }
}

Write-Host "Envios concluídos: $enviados de $($grupos.Count)."

if ($falhas.Count -gt 0) {
    throw (
        "Ocorreram falhas em {0} envio(s): {1}" -f
        $falhas.Count,
        ($falhas -join " | ")
    )
}
