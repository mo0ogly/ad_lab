<#
.SYNOPSIS
    Cree la VM Hyper-V pour le lab Active Directory
.DESCRIPTION
    - Active Hyper-V si necessaire
    - Cree un vSwitch EXTERNE (acces Internet direct via carte physique)
    - Cree la VM avec les specs recommandees
    - Monte l'ISO Windows Server 2022
    - Configure la carte reseau en mode Untagged (pas de VLAN)
.NOTES
    Executer en tant qu'Administrateur sur l'HOTE Windows 11
#>

param(
    [string]$VMName = "DC01-LAB",
    [string]$SwitchName = "LabSwitch",
    [int64]$RAM = 4GB,
    [int]$CPU = 4,
    [int64]$DiskSize = 80GB,
    [string]$ISOPath = ""
)

$ErrorActionPreference = "Stop"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Creation de la VM Hyper-V" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- 1. Vérifier/Activer Hyper-V ---
Write-Host "`n[1/5] Verification de Hyper-V..." -ForegroundColor Yellow
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V
if ($hyperv.State -ne "Enabled") {
    Write-Host "  -> Activation de Hyper-V (redemarrage requis apres)..." -ForegroundColor Red
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -NoRestart
    Write-Host "  -> Hyper-V active. REDEMARREZ puis relancez ce script." -ForegroundColor Red
    Read-Host "Appuyez sur Entree pour quitter"
    exit 0
}
Write-Host "  -> Hyper-V est actif." -ForegroundColor Green

# --- 2. Demander l'ISO si non fourni ---
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    Write-Host "`n[INFO] Vous avez besoin de l'ISO Windows Server 2022 Evaluation." -ForegroundColor Yellow
    Write-Host "  Telechargez-la depuis: https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022" -ForegroundColor Yellow
    $ISOPath = Read-Host "`nEntrez le chemin complet de l'ISO Windows Server"
    if (-not (Test-Path $ISOPath)) {
        Write-Host "ERREUR: Fichier ISO introuvable: $ISOPath" -ForegroundColor Red
        exit 1
    }
}

# --- 3. Créer le Virtual Switch ---
Write-Host "`n[2/5] Configuration du reseau virtuel..." -ForegroundColor Yellow
$existingSwitch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
if (-not $existingSwitch) {
    # Switch EXTERNE pour acces direct au reseau physique + Internet
    # Trouver la carte reseau physique active
    $physicalAdapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" }
    if ($physicalAdapters.Count -eq 0) {
        Write-Host "  ERREUR: Aucune carte reseau physique active!" -ForegroundColor Red
        exit 1
    }
    $selectedAdapter = $physicalAdapters | Select-Object -First 1
    Write-Host "  -> Carte physique: $($selectedAdapter.Name) ($($selectedAdapter.InterfaceDescription))" -ForegroundColor Gray

    New-VMSwitch -Name $SwitchName -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true
    Write-Host "  -> vSwitch '$SwitchName' cree (External - acces Internet direct)." -ForegroundColor Green
} else {
    Write-Host "  -> vSwitch '$SwitchName' existe deja (Type: $($existingSwitch.SwitchType))." -ForegroundColor Green
}

# --- 4. Créer la VM ---
Write-Host "`n[3/5] Creation de la VM '$VMName'..." -ForegroundColor Yellow
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    Write-Host "  -> La VM '$VMName' existe deja. Suppression..." -ForegroundColor Yellow
    Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
    Remove-VM -Name $VMName -Force
    # Supprimer les fichiers
    $vmPath = "C:\HyperV\$VMName"
    if (Test-Path $vmPath) { Remove-Item $vmPath -Recurse -Force }
}

$vmPath = "C:\HyperV\$VMName"
$vhdPath = "$vmPath\$VMName.vhdx"

# Créer la VM
New-VM -Name $VMName `
    -MemoryStartupBytes $RAM `
    -Generation 2 `
    -NewVHDPath $vhdPath `
    -NewVHDSizeBytes $DiskSize `
    -SwitchName $SwitchName `
    -Path $vmPath

Write-Host "  -> VM creee." -ForegroundColor Green

# --- 5. Configurer la VM ---
Write-Host "`n[4/5] Configuration de la VM..." -ForegroundColor Yellow

# CPU
Set-VMProcessor -VMName $VMName -Count $CPU

# Mémoire dynamique
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes $RAM -StartupBytes $RAM

# Désactiver Secure Boot pour compatibilité (ou garder avec le template MS)
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftWindows

# Activer nested virtualization (pour Hyper-V dans la VM si besoin)
Set-VMProcessor -VMName $VMName -ExposeVirtualizationExtensions $true

# S'assurer que la carte reseau est en mode Untagged (pas de VLAN)
# Ceci evite le probleme d'isolation reseau rencontre frequemment
Set-VMNetworkAdapterVlan -VMName $VMName -Untagged
Write-Host "  -> Carte reseau: mode Untagged (pas de VLAN)." -ForegroundColor Green

# Monter l'ISO
Add-VMDvdDrive -VMName $VMName -Path $ISOPath

# Configurer l'ordre de boot : DVD en premier
$dvd = Get-VMDvdDrive -VMName $VMName
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd

# Activer les checkpoints automatiques
Set-VM -VMName $VMName -AutomaticCheckpointsEnabled $true

# Activer les Integration Services
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"

Write-Host "  -> Configuration terminee." -ForegroundColor Green

# --- Résumé ---
Write-Host "`n[5/5] Resume de la VM creee:" -ForegroundColor Yellow
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Nom          : $VMName"
Write-Host "  RAM          : $($RAM / 1GB) GB (dynamique, min 2GB)"
Write-Host "  CPU          : $CPU vCPUs"
Write-Host "  Disque       : $($DiskSize / 1GB) GB"
Write-Host "  Reseau       : $SwitchName (External - acces Internet direct)"
Write-Host "  ISO          : $ISOPath"
Write-Host "  Nested Virt  : Oui"
Write-Host "  Emplacement  : $vmPath"
Write-Host "================================================" -ForegroundColor Cyan

Write-Host "`n[NEXT] Pour demarrer la VM:" -ForegroundColor Green
Write-Host "  Start-VM -Name '$VMName'"
Write-Host "  vmconnect localhost '$VMName'"
Write-Host "`n[NEXT] Apres l'installation de Windows Server:" -ForegroundColor Green
Write-Host "  1. Choisir 'Desktop Experience'"
Write-Host "  2. Configurer IP statique: 192.168.0.10/24, GW: 192.168.0.1, DNS: 127.0.0.1"
Write-Host "  3. Renommer le serveur: Rename-Computer -NewName 'DC01' -Restart"
Write-Host "  4. Lancer le script 02_Install-ADDS.ps1"

Read-Host "`nAppuyez sur Entree pour terminer"
