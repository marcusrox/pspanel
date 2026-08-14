#requires -Version 5.1

<#
.SYNOPSIS
Executa em sequência a exportação, classificação e notificação da quarentena.

.DESCRIPTION
Executa os scripts Quarentena-Step-1-Exportar-Do-Outlook.ps1,
Quarentena-Step-2-Classificar-Emails.ps1 e
Quarentena-Step-3-Enviar-Sumario-Emails.ps1 nesta ordem.

A data informada é usada pelo Step 1 para exportar as mensagens. O arquivo
bruto criado nessa execução é passado ao Step 2, e o arquivo classificado
resultante é passado ao Step 3. A execução é interrompida se uma etapa falhar
ou se o arquivo esperado não for encontrado.

.PARAMETER DataMensagens
Data opcional das mensagens que serão processadas. Aceita os formatos
yyyy-MM-dd e dd/MM/yyyy. Quando omitida, utiliza a data do dia da execução.

.PARAMETER FiltroPara
Endereço opcional da coluna Para cujas mensagens devem compor o relatório
enviado pelo Step 3. Quando omitido, o Step 3 processa todos os destinatários.

.PARAMETER WhatIf
Redireciona o relatório ao DestinatarioSimulacao. Este parâmetro ainda realiza
o envio; ele apenas impede a entrega ao destinatário original.

.PARAMETER DestinatarioSimulacao
Endereço opcional que recebe o relatório quando WhatIf é usado. Quando
omitido, o Step 3 utiliza seu próprio valor padrão.

.EXAMPLE
.\Quarentena-Executar-Fluxo-Completo.ps1

Executa as três etapas para as mensagens do dia atual e envia os relatórios
para todos os destinatários encontrados pelo Step 3.

.EXAMPLE
.\Quarentena-Executar-Fluxo-Completo.ps1 -DataMensagens "2026-08-14"

Executa as três etapas e envia os relatórios para todos os destinatários
encontrados pelo Step 3.

.EXAMPLE
.\Quarentena-Executar-Fluxo-Completo.ps1 `
    -DataMensagens "2026-08-14" `
    -FiltroPara "usuario@desenbahia.ba.gov.br" `
    -WhatIf `
    -DestinatarioSimulacao "msouza@desenbahia.ba.gov.br"

Exporta e classifica as mensagens de 14/08/2026 e envia o relatório filtrado
ao destinatário de simulação.

.INPUTS
Nenhum.

.OUTPUTS
Mensagens de progresso no host. Os três steps criam planilhas e enviam o
relatório conforme seus próprios comportamentos.

.NOTES
Requer Outlook clássico e Microsoft Excel instalados, perfil do Outlook
autenticado e configuração SMTP salva no PS Panel. Em modo WhatIf, o Step 3
continua realizando um envio SMTP real ao destinatário de simulação.
#>

[CmdletBinding()]
param(
    [AllowEmptyString()]
    [string]$DataMensagens = "",

    [AllowEmptyString()]
    [ValidateLength(0, 320)]
    [string]$FiltroPara = "",

    [switch]$WhatIf,

    [AllowEmptyString()]
    [ValidateLength(0, 320)]
    [string]$DestinatarioSimulacao = ""
)

$ErrorActionPreference = "Stop"

function ConvertTo-DataFluxoQuarentena {
    param(
        [AllowEmptyString()]
        [string]$Valor
    )

    if ([string]::IsNullOrWhiteSpace($Valor)) {
        return (Get-Date).Date
    }

    $data = [datetime]::MinValue

    foreach ($formato in @("yyyy-MM-dd", "dd/MM/yyyy")) {
        if (
            [datetime]::TryParseExact(
                $Valor.Trim(),
                $formato,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::None,
                [ref]$data
            )
        ) {
            return $data.Date
        }
    }

    throw "Data inválida em -DataMensagens. Use yyyy-MM-dd ou dd/MM/yyyy."
}

function Test-EnderecoEmailFluxo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endereco
    )

    if ($Endereco -match '[\r\n]') {
        return $false
    }

    try {
        $mailAddress = [Net.Mail.MailAddress]::new($Endereco.Trim())
        return $mailAddress.Address -ieq $Endereco.Trim()
    }
    catch {
        return $false
    }
}

function Assert-ScriptEtapaExiste {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Caminho,

        [Parameter(Mandatory = $true)]
        [string]$NomeEtapa
    )

    if (-not (Test-Path -LiteralPath $Caminho -PathType Leaf)) {
        throw "$NomeEtapa não encontrado: $Caminho"
    }
}

function Get-NovoArquivoEtapa {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Diretorio,

        [Parameter(Mandatory = $true)]
        [string]$PadraoNome,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ArquivosAnteriores,

        [Parameter(Mandatory = $true)]
        [datetime]$InicioEtapa,

        [Parameter(Mandatory = $true)]
        [string]$Descricao
    )

    $candidatos = @(
        Get-ChildItem -LiteralPath $Diretorio -File -Filter "*.xlsx" |
            Where-Object {
                -not $_.Name.StartsWith("~$") -and
                $_.Name -match $PadraoNome -and
                (
                    $_.FullName -notin $ArquivosAnteriores -or
                    $_.LastWriteTime -ge $InicioEtapa.AddSeconds(-2)
                )
            } |
            Sort-Object LastWriteTime -Descending
    )

    if ($candidatos.Count -eq 0) {
        throw "O arquivo $Descricao não foi encontrado após a execução."
    }

    return $candidatos[0]
}

$dataProcessamento = ConvertTo-DataFluxoQuarentena -Valor $DataMensagens
$dataIso = $dataProcessamento.ToString("yyyy-MM-dd")
$diretorioQuarentena = Join-Path -Path $PSScriptRoot -ChildPath "Quarentena"
$step1 = Join-Path $diretorioQuarentena "Quarentena-Step-1-Exportar-Do-Outlook.ps1"
$step2 = Join-Path $diretorioQuarentena "Quarentena-Step-2-Classificar-Emails.ps1"
$step3 = Join-Path $diretorioQuarentena "Quarentena-Step-3-Enviar-Sumario-Emails.ps1"

if (
    -not [string]::IsNullOrWhiteSpace($FiltroPara) -and
    -not (Test-EnderecoEmailFluxo -Endereco $FiltroPara)
) {
    throw "Filtro da coluna Para inválido: $FiltroPara"
}

if (
    $WhatIf -and
    -not [string]::IsNullOrWhiteSpace($DestinatarioSimulacao) -and
    -not (Test-EnderecoEmailFluxo -Endereco $DestinatarioSimulacao)
) {
    throw "Destinatário de simulação inválido: $DestinatarioSimulacao"
}

Assert-ScriptEtapaExiste -Caminho $step1 -NomeEtapa "Step 1"
Assert-ScriptEtapaExiste -Caminho $step2 -NomeEtapa "Step 2"
Assert-ScriptEtapaExiste -Caminho $step3 -NomeEtapa "Step 3"

if (-not (Test-Path -LiteralPath $diretorioQuarentena -PathType Container)) {
    [void](New-Item -Path $diretorioQuarentena -ItemType Directory -Force)
}

$arquivosAntesStep1 = @(
    Get-ChildItem -LiteralPath $diretorioQuarentena -File -Filter "*.xlsx" |
        ForEach-Object FullName
)
$inicioStep1 = Get-Date

Write-Host ""
Write-Host "=== Step 1 de 3: exportar mensagens de $dataIso ===" -ForegroundColor Cyan

try {
    & $step1 -DataMensagens $dataIso
}
catch {
    throw "Falha no Step 1 (exportação): $($_.Exception.Message)"
}

$padraoArquivoBruto = (
    "^Quarentena-Emails-{0}_\d{{4}}-\d{{2}}-\d{{2}}_\d{{6}}\.xlsx$" -f
    [regex]::Escape($dataIso)
)
$arquivoBruto = Get-NovoArquivoEtapa `
    -Diretorio $diretorioQuarentena `
    -PadraoNome $padraoArquivoBruto `
    -ArquivosAnteriores $arquivosAntesStep1 `
    -InicioEtapa $inicioStep1 `
    -Descricao "bruto do Step 1"

Write-Host "Arquivo bruto selecionado: $($arquivoBruto.FullName)"

$arquivosAntesStep2 = @(
    Get-ChildItem -LiteralPath $diretorioQuarentena -File -Filter "*.xlsx" |
        ForEach-Object FullName
)
$inicioStep2 = Get-Date

Write-Host ""
Write-Host "=== Step 2 de 3: classificar mensagens ===" -ForegroundColor Cyan

try {
    & $step2 -ArquivoEntrada $arquivoBruto.FullName
}
catch {
    throw "Falha no Step 2 (classificação): $($_.Exception.Message)"
}

$nomeBaseBruto = [IO.Path]::GetFileNameWithoutExtension($arquivoBruto.Name)
$padraoArquivoClassificado = (
    "^{0}-Classificados-\d{{6}}\.xlsx$" -f
    [regex]::Escape($nomeBaseBruto)
)
$arquivoClassificado = Get-NovoArquivoEtapa `
    -Diretorio $diretorioQuarentena `
    -PadraoNome $padraoArquivoClassificado `
    -ArquivosAnteriores $arquivosAntesStep2 `
    -InicioEtapa $inicioStep2 `
    -Descricao "classificado do Step 2"

Write-Host "Arquivo classificado selecionado: $($arquivoClassificado.FullName)"

$parametrosStep3 = @{
    ArquivoEntrada = $arquivoClassificado.FullName
}

if (-not [string]::IsNullOrWhiteSpace($FiltroPara)) {
    $parametrosStep3["FiltroPara"] = $FiltroPara.Trim()
}

if ($WhatIf) {
    $parametrosStep3["WhatIf"] = $true

    if (-not [string]::IsNullOrWhiteSpace($DestinatarioSimulacao)) {
        $parametrosStep3["DestinatarioSimulacao"] = $DestinatarioSimulacao.Trim()
    }
}

Write-Host ""
Write-Host "=== Step 3 de 3: enviar sumário ===" -ForegroundColor Cyan

try {
    & $step3 @parametrosStep3
}
catch {
    throw "Falha no Step 3 (envio do sumário): $($_.Exception.Message)"
}

Write-Host ""
Write-Host "Fluxo completo concluído com sucesso." -ForegroundColor Green
Write-Host "Data processada: $($dataProcessamento.ToString('dd/MM/yyyy'))"
Write-Host "Arquivo bruto: $($arquivoBruto.FullName)"
Write-Host "Arquivo classificado: $($arquivoClassificado.FullName)"

if (-not [string]::IsNullOrWhiteSpace($FiltroPara)) {
    Write-Host "Destinatário filtrado: $($FiltroPara.Trim())"
}
else {
    Write-Host "Destinatários: todos os encontrados no arquivo classificado"
}

if ($WhatIf) {
    if (-not [string]::IsNullOrWhiteSpace($DestinatarioSimulacao)) {
        Write-Host "Relatório entregue em modo de simulação para: $($DestinatarioSimulacao.Trim())"
    }
    else {
        Write-Host "Modo de simulação: destinatário padrão do Step 3"
    }
}
