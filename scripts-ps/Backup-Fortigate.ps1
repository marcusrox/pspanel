<#
.SYNOPSIS
    Realiza backup lógico do FortiGate via SSH e versiona os arquivos com Git.

.DESCRIPTION
    Garante o módulo Posh-SSH, conecta ao firewall, executa vários comandos "show" e grava saídas
    em texto em C:\FortiGate-Backup (ou pasta configurada), incluindo full-configuration. Opcionalmente
    inicializa ou atualiza um repositório Git nessa pasta.

.PARAMETER FortiUser
    Usuário SSH do FortiGate.

.PARAMETER FortiPassword
    Senha SSH do FortiGate.

.PARAMETER FortiHost
    IP ou hostname do FortiGate. Valor padrão: 10.35.0.1.

.EXAMPLE
    .\Backup-Fortigate.ps1 -FortiUser admin -FortiPassword "senha"

.EXAMPLE
    .\Backup-Fortigate.ps1 -FortiHost 10.35.0.2 -FortiUser admin -FortiPassword "senha"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$FortiUser,

    [Parameter(Mandatory = $true)]
    [string]$FortiPassword,

    [Parameter(Mandatory = $false)]
    [string]$FortiHost = "10.35.0.1"
)

# Requer o módulo Posh-SSH 4.x prerelease ou superior para compatibilidade SSH com o FortiGate.
# Instale com: Install-Module -Name Posh-SSH -AllowPrerelease -Force

# === GARANTE QUE O MÓDULO POSH-SSH ESTEJA INSTALADO E CARREGADO ===
$RequiredPoshSshVersion = [version]"4.0.0"
$InstalledPoshSsh = Get-Module -ListAvailable -Name Posh-SSH |
    Sort-Object Version -Descending |
    Select-Object -First 1

if ($null -eq $InstalledPoshSsh -or $InstalledPoshSsh.Version -lt $RequiredPoshSshVersion) {
    Write-Host "Módulo Posh-SSH 4.x não encontrado. Instalando versão prerelease..."
    try {
        Install-Module -Name Posh-SSH -AllowPrerelease -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
        Write-Host "Módulo Posh-SSH instalado com sucesso."
    }
    catch {
        Write-Error "Erro ao instalar o módulo Posh-SSH: $_"
        exit 1
    }
}

try {
    Import-Module Posh-SSH -Force -ErrorAction Stop
}
catch {
    Write-Error "Erro ao carregar o módulo Posh-SSH: $_"
    exit 1
}

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
try {
    $session = New-SSHSession -ComputerName $FortiHost -Credential $Credential -AcceptKey -Force -ErrorAction Stop
}
catch {
    Write-Error "Erro ao conectar no FortiGate: $_"
    exit 1
}

if ($null -eq $session -or $null -eq $session.SessionId) {
    Write-Error "Erro ao conectar no FortiGate: sessão SSH não foi criada."
    exit 1
}

$SessionId = $session.SessionId

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
    $output = Invoke-SSHCommand -SessionId $SessionId -Command "show $block"
    $safeName = $block -replace "\s+", "-"   # Substitui espaços por hífens
    $fileName = "${BackupDir}\$safeName.txt"
    $output.Output | Out-File -FilePath $fileName -Encoding utf8 -Force
}

# === EXTRAÇÃO DO FULL CONFIGURATION ===
Write-Host "Extraindo: full-configuration..."
$fullConfig = Invoke-SSHCommand -SessionId $SessionId -Command "show full-configuration"
$fullFileName = "${BackupDir}\full-configuration.txt"
$fullConfig.Output | Out-File -FilePath $fullFileName -Encoding utf8 -Force

# === FINALIZA SESSÃO ===
Remove-SSHSession -SessionId $SessionId

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
