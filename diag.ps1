param(
    [string]$VMName  = "DC01-LAB",
    [string]$ISOPath = ""
)

Write-Host "=== DIAGNOSTIC VM ===" -ForegroundColor Cyan

# VM existe?
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "ERREUR: VM '$VMName' n'existe pas!" -ForegroundColor Red
    Get-VM | Format-Table Name, State, Generation
    pause
    exit
}

Write-Host "VM: $($vm.Name) | Generation: $($vm.Generation) | State: $($vm.State)" -ForegroundColor Green

# ISO existe?
Write-Host "`n=== ISO ===" -ForegroundColor Cyan
if ($ISOPath -and (Test-Path $ISOPath)) {
    $size = [math]::Round((Get-Item $ISOPath).Length / 1GB, 2)
    Write-Host "ISO trouvee: $size GB" -ForegroundColor Green
} else {
    Write-Host "ISO non specifiee ou introuvable." -ForegroundColor Yellow
    Write-Host "Fichiers ISO detectes:" -ForegroundColor Yellow
    Get-ChildItem "$env:USERPROFILE\Desktop\*.iso", "$env:USERPROFILE\Downloads\*.iso" -ErrorAction SilentlyContinue |
        ForEach-Object { Write-Host "  $($_.FullName) ($([math]::Round($_.Length/1GB,2)) GB)" }
}

# DVD Drive
Write-Host "`n=== DVD DRIVE ===" -ForegroundColor Cyan
$dvd = Get-VMDvdDrive -VMName $VMName
if ($dvd) {
    Write-Host "Path: $($dvd.Path)" -ForegroundColor $(if($dvd.Path){"Green"}else{"Red"})
    Write-Host "Controller: $($dvd.ControllerNumber) Location: $($dvd.ControllerLocation)"
} else {
    Write-Host "AUCUN DVD Drive!" -ForegroundColor Red
}

# Firmware / Boot
Write-Host "`n=== FIRMWARE ===" -ForegroundColor Cyan
$fw = Get-VMFirmware -VMName $VMName -ErrorAction SilentlyContinue
if ($fw) {
    Write-Host "SecureBoot: $($fw.SecureBoot)"
    Write-Host "Boot Order:"
    $fw.BootOrder | ForEach-Object {
        Write-Host "  BootType: $($_.BootType) | Device: $($_.Device)" -ForegroundColor Yellow
    }
} else {
    Write-Host "(Generation 1 — pas de firmware UEFI)" -ForegroundColor DarkGray
}

# HDD
Write-Host "`n=== HDD ===" -ForegroundColor Cyan
Get-VMHardDiskDrive -VMName $VMName | ForEach-Object {
    Write-Host "  $($_.Path) | Controller: $($_.ControllerNumber)"
}

# Network
Write-Host "`n=== RESEAU ===" -ForegroundColor Cyan
Get-VMNetworkAdapter -VMName $VMName | ForEach-Object {
    Write-Host "  Switch: $($_.SwitchName) | MAC: $($_.MacAddress) | VLAN: $($_.VlanSetting.OperationMode)"
}

# Tentative de fix (seulement si ISO fournie)
if ($ISOPath -and (Test-Path $ISOPath)) {
    Write-Host "`n=== TENTATIVE DE FIX ===" -ForegroundColor Cyan
    $answer = Read-Host "Tenter un fix automatique du boot ? (O/N)"
    if ($answer -eq "O" -or $answer -eq "o") {
        if ($vm.State -ne "Off") {
            Stop-VM -Name $VMName -Force -TurnOff
            Start-Sleep 3
            Write-Host "VM eteinte." -ForegroundColor Yellow
        }
        Get-VMDvdDrive -VMName $VMName | Remove-VMDvdDrive
        Add-VMDvdDrive -VMName $VMName -Path $ISOPath
        Write-Host "DVD recree avec ISO." -ForegroundColor Green
        $newDvd = Get-VMDvdDrive -VMName $VMName
        $newHdd = Get-VMHardDiskDrive -VMName $VMName
        Set-VMFirmware -VMName $VMName -EnableSecureBoot Off -BootOrder $newDvd, $newHdd -ErrorAction SilentlyContinue
        Write-Host "Boot: DVD > HDD" -ForegroundColor Green
        Start-VM -Name $VMName
        Write-Host "VM DEMARREE — ouvrez la console et appuyez sur une touche!" -ForegroundColor Red
        vmconnect localhost $VMName
    }
}

pause
