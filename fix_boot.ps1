<#
.SYNOPSIS
    Corrige le boot de la VM DC01-LAB pour booter sur l'ISO
#>

param(
    [string]$VMName  = "DC01-LAB",
    [string]$ISOPath = ""
)

# Demander l'ISO si non fournie
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    Write-Host "=== Fix Boot VM ===" -ForegroundColor Cyan
    Write-Host "ISO non specifiee. Fichiers detectes:" -ForegroundColor Yellow
    Get-ChildItem "$env:USERPROFILE\Desktop\*.iso", "$env:USERPROFILE\Downloads\*.iso" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $($_.FullName)" }
    $ISOPath = Read-Host "Chemin complet de l'ISO Windows Server"
    if (-not (Test-Path $ISOPath)) {
        Write-Host "ERREUR: ISO introuvable!" -ForegroundColor Red
        pause; exit
    }
}

Write-Host "=== Fix Boot VM ===" -ForegroundColor Cyan

# Eteindre la VM
Write-Host "Arret de la VM..." -ForegroundColor Yellow
Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3

# Verifier/remonter l'ISO sur le DVD
Write-Host "Remontage de l'ISO..." -ForegroundColor Yellow
$dvd = Get-VMDvdDrive -VMName $VMName
if (-not $dvd) {
    Add-VMDvdDrive -VMName $VMName -Path $ISOPath
    Write-Host "  -> DVD ajoutee avec ISO." -ForegroundColor Green
} else {
    Set-VMDvdDrive -VMName $VMName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $ISOPath
    Write-Host "  -> ISO remontee: $ISOPath" -ForegroundColor Green
}

# Reconfigurer le boot order : DVD en premier
Write-Host "Configuration boot order (DVD first)..." -ForegroundColor Yellow
$dvd = Get-VMDvdDrive -VMName $VMName
$hdd = Get-VMHardDiskDrive -VMName $VMName

Set-VMFirmware -VMName $VMName -BootOrder $dvd, $hdd -ErrorAction SilentlyContinue
Write-Host "  -> Boot order: DVD > HDD" -ForegroundColor Green

# Secure Boot avec template Microsoft Windows
Write-Host "Configuration Secure Boot..." -ForegroundColor Yellow
Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -ErrorAction SilentlyContinue
Write-Host "  -> Secure Boot: ON (template MicrosoftWindows)" -ForegroundColor Green

# Redemarrer
Write-Host "`nDemarrage de la VM..." -ForegroundColor Yellow
Start-VM -Name $VMName
Write-Host "  -> VM demarree!" -ForegroundColor Green

Write-Host "`n=== Ouvrez la console ===" -ForegroundColor Cyan
Write-Host "IMPORTANT: Appuyez VITE sur une touche dans la console VM" -ForegroundColor Red
Write-Host "pour booter sur le DVD!" -ForegroundColor Red

vmconnect localhost $VMName
pause
