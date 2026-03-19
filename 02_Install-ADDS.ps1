#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe Active Directory Domain Services et promeut en Domain Controller
.DESCRIPTION
    - Configure l'IP statique
    - Installe AD DS + DNS
    - Promeut le serveur en DC pour lab.local
    - Configure DHCP
    - Redémarre automatiquement
.NOTES
    Exécuter DANS la VM Windows Server, en tant qu'Administrateur
#>

param(
    [string]$DomainName     = "lab.local",
    [string]$NetBIOS        = "LAB",
    [string]$ServerIP       = "192.168.0.10",
    [int]$PrefixLength      = 24,
    [string]$Gateway        = "192.168.0.1",
    [string]$SafePassword   = "",
    [string]$DHCPScopeStart = "192.168.0.100",
    [string]$DHCPScopeEnd   = "192.168.0.200"
)

# Charger config si pas de mot de passe fourni
if (-not $SafePassword) {
    $configPath = Join-Path $PSScriptRoot "config.ps1"
    if (Test-Path $configPath) { . $configPath; $SafePassword = $LabPassword }
    else { Write-Host "[ERREUR] Mot de passe requis. Copiez config.example.ps1 en config.ps1" -ForegroundColor Red; exit 1 }
}

$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Installation Active Directory" -ForegroundColor Cyan
Write-Host "  Domaine: $DomainName" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- 1. Configuration réseau ---
Write-Host "`n[1/6] Configuration IP statique..." -ForegroundColor Yellow

# Trouver l'adaptateur principal (premier connecté)
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1

if ($adapter) {
    # Supprimer la config DHCP existante
    Remove-NetIPAddress -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
    Remove-NetRoute -InterfaceIndex $adapter.ifIndex -Confirm:$false -ErrorAction SilentlyContinue

    # IP statique
    New-NetIPAddress -InterfaceIndex $adapter.ifIndex `
        -IPAddress $ServerIP `
        -PrefixLength $PrefixLength `
        -DefaultGateway $Gateway

    # DNS pointe vers lui-même
    Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses @("127.0.0.1", "8.8.8.8")

    Write-Host "  -> IP: $ServerIP/$PrefixLength, GW: $Gateway, DNS: 127.0.0.1" -ForegroundColor Green
} else {
    Write-Host "  -> ERREUR: Aucun adaptateur reseau actif trouve!" -ForegroundColor Red
    exit 1
}

# --- 2. Renommer le serveur ---
Write-Host "`n[2/6] Verification du nom du serveur..." -ForegroundColor Yellow
$currentName = $env:COMPUTERNAME
if ($currentName -ne "DC01") {
    Write-Host "  -> Renommage en 'DC01'... (redemarrage apres)" -ForegroundColor Yellow
    Rename-Computer -NewName "DC01" -Force
    Write-Host "  -> Serveur renomme. Redemarrage dans 10s, puis relancez ce script." -ForegroundColor Red
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit 0
}
Write-Host "  -> Nom OK: $currentName" -ForegroundColor Green

# --- 3. Installer AD DS ---
Write-Host "`n[3/6] Installation du role AD DS..." -ForegroundColor Yellow
$addsInstalled = Get-WindowsFeature -Name AD-Domain-Services
if (-not $addsInstalled.Installed) {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature
    Write-Host "  -> AD DS installe." -ForegroundColor Green
} else {
    Write-Host "  -> AD DS deja installe." -ForegroundColor Green
}

# --- 4. Promouvoir en Domain Controller ---
Write-Host "`n[4/6] Promotion en Domain Controller..." -ForegroundColor Yellow

$domain = Get-ADDomain -ErrorAction SilentlyContinue
if (-not $domain) {
    $securePassword = ConvertTo-SecureString $SafePassword -AsPlainText -Force

    Install-ADDSForest `
        -DomainName $DomainName `
        -DomainNetBIOSName $NetBIOS `
        -ForestMode "WinThreshold" `
        -DomainMode "WinThreshold" `
        -InstallDns:$true `
        -CreateDnsDelegation:$false `
        -DatabasePath "C:\Windows\NTDS" `
        -LogPath "C:\Windows\NTDS" `
        -SysvolPath "C:\Windows\SYSVOL" `
        -SafeModeAdministratorPassword $securePassword `
        -NoRebootOnCompletion:$false `
        -Force:$true

    Write-Host "  -> Foret '$DomainName' creee. Le serveur va redemarrer." -ForegroundColor Green
    Write-Host "  -> Apres redemarrage, lancez 03_Install-Services.ps1" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "  -> Domaine '$($domain.DNSRoot)' deja configure." -ForegroundColor Green
}

# --- 5. Configurer DNS (zones supplémentaires) ---
Write-Host "`n[5/6] Configuration DNS avancee..." -ForegroundColor Yellow

# Zone de recherche inversee
$reverseZone = Get-DnsServerZone -Name "0.168.192.in-addr.arpa" -ErrorAction SilentlyContinue
if (-not $reverseZone) {
    Add-DnsServerPrimaryZone -NetworkID "192.168.0.0/24" -ReplicationScope Domain
    Write-Host "  -> Zone inversee 192.168.0.0/24 creee." -ForegroundColor Green
} else {
    Write-Host "  -> Zone inversee existe deja." -ForegroundColor Green
}

# Enregistrement PTR pour le DC
Add-DnsServerResourceRecordPtr -ZoneName "0.168.192.in-addr.arpa" `
    -Name "10" -PtrDomainName "dc01.$DomainName" -ErrorAction SilentlyContinue

# Forwarders DNS
Set-DnsServerForwarder -IPAddress @("8.8.8.8", "1.1.1.1") -ErrorAction SilentlyContinue
Write-Host "  -> Forwarders: 8.8.8.8, 1.1.1.1" -ForegroundColor Green

# --- 6. Installer et configurer DHCP ---
Write-Host "`n[6/6] Installation et configuration DHCP..." -ForegroundColor Yellow

$dhcpInstalled = Get-WindowsFeature -Name DHCP
if (-not $dhcpInstalled.Installed) {
    Install-WindowsFeature -Name DHCP -IncludeManagementTools
}

# Autoriser le serveur DHCP dans AD
Add-DhcpServerInDC -DnsName "dc01.$DomainName" -IPAddress $ServerIP -ErrorAction SilentlyContinue

# Créer le scope
$existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq "LabScope" }
if (-not $existingScope) {
    Add-DhcpServerv4Scope -Name "LabScope" `
        -StartRange $DHCPScopeStart `
        -EndRange $DHCPScopeEnd `
        -SubnetMask "255.255.255.0" `
        -LeaseDuration (New-TimeSpan -Days 8) `
        -State Active

    # Options DHCP
    Set-DhcpServerv4OptionValue -ScopeId "192.168.0.0" `
        -Router $Gateway `
        -DnsServer $ServerIP `
        -DnsDomain $DomainName

    Write-Host "  -> DHCP scope $DHCPScopeStart - $DHCPScopeEnd cree." -ForegroundColor Green
} else {
    Write-Host "  -> DHCP scope existe deja." -ForegroundColor Green
}

# Supprimer l'alerte de configuration DHCP
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\ServerManager\Roles\12" -Name "ConfigurationState" -Value 2 -ErrorAction SilentlyContinue

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  AD DS + DNS + DHCP installes avec succes!" -ForegroundColor Green
Write-Host "  Domaine : $DomainName" -ForegroundColor Green
Write-Host "  DC      : dc01.$DomainName ($ServerIP)" -ForegroundColor Green
Write-Host "  DHCP    : $DHCPScopeStart - $DHCPScopeEnd" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "`n[NEXT] Lancez 03_Install-Services.ps1 pour les services supplementaires." -ForegroundColor Yellow

Read-Host "`nAppuyez sur Entree pour terminer"
