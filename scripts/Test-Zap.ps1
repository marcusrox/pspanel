
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
            "apikey" = $apikey
            "Content-Type"  = "application/json"
        }

        # Monta o corpo da requisição
        $body = @{
            number      = "55$cleanPhoneNumber@c.us"
            #number      = "557192769969"
            options     = @{
                delay    = 1200
                presence = "composing"
            }
            text = $message
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

# Envia mensagem WhatsApp após deploy bem-sucedido
$mensagem = "Deploy da aplicação XX no ambiente YYY foi concluído com sucesso em DDDD"
Send-WhatsAppMessage -phoneNumber "71-92769969" -message $mensagem 
