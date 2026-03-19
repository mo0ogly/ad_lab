#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploie une 2e VM pour RODC (lab.local) + 3e VM pour Trust (partner.local)
.DESCRIPTION
    Ce script cree l'infrastructure supplementaire pour couvrir les collecteurs :
      - Collect-RODCConfig    → DC02 promu en RODC dans lab.local
      - Collect-Trusts        → DC-PARTNER dans foret partner.local + trust bidirectionnel

    ETAPES :
    Phase A — RODC (DC02-LAB) :
      A1. Creer VM DC02-LAB sur l'hote Hyper-V
      A2. Generer le script d'installation AD DS RODC (a executer dans la VM)

    Phase B — Partner Forest (DC-PARTNER) :
      B1. Creer VM DC-PARTNER sur l'hote Hyper-V
      B2. Generer le script d'installation foret partner.local
      B3. Generer le script d'etablissement du trust (a executer sur DC01)

    Executer sur l'HOTE Windows 11 (pas dans la VM).
.NOTES
    Pre-requis : 01_Create-VM.ps1 et 02_Install-ADDS.ps1 deja executes pour DC01.
    ISO Windows Server 2022 necessaire.
#>

param(
    [string]$SwitchName   = "LabSwitch",
    [string]$ISOPath      = "",
    [int64]$RAM           = 2GB,
    [int]$CPU             = 2,
    [int64]$DiskSize      = 60GB,
    [string]$OutputScripts = "C:\HyperV\setup-scripts"
)

$ErrorActionPreference = "Stop"

# ============================================================
# Verification pre-requis
# ============================================================
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD — Deploiement RODC + Partner Forest" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Verifier Hyper-V
if (-not (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V).State -eq "Enabled") {
    Write-Host "[ERREUR] Hyper-V n'est pas active. Executez d'abord 01_Create-VM.ps1" -ForegroundColor Red
    exit 1
}

# Verifier le vSwitch
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $switch) {
    Write-Host "[ERREUR] vSwitch '$SwitchName' introuvable. Executez d'abord 01_Create-VM.ps1" -ForegroundColor Red
    exit 1
}

# Demander ISO si non fourni
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    $ISOPath = Read-Host "Chemin de l'ISO Windows Server 2022"
    if (-not (Test-Path $ISOPath)) {
        Write-Host "[ERREUR] ISO introuvable : $ISOPath" -ForegroundColor Red
        exit 1
    }
}

# Creer le dossier pour les scripts generes
New-Item -Path $OutputScripts -ItemType Directory -Force | Out-Null

# ============================================================
# PHASE A — RODC (DC02-LAB)
# ============================================================
Write-Host "`n========== PHASE A : RODC (DC02-LAB) ==========" -ForegroundColor Cyan

$vmRODC = "DC02-LAB"
$rodcIP = "192.168.0.11"
$rodcPath = "C:\HyperV\$vmRODC"

# A1. Creer la VM
Write-Host "[A1] Creation de la VM $vmRODC..." -ForegroundColor Yellow

if (Get-VM -Name $vmRODC -ErrorAction SilentlyContinue) {
    Write-Host "  [SKIP] VM $vmRODC existe deja" -ForegroundColor DarkGray
} else {
    New-Item -Path $rodcPath -ItemType Directory -Force | Out-Null

    New-VM -Name $vmRODC `
        -MemoryStartupBytes $RAM `
        -Generation 2 `
        -NewVHDPath "$rodcPath\$vmRODC.vhdx" `
        -NewVHDSizeBytes $DiskSize `
        -SwitchName $SwitchName `
        -Path $rodcPath

    Set-VMProcessor -VMName $vmRODC -Count $CPU
    Set-VMMemory    -VMName $vmRODC -DynamicMemoryEnabled $true -MinimumBytes 1GB -MaximumBytes $RAM -StartupBytes $RAM
    Set-VMFirmware  -VMName $vmRODC -SecureBootTemplate MicrosoftWindows
    Set-VMNetworkAdapterVlan -VMName $vmRODC -Untagged

    $dvd = Add-VMDvdDrive -VMName $vmRODC -Path $ISOPath -PassThru
    $hdd = Get-VMHardDiskDrive -VMName $vmRODC
    Set-VMFirmware -VMName $vmRODC -BootOrder $dvd, $hdd

    Enable-VMIntegrationService -VMName $vmRODC -Name "Guest Service Interface"

    Write-Host "  [OK] VM $vmRODC creee (${CPU} vCPU, $($RAM/1GB) GB RAM, $($DiskSize/1GB) GB disk)" -ForegroundColor Green
}

# A2. Generer le script d'installation RODC
$rodcScript = @'
#Requires -RunAsAdministrator
# ================================================================
# Script a executer DANS la VM DC02-LAB apres installation Windows
# Promeut DC02 en RODC dans lab.local
# ================================================================

param(
    [string]$DomainName   = "lab.local",
    [string]$DC01IP       = "192.168.0.10",
    [string]$RODCIP       = "192.168.0.11",
    [int]$PrefixLength    = 24,
    [string]$Gateway      = "192.168.0.1",
    [string]$SafePassword = "Cim22091956!!??"
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  DC02-LAB — Installation RODC" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# --- 1. IP Statique ---
Write-Host "`n[1/4] Configuration reseau..." -ForegroundColor Yellow
$nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $RODCIP -PrefixLength $PrefixLength -DefaultGateway $Gateway
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @($DC01IP, "127.0.0.1")
Write-Host "  [OK] IP = $RODCIP, DNS = $DC01IP" -ForegroundColor Green

# --- 2. Renommer la machine ---
Write-Host "`n[2/4] Renommage en DC02..." -ForegroundColor Yellow
if ($env:COMPUTERNAME -ne "DC02") {
    Rename-Computer -NewName "DC02" -Force
    Write-Host "  [OK] Renomme en DC02 — REDEMARRAGE REQUIS" -ForegroundColor Yellow
    Write-Host "  Relancez ce script apres redemarrage." -ForegroundColor Yellow
    Restart-Computer -Force
    exit
}
Write-Host "  [OK] Nom = DC02" -ForegroundColor Green

# --- 3. Installer AD DS ---
Write-Host "`n[3/4] Installation du role AD DS..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools -IncludeAllSubFeature
Write-Host "  [OK] Role AD DS installe" -ForegroundColor Green

# --- 4. Promouvoir en RODC ---
Write-Host "`n[4/4] Promotion en RODC dans $DomainName..." -ForegroundColor Yellow

$cred = Get-Credential -Message "Entrez les credentials Domain Admin de $DomainName (LAB\Administrator)"

Install-ADDSDomainController `
    -DomainName $DomainName `
    -Credential $cred `
    -ReadOnlyReplica:$true `
    -InstallDns:$true `
    -NoGlobalCatalog:$false `
    -SiteName "Default-First-Site-Name" `
    -DatabasePath "C:\Windows\NTDS" `
    -LogPath "C:\Windows\NTDS" `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $SafePassword -AsPlainText -Force) `
    -NoRebootOnCompletion:$false `
    -Force:$true

Write-Host "`n[OK] DC02 promu en RODC dans $DomainName" -ForegroundColor Green
Write-Host "La machine va redemarrer automatiquement." -ForegroundColor Yellow
'@

Set-Content -Path "$OutputScripts\A2_Install-RODC.ps1" -Value $rodcScript -Encoding UTF8
Write-Host "  [OK] Script genere : $OutputScripts\A2_Install-RODC.ps1" -ForegroundColor Green

# ============================================================
# PHASE B — Partner Forest (DC-PARTNER)
# ============================================================
Write-Host "`n========== PHASE B : Partner Forest (DC-PARTNER) ==========" -ForegroundColor Cyan

$vmPartner = "DC-PARTNER"
$partnerIP = "192.168.0.12"
$partnerPath = "C:\HyperV\$vmPartner"

# B1. Creer la VM
Write-Host "[B1] Creation de la VM $vmPartner..." -ForegroundColor Yellow

if (Get-VM -Name $vmPartner -ErrorAction SilentlyContinue) {
    Write-Host "  [SKIP] VM $vmPartner existe deja" -ForegroundColor DarkGray
} else {
    New-Item -Path $partnerPath -ItemType Directory -Force | Out-Null

    New-VM -Name $vmPartner `
        -MemoryStartupBytes $RAM `
        -Generation 2 `
        -NewVHDPath "$partnerPath\$vmPartner.vhdx" `
        -NewVHDSizeBytes $DiskSize `
        -SwitchName $SwitchName `
        -Path $partnerPath

    Set-VMProcessor -VMName $vmPartner -Count $CPU
    Set-VMMemory    -VMName $vmPartner -DynamicMemoryEnabled $true -MinimumBytes 1GB -MaximumBytes $RAM -StartupBytes $RAM
    Set-VMFirmware  -VMName $vmPartner -SecureBootTemplate MicrosoftWindows
    Set-VMNetworkAdapterVlan -VMName $vmPartner -Untagged

    $dvd = Add-VMDvdDrive -VMName $vmPartner -Path $ISOPath -PassThru
    $hdd = Get-VMHardDiskDrive -VMName $vmPartner
    Set-VMFirmware -VMName $vmPartner -BootOrder $dvd, $hdd

    Enable-VMIntegrationService -VMName $vmPartner -Name "Guest Service Interface"

    Write-Host "  [OK] VM $vmPartner creee (${CPU} vCPU, $($RAM/1GB) GB RAM, $($DiskSize/1GB) GB disk)" -ForegroundColor Green
}

# B2. Generer le script d'installation partner.local
$partnerScript = @'
#Requires -RunAsAdministrator
# ================================================================
# Script a executer DANS la VM DC-PARTNER apres installation Windows
# Cree la foret partner.local (domaine partenaire pour trust)
# ================================================================

param(
    [string]$DomainName   = "partner.local",
    [string]$NetBIOS      = "PARTNER",
    [string]$ServerIP     = "192.168.0.12",
    [int]$PrefixLength    = 24,
    [string]$Gateway      = "192.168.0.1",
    [string]$DC01IP       = "192.168.0.10",
    [string]$SafePassword = "Cim22091956!!??"
)

$ErrorActionPreference = "Stop"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  DC-PARTNER — Foret partner.local" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# --- 1. IP Statique ---
Write-Host "`n[1/5] Configuration reseau..." -ForegroundColor Yellow
$nic = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Remove-NetIPAddress -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
Remove-NetRoute -InterfaceIndex $nic.ifIndex -Confirm:$false -ErrorAction SilentlyContinue
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $ServerIP -PrefixLength $PrefixLength -DefaultGateway $Gateway
# DNS : soi-meme d'abord, puis DC01 pour resolution cross-forest
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses @("127.0.0.1", $DC01IP)
Write-Host "  [OK] IP = $ServerIP, DNS = 127.0.0.1 + $DC01IP" -ForegroundColor Green

# --- 2. Renommer ---
Write-Host "`n[2/5] Renommage en DC-PARTNER..." -ForegroundColor Yellow
if ($env:COMPUTERNAME -ne "DC-PARTNER") {
    Rename-Computer -NewName "DC-PARTNER" -Force
    Write-Host "  [OK] Renomme — REDEMARRAGE REQUIS. Relancez apres." -ForegroundColor Yellow
    Restart-Computer -Force
    exit
}

# --- 3. Installer AD DS ---
Write-Host "`n[3/5] Installation du role AD DS + DNS..." -ForegroundColor Yellow
Install-WindowsFeature -Name AD-Domain-Services, DNS -IncludeManagementTools -IncludeAllSubFeature
Write-Host "  [OK] Roles installes" -ForegroundColor Green

# --- 4. Creer la foret partner.local ---
Write-Host "`n[4/5] Creation de la foret $DomainName..." -ForegroundColor Yellow
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
    -SafeModeAdministratorPassword (ConvertTo-SecureString $SafePassword -AsPlainText -Force) `
    -NoRebootOnCompletion:$false `
    -Force:$true

# (Machine reboote ici)
'@

Set-Content -Path "$OutputScripts\B2_Install-PartnerForest.ps1" -Value $partnerScript -Encoding UTF8
Write-Host "  [OK] Script genere : $OutputScripts\B2_Install-PartnerForest.ps1" -ForegroundColor Green

# B3. Generer le script de post-config partner + DNS conditionnel
$partnerPostScript = @'
#Requires -RunAsAdministrator
# ================================================================
# Script a executer DANS la VM DC-PARTNER apres promotion
# Configure DNS conditionnel + peuple quelques objets
# ================================================================

param(
    [string]$DC01IP = "192.168.0.10"
)

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  DC-PARTNER — Post-Configuration" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# DNS conditionnel vers lab.local
Write-Host "[1/2] DNS conditionnel lab.local -> $DC01IP" -ForegroundColor Yellow
Add-DnsServerConditionalForwarderZone -Name "lab.local" -MasterServers $DC01IP -ReplicationScope Forest
Write-Host "  [OK]" -ForegroundColor Green

# Creer quelques utilisateurs pour simuler un domaine partenaire
Write-Host "[2/2] Utilisateurs partenaires..." -ForegroundColor Yellow
$securePwd = ConvertTo-SecureString "Partner2024!" -AsPlainText -Force
@("partner.admin", "partner.user1", "partner.svc") | ForEach-Object {
    New-ADUser -Name $_ -SamAccountName $_ -UserPrincipalName "$_@partner.local" `
        -AccountPassword $securePwd -Enabled $true -PasswordNeverExpires $true `
        -ErrorAction SilentlyContinue
}
# Mettre partner.admin dans Domain Admins
Add-ADGroupMember "Domain Admins" -Members "partner.admin" -ErrorAction SilentlyContinue
Write-Host "  [OK] 3 utilisateurs crees dans partner.local" -ForegroundColor Green

Write-Host "`n[OK] DC-PARTNER pret. Executez maintenant B4 sur DC01." -ForegroundColor Green
'@

Set-Content -Path "$OutputScripts\B3_PostConfig-Partner.ps1" -Value $partnerPostScript -Encoding UTF8
Write-Host "  [OK] Script genere : $OutputScripts\B3_PostConfig-Partner.ps1" -ForegroundColor Green

# B4. Generer le script de trust (a executer sur DC01)
$trustScript = @'
#Requires -RunAsAdministrator
# ================================================================
# Script a executer SUR DC01 (lab.local)
# Etablit le trust bidirectionnel avec partner.local
# + injecte les anomalies detectees par Collect-Trusts.ps1
# ================================================================

param(
    [string]$PartnerDomain = "partner.local",
    [string]$PartnerDC_IP  = "192.168.0.12",
    [string]$TrustPassword = "TrustP@ss2024!"
)

$ErrorActionPreference = "Continue"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host "  DC01 — Trust + RODC Anomalies" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Cyan

# --- 1. DNS conditionnel vers partner.local ---
Write-Host "`n[1/5] DNS conditionnel partner.local -> $PartnerDC_IP" -ForegroundColor Yellow
Add-DnsServerConditionalForwarderZone -Name $PartnerDomain -MasterServers $PartnerDC_IP -ReplicationScope Forest -ErrorAction SilentlyContinue
Write-Host "  [OK]" -ForegroundColor Green

# Verifier la resolution DNS
Write-Host "  Test DNS..." -ForegroundColor DarkGray
$resolved = Resolve-DnsName "$PartnerDomain" -ErrorAction SilentlyContinue
if ($resolved) {
    Write-Host "  [OK] $PartnerDomain resolu" -ForegroundColor Green
} else {
    Write-Host "  [ERREUR] $PartnerDomain non resolu — verifiez le reseau" -ForegroundColor Red
    Write-Host "  Attendez 30 secondes et reessayez ou verifiez la connectivite avec DC-PARTNER" -ForegroundColor Yellow
}

# --- 2. Creer le trust bidirectionnel (External Trust, pas Forest Trust) ---
# On utilise un External Trust pour que le SID Filtering soit pertinent
Write-Host "`n[2/5] Creation du trust bidirectionnel avec $PartnerDomain..." -ForegroundColor Yellow

$partnerCred = Get-Credential -Message "Credentials Domain Admin de $PartnerDomain (PARTNER\Administrator)"

# Methode netdom (plus robuste que New-ADTrust pour cross-forest)
netdom trust $PartnerDomain /Domain:lab.local /Add /TwoWay /UserD:$($partnerCred.UserName) /PasswordD:$($partnerCred.GetNetworkCredential().Password) /UserO:Administrator /PasswordO:"Cim22091956!!??"

if ($LASTEXITCODE -eq 0) {
    Write-Host "  [OK] Trust bidirectionnel cree" -ForegroundColor Green
} else {
    Write-Host "  [ERREUR] netdom trust a echoue (code $LASTEXITCODE)" -ForegroundColor Red
    Write-Host "  Alternative: utilisez la console AD Domains and Trusts manuellement" -ForegroundColor Yellow
}

# --- 3. VULN: Desactiver SID Filtering (QUARANTINED_DOMAIN) ---
Write-Host "`n[3/5] Desactivation SID Filtering (injection SID cross-domain)..." -ForegroundColor Yellow
netdom trust $PartnerDomain /Domain:lab.local /Quarantine:No
Write-Host "  [OK] SID Filtering desactive (cross-domain SID injection possible)" -ForegroundColor Green

# --- 4. VULN: Activer TGT Delegation ---
Write-Host "`n[4/5] Activation TGT Delegation (unconstrained delegation cross-trust)..." -ForegroundColor Yellow
netdom trust $PartnerDomain /Domain:lab.local /EnableTgtDelegation:Yes
Write-Host "  [OK] TGT Delegation active (delegation non-contrainte cross-trust)" -ForegroundColor Green

# --- 5. VULN: Forcer encryption RC4 only (pas d'AES) ---
Write-Host "`n[5/5] Configuration chiffrement RC4 uniquement (pas d'AES)..." -ForegroundColor Yellow
# Modifier les supported encryption types du trust pour n'autoriser que RC4
# Bit 4 = RC4_HMAC_MD5 = 0x4
$trustDN = Get-ADObject -Filter "objectClass -eq 'trustedDomain' -and Name -eq '$PartnerDomain'" `
    -SearchBase "CN=System,$($(Get-ADDomain).DistinguishedName)" `
    -Properties msDSSupportedEncryptionTypes

if ($trustDN) {
    Set-ADObject $trustDN -Replace @{msDSSupportedEncryptionTypes = 4}  # RC4 only, no AES
    Write-Host "  [OK] Chiffrement trust = RC4 uniquement (AES desactive)" -ForegroundColor Green
} else {
    Write-Host "  [WARN] Trust object introuvable dans AD — configurez manuellement" -ForegroundColor Yellow
}

# --- RODC Anomalies (si DC02 est promu) ---
Write-Host "`n========== RODC Anomalies ==========" -ForegroundColor Cyan

$rodc = Get-ADDomainController -Filter {IsReadOnly -eq $true} -ErrorAction SilentlyContinue
if ($rodc) {
    Write-Host "[RODC] DC02 detecte : $($rodc.Name)" -ForegroundColor Green

    # VULN: Ajouter des comptes privilegies dans le Allowed RODC Password Replication
    $rodcComputer = Get-ADComputer $rodc.Name
    Set-ADComputer $rodcComputer -Replace @{
        "msDS-RevealOnDemandGroup" = @(
            "CN=Domain Admins,CN=Users,$($(Get-ADDomain).DistinguishedName)",
            "CN=Domain Users,CN=Users,$($(Get-ADDomain).DistinguishedName)",
            "CN=GRP_IT_Admins,OU=Groupes,$($(Get-ADDomain).DistinguishedName)"
        )
    } -ErrorAction SilentlyContinue
    Write-Host "  [OK] RODC PRP : Domain Admins + Domain Users dans Allowed List" -ForegroundColor Green
    Write-Host "  [VULN] Si DC02 est compromis, TOUS les hash sont exposes" -ForegroundColor Red
} else {
    Write-Host "[RODC] Aucun RODC detecte — executez d'abord A2_Install-RODC.ps1 dans DC02" -ForegroundColor Yellow
}

Write-Host "`n======================================" -ForegroundColor Cyan
Write-Host "  TRUST + RODC — Configuration terminee!" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  ANOMALIES INJECTEES :" -ForegroundColor Red
Write-Host "    [Trust] SID Filtering desactive (cross-domain SID injection)" -ForegroundColor Yellow
Write-Host "    [Trust] TGT Delegation active (unconstrained cross-trust)" -ForegroundColor Yellow
Write-Host "    [Trust] Chiffrement RC4 only (pas d'AES)" -ForegroundColor Yellow
Write-Host "    [RODC]  Domain Admins dans Allowed PRP (hash exposes)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Les collecteurs suivants trouveront maintenant des resultats :" -ForegroundColor Green
Write-Host "    Collect-Trusts.ps1       → T-TrustAES, T-TrustSIDFiltering, T-TrustTGTDelegation" -ForegroundColor White
Write-Host "    Collect-RODCConfig.ps1   → P-RODC-RevealGroup, P-RODC-AdminReplication" -ForegroundColor White
Write-Host ""
'@

Set-Content -Path "$OutputScripts\B4_Setup-Trust-Vulns.ps1" -Value $trustScript -Encoding UTF8
Write-Host "  [OK] Script genere : $OutputScripts\B4_Setup-Trust-Vulns.ps1" -ForegroundColor Green

# ============================================================
# RESUME FINAL
# ============================================================
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  VMs creees + scripts generes" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  PROCHAINES ETAPES :" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [RODC — DC02-LAB]" -ForegroundColor Magenta
Write-Host "    1. Demarrer la VM DC02-LAB et installer Windows Server 2022" -ForegroundColor White
Write-Host "    2. Copier et executer : $OutputScripts\A2_Install-RODC.ps1" -ForegroundColor White
Write-Host "       (Relancez apres chaque redemarrage)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  [PARTNER — DC-PARTNER]" -ForegroundColor Magenta
Write-Host "    3. Demarrer la VM DC-PARTNER et installer Windows Server 2022" -ForegroundColor White
Write-Host "    4. Copier et executer : $OutputScripts\B2_Install-PartnerForest.ps1" -ForegroundColor White
Write-Host "       (Relancez apres chaque redemarrage)" -ForegroundColor DarkGray
Write-Host "    5. Apres promotion, executer : $OutputScripts\B3_PostConfig-Partner.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  [TRUST + ANOMALIES — sur DC01]" -ForegroundColor Magenta
Write-Host "    6. Quand DC02 et DC-PARTNER sont operationnels :" -ForegroundColor White
Write-Host "       Executer sur DC01 : $OutputScripts\B4_Setup-Trust-Vulns.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  RESSOURCES REQUISES :" -ForegroundColor Yellow
Write-Host "    DC02-LAB   : $($RAM/1GB) GB RAM, $CPU vCPU, $($DiskSize/1GB) GB disk" -ForegroundColor White
Write-Host "    DC-PARTNER : $($RAM/1GB) GB RAM, $CPU vCPU, $($DiskSize/1GB) GB disk" -ForegroundColor White
Write-Host "    Total supplementaire : $($RAM*2/1GB) GB RAM" -ForegroundColor White
Write-Host ""

# Demarrer les VMs
$startVMs = Read-Host "Demarrer les VMs maintenant ? (O/N)"
if ($startVMs -eq "O" -or $startVMs -eq "o") {
    Start-VM -Name $vmRODC -ErrorAction SilentlyContinue
    Start-VM -Name $vmPartner -ErrorAction SilentlyContinue
    Write-Host "`n[OK] VMs demarrees. Installez Windows puis executez les scripts." -ForegroundColor Green
    vmconnect localhost $vmRODC
}
