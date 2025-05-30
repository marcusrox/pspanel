# Requer o módulo Posh-SSH
# Instale com: Install-Module -Name Posh-SSH -Force

# === GARANTE QUE O MÓDULO POSH-SSH ESTEJA INSTALADO E CARREGADO ===
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    Write-Host "Módulo Posh-SSH não encontrado. Instalando..."
    try {
        Install-Module -Name Posh-SSH -Force -Scope CurrentUser -AllowClobber
        Write-Host "Módulo Posh-SSH instalado com sucesso."
    }
    catch {
        Write-Host "Erro ao instalar o módulo Posh-SSH: $_" -ForegroundColor Red
        exit
    }
}

Import-Module Posh-SSH -Force


# === CONFIGURAÇÕES ===
$FortiHost = "10.35.0.1"       # IP ou hostname do FortiGate
$FortiUser = "msouza"             # Usuário
$FortiPassword = "mmdmmd" # Senha


# Diretório onde os arquivos serão salvos
$BackupDir = "C:\FortiGate-Backup"

# === PREPARAÇÃO ===
if (!(Test-Path -Path $BackupDir)) {
    New-Item -ItemType Directory -Path $BackupDir | Out-Null
}

#$DateStamp = Get-Date -Format "yyyyMMdd-HHmmss"

$SecurePassword = ConvertTo-SecureString $FortiPassword -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($FortiUser, $SecurePassword)

# === CONECTANDO ===
$session = New-SSHSession -ComputerName $FortiHost -Credential $Credential -AcceptKey

if ($null -eq $session -or $null -eq $session.SessionId) {
    Write-Host "Erro ao conectar no FortiGate!" -ForegroundColor Red
    exit
}

# === LISTA DE BLOCOS PARA EXTRAÇÃO ===
$blocks = @(
    "firewall policy",
    "firewall policy6",
    "firewall addrgrp",
    "firewall address",
    "firewall service custom",
    "firewall vip",
    "firewall vipgrp",
    "firewall ippool",
    "system interface",
    "router static",
    "router ospf",
    "router bgp",
    "router rip",
    "antivirus",
    "webfilter",
    "application",
    "ips",
    "vpn ipsec phase1-interface",
    "vpn ipsec phase2-interface",
    "vpn ssl settings",
    "user local",
    "user group",
    "user ldap",
    "user radius",
    "system global",
    "system admin",
    "system dns",
    "system ntp",
    "system ha",
    "log",
    "emailfilter",
    "dlp sensor",
    "firewall proxy-policy",
    "firewall ssl-ssh-profile"
)

# === EXTRAÇÃO DE CADA BLOCO ===
foreach ($block in $blocks) {
    Write-Host "Extraindo: $block..."
    $output = Invoke-SSHCommand -Index 0 -Command "show $block"
    $safeName = $block -replace "\s+", "-"   # Substitui espaços por hífens
    $fileName = "${BackupDir}\$safeName.txt"
    $output.Output | Out-File -FilePath $fileName -Encoding utf8 -Force
}

# === EXTRAÇÃO DO FULL CONFIGURATION ===
Write-Host "Extraindo: full-configuration..."
$fullConfig = Invoke-SSHCommand -Index 0 -Command "show full-configuration"
$fullFileName = "${BackupDir}\full-configuration.txt"
$fullConfig.Output | Out-File -FilePath $fullFileName -Encoding utf8 -Force

# === FINALIZA SESSÃO ===
Remove-SSHSession -Index 0

Write-Host "Backup concluído! Arquivos salvos em $BackupDir" -ForegroundColor Green

# === CONTROLE DE VERSÃO COM GIT (robusto) ===
$CurrentDir = Get-Location
try {
    Set-Location -Path $BackupDir

    if (-not (Test-Path ".git")) {
        Write-Host "Repositório Git não encontrado. Inicializando um novo repositório..."
        git init | Out-Null
        Write-Host "Repositório Git criado com sucesso."
    }
    else {
        Write-Host "Repositório Git já existe."
    }

    git add .

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        git commit -m "Backup automático FortiGate - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    }
    catch {
        # Aqui você pode ignorar erros, por exemplo quando não há alterações para commitar
        Write-Host "Nada novo para commitar ou erro no commit." -ForegroundColor Yellow
    }

    Write-Host "Backup commitado no repositório Git." -ForegroundColor Green
}
catch {
    Write-Host "Erro ao executar comandos Git: $_" -ForegroundColor Red
}
Set-Location -Path $CurrentDir
