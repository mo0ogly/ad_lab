param(
    [string]$VMName     = "DC01-LAB",
    [string]$SwitchName = "LabSwitch",
    [string]$ISOPath    = "",
    [string]$VMBasePath = "C:\HyperV"
)

# Demander l'ISO si non fournie
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    Write-Host "=== REBUILD COMPLET ===" -ForegroundColor Cyan
    Write-Host "ISO non specifiee. Fichiers detectes:" -ForegroundColor Yellow
    Get-ChildItem "$env:USERPROFILE\Desktop\*.iso", "$env:USERPROFILE\Downloads\*.iso" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $($_.FullName)" }
    $ISOPath = Read-Host "Chemin complet de l'ISO Windows Server"
    if (-not (Test-Path $ISOPath)) {
        Write-Host "ERREUR: ISO introuvable!" -ForegroundColor Red
        pause; exit
    }
}

Write-Host "=== REBUILD COMPLET ===" -ForegroundColor Cyan

# 1. Supprimer l'ancienne VM
Write-Host "[1] Suppression ancienne VM..." -ForegroundColor Yellow
$existing = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.State -ne "Off") { Stop-VM -Name $VMName -TurnOff -Force; Start-Sleep 2 }
    Remove-VM -Name $VMName -Force
    Write-Host "  -> VM supprimee." -ForegroundColor Green
}
if (Test-Path "$VMBasePath\$VMName") {
    Remove-Item "$VMBasePath\$VMName" -Recurse -Force
    Write-Host "  -> Fichiers supprimes." -ForegroundColor Green
}

# 2. Verifier ISO
Write-Host "`n[2] Verification ISO..." -ForegroundColor Yellow
$isoSize = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
Write-Host "  -> ISO OK: $isoSize GB" -ForegroundColor Green

# 3. Verifier/creer le switch
Write-Host "`n[3] Switch reseau..." -ForegroundColor Yellow
if (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    $physNIC = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    if ($physNIC) {
        New-VMSwitch -Name $SwitchName -NetAdapterName $physNIC.Name -AllowManagementOS $true
        Write-Host "  -> Switch externe cree sur $($physNIC.Name)" -ForegroundColor Green
    } else {
        New-VMSwitch -Name $SwitchName -SwitchType Internal
        Write-Host "  -> Switch interne cree (pas de NIC physique detectee)" -ForegroundColor Yellow
    }
} else {
    Write-Host "  -> Switch existe." -ForegroundColor Green
}

# 4. Creer la VM (Generation 2 pour UEFI + Secure Boot)
Write-Host "`n[4] Creation VM Generation 2..." -ForegroundColor Yellow
$vhdPath = "$VMBasePath\$VMName\$VMName.vhdx"

New-VM -Name $VMName `
    -MemoryStartupBytes 4GB `
    -Generation 2 `
    -NewVHDPath $vhdPath `
    -NewVHDSizeBytes 80GB `
    -SwitchName $SwitchName `
    -Path "$VMBasePath\$VMName"

Write-Host "  -> VM creee (Gen 2)." -ForegroundColor Green

# 5. Configurer
Write-Host "`n[5] Configuration..." -ForegroundColor Yellow
Set-VMProcessor -VMName $VMName -Count 4
Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 2GB -MaximumBytes 4GB -StartupBytes 4GB
Set-VMFirmware -VMName $VMName -SecureBootTemplate MicrosoftWindows
Set-VMNetworkAdapterVlan -VMName $VMName -Untagged

$dvd = Add-VMDvdDrive -VMName $VMName -Path $ISOPath -PassThru
$hdd = Get-VMHardDiskDrive -VMName $VMName
Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd

Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface"
Write-Host "  -> 4 vCPU, 4GB RAM, Secure Boot, Boot: DVD > HDD" -ForegroundColor Green

# 6. Verification finale
Write-Host "`n[6] Verification finale..." -ForegroundColor Yellow
$vm = Get-VM -Name $VMName
$dvdInfo = Get-VMDvdDrive -VMName $VMName
Write-Host "  VM     : $($vm.Name) | Gen $($vm.Generation) | $($vm.State)" -ForegroundColor Cyan
Write-Host "  DVD    : $($dvdInfo.Path)" -ForegroundColor Cyan
Write-Host "  RAM    : $($vm.MemoryStartup/1GB) GB" -ForegroundColor Cyan
Write-Host "  CPU    : $($vm.ProcessorCount)" -ForegroundColor Cyan

# 7. Demarrer
Write-Host "`n[7] Demarrage..." -ForegroundColor Yellow
Start-VM -Name $VMName
Write-Host "  -> VM demarree!" -ForegroundColor Green

Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  Console VM en cours d'ouverture..." -ForegroundColor Cyan
Write-Host "  APPUYEZ SUR UNE TOUCHE pour booter sur DVD!" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Cyan

vmconnect localhost $VMName
pause
