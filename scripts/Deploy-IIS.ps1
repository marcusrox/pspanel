# Script para deploy da aplicação no IIS
# Autor: Deployment Team
# Data: 2024

# Exemplo de uso:
# .\Deploy-IIS.ps1 -appName "APP_NAME" -AMBIENTE "INTERNO"
# .\Deploy-IIS.ps1 -appName "ConsultaAcesso" -AMBIENTE "INTERNO"
param(
    [Parameter(Mandatory=$true)]
    [string]$appName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("INTERNO", "EXTERNO")]
    [string]$AMBIENTE
)

# Definição de parâmetros e variáveis
$currentDate = Get-Date -Format "yyyy-MM-dd"
$currentDateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

# Definição do servidor e caminho baseado no ambiente
switch ($AMBIENTE) {
    "INTERNO" {
        $serverName = "SERV38D"
        $destinationPath = "\\$serverName\d$\Sistemas\APP\$appName"
        $backupPath = "\\$serverName\d$\Sistemas\APP"
    }
    "EXTERNO" {
        $serverName = "ext05d"
        $destinationPath = "\\$serverName\d$\WWWS\$appName"
        $backupPath = "\\$serverName\d$\WWWS"
    }
}

$sourcePath = "\\interno\Implantacoes\PRD\$currentDate\$appName\WEB"
$backupFileName = "$appName-$currentDateTime.zip"
$logPath = "$backupPath\deploy"
$logFile = "$logPath\deploy-$AMBIENTE-$appName-$currentDateTime.log"

# Função para escrever no log
function Write-Log {
    param(
        [string]$Message
    )
    
    $logMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): $Message"
    Write-Host $logMessage
    
    # Criar diretório de log se não existir
    if (-not (Test-Path -Path $logPath)) {
        New-Item -ItemType Directory -Path $logPath -Force | Out-Null
    }
    
    Add-Content -Path $logFile -Value $logMessage
}

# Função para validar a existência de um caminho
function Test-PathExists {
    param (
        [string]$Path,
        [string]$PathType
    )
    
    if (-not (Test-Path -Path $Path)) {
        Write-Log "ERRO: O caminho $PathType '$Path' não existe ou não está acessível."
        exit 1
    }
}

# Função para criar backup
function New-BackupZip {
    param (
        [string]$SourcePath,
        [string]$BackupPath,
        [string]$BackupFileName
    )
    
    try {
        $backupFullPath = Join-Path -Path $BackupPath -ChildPath $BackupFileName
        Write-Log "Criando backup em: $backupFullPath"
        
        if (Test-Path -Path $SourcePath) {
            Compress-Archive -Path "$SourcePath\*" -DestinationPath $backupFullPath -Force
            Write-Log "Backup criado com sucesso!"
        } else {
            Write-Log "AVISO: Pasta origem '$SourcePath' não existe. Backup não foi criado."
        }
    } catch {
        Write-Log "ERRO ao criar backup: $_"
        exit 1
    }
}

# Função para limpar diretório mantendo web.config
function Clear-DirectoryKeepWebConfig {
    param (
        [string]$Path
    )
    
    try {
        Write-Log "Limpando diretório: $Path"
        Get-ChildItem -Path $Path -Exclude "web.config","deploy" | Remove-Item -Recurse -Force
        Write-Log "Diretório limpo com sucesso (web.config e pasta deploy preservados)!"
    } catch {
        Write-Log "ERRO ao limpar diretório: $_"
        exit 1
    }
}

# Função para copiar arquivos
function Copy-DeployFiles {
    param (
        [string]$Source,
        [string]$Destination
    )
    
    try {
        Write-Log "Copiando arquivos de $Source para $Destination"
        Copy-Item -Path "$Source\*" -Destination $Destination -Recurse -Force
        Write-Log "Arquivos copiados com sucesso!"
    } catch {
        Write-Log "ERRO ao copiar arquivos: $_"
        exit 1
    }
}

# Função para atualizar timestamp do web.config
function Update-WebConfigTimestamp {
    param (
        [string]$Path
    )
    
    try {
        $webConfigPath = Join-Path -Path $Path -ChildPath "web.config"
        if (Test-Path $webConfigPath) {
            (Get-Item $webConfigPath).LastWriteTime = Get-Date
            Write-Log "Timestamp do web.config atualizado com sucesso!"
        } else {
            Write-Log "ERRO: Arquivo web.config não encontrado em $Path"
            exit 1
        }
    } catch {
        Write-Log "ERRO ao atualizar timestamp do web.config: $_"
        exit 1
    }
}

# Função para enviar mensagem via WhatsApp usando Evolution API
function Send-WhatsAppMessage {
    param (
        [string]$phoneNumber,
        [string]$message
    )
    $apikey = "cd65ff251ca6dc7616a2cc6ef0d7c6d2"
    #$instance = "BFD925E81B7D-454E-B484-6DB9B54E6675"
    $instance = "Atendimento"
    try {
        $evolutionApiUrl = "https://evolution.idevsolutions.com.br/message/sendText/$instance"
        
        # Remove caracteres não numéricos do número de telefone
        $cleanPhoneNumber = $phoneNumber -replace '[^0-9]', ''
        
        # Defina os headers
        $headers = @{
            "apikey"       = $apikey
            "Content-Type" = "application/json"
        }

        # Monta o corpo da requisição
        $body = @{
            number  = "55$cleanPhoneNumber@c.us"
            #number      = "557192769969"
            #number  = "557187131802-1392228925@g.us" # Grupo da USI no WhatsApp
            options = @{
                delay    = 1200
                presence = "composing"
            }
            text    = $message
        } | ConvertTo-Json
        
        try {
            # Faz a requisição POST para a Evolution API
            $response = Invoke-RestMethod -Uri $evolutionApiUrl -Method Post -Body $body -Headers $headers -ContentType "application/json"
            Write-Host "Mensagem WhatsApp enviada com sucesso! Status: $($response.status)"
        }
        catch { 
            Write-Host "AVISO: Falha ao enviar mensagem WhatsApp. Status: $($response.status)"
            Write-Host "Ocorreu um erro na chamada HTTP:"   
            Write-Host $_.Exception.Message         
        }
    }
    catch {
        Write-Host "ERRO ao enviar mensagem WhatsApp: $_"
    }
}


# Início do processo de deploy
Write-Log "Iniciando processo de deploy da aplicação $appName em $currentDate"
Write-Log "Ambiente: $AMBIENTE"
Write-Log "Caminhos que serão utilizados:"
Write-Log "  Origem dos arquivos: $sourcePath"
Write-Log "  Destino do deploy..: $destinationPath"
Write-Log "  Local do backup....: $backupPath"

$confirmation = Read-Host -Prompt "`nDeseja continuar com o deploy? (S/N)"
if ($confirmation -ne "S") {
    Write-Log "Deploy cancelado pelo operador."
    exit 0
}

# Validação dos caminhos
Write-Log "Validando caminhos..."
Test-PathExists -Path $sourcePath -PathType "Origem"
Test-PathExists -Path $destinationPath -PathType "Destino"
Test-PathExists -Path $backupPath -PathType "Backup"

# Criação do backup
Write-Log "Iniciando backup..."
New-BackupZip -SourcePath $destinationPath -BackupPath $backupPath -BackupFileName $backupFileName

# Limpeza do diretório de destino
Write-Log "Iniciando limpeza do diretório..."
Clear-DirectoryKeepWebConfig -Path $destinationPath

# Cópia dos arquivos
Write-Log "Iniciando cópia dos arquivos..."
Copy-DeployFiles -Source $sourcePath -Destination $destinationPath

# Atualização do timestamp do web.config
Write-Log "Atualizando timestamp do web.config..."
Update-WebConfigTimestamp -Path $destinationPath

Write-Log "Deploy concluído com sucesso!"

# Envia mensagem WhatsApp após deploy bem-sucedido
$mensagem = "🚀 *Deploy Concluído!*`n`n_Aplicação:_ *$appName*`n_Ambiente:_ *$AMBIENTE*`n_Data/Hora:_ *$currentDateTime*`n`n✅ *_Deploy realizado com sucesso!_*"
Send-WhatsAppMessage -phoneNumber "71-92769969" -message $mensagem 


