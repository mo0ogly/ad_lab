#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Corrige la connectivite reseau de la VM DC01-LAB
.DESCRIPTION
    Probleme courant: la carte reseau de la VM est assignee a un VLAN
    (ex: VLAN 2) ce qui l'isole du reseau physique.

    Ce script:
    - Verifie le switch virtuel (doit etre External)
    - Retire le VLAN tag de la carte reseau VM
    - Connecte la VM au LabSwitch (externe)
    - Verifie la connectivite
.NOTES
    Executer sur l'HOTE en tant qu'Administrateur
#>

param(
    [string]$VMName = "DC01-LAB",
    [string]$SwitchName = "LabSwitch"
)

$ErrorActionPreference = "Continue"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Correction Reseau VM" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# --- 1. Verifier que la VM existe ---
Write-Host "`n[1/5] Verification de la VM..." -ForegroundColor Yellow
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) {
    Write-Host "  ERREUR: VM '$VMName' introuvable!" -ForegroundColor Red
    Get-VM | Format-Table Name, State -AutoSize
    exit 1
}
Write-Host "  -> VM '$VMName' trouvee (Etat: $($vm.State))." -ForegroundColor Green

# --- 2. Verifier/creer le switch externe ---
Write-Host "`n[2/5] Verification du switch reseau..." -ForegroundColor Yellow
$switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue

if (-not $switch) {
    Write-Host "  -> Switch '$SwitchName' n'existe pas. Creation en mode External..." -ForegroundColor Yellow

    # Trouver la carte reseau physique
    $physicalAdapters = Get-NetAdapter -Physical | Where-Object { $_.Status -eq "Up" }
    if ($physicalAdapters.Count -eq 0) {
        Write-Host "  ERREUR: Aucune carte reseau physique active!" -ForegroundColor Red
        exit 1
    }

    $selectedAdapter = $physicalAdapters | Select-Object -First 1
    Write-Host "  -> Carte physique selectionnee: $($selectedAdapter.Name) ($($selectedAdapter.InterfaceDescription))" -ForegroundColor Gray

    New-VMSwitch -Name $SwitchName -NetAdapterName $selectedAdapter.Name -AllowManagementOS $true
    Write-Host "  -> Switch externe '$SwitchName' cree." -ForegroundColor Green
} else {
    Write-Host "  -> Switch '$SwitchName' existe (Type: $($switch.SwitchType))." -ForegroundColor Green
    if ($switch.SwitchType -ne "External") {
        Write-Host "  ATTENTION: Le switch n'est pas External! La VM n'aura pas acces au reseau physique." -ForegroundColor Red
        Write-Host "  Pour un acces Internet, le switch doit etre de type External." -ForegroundColor Yellow
    }
}

# --- 3. Connecter la VM au bon switch ---
Write-Host "`n[3/5] Connexion de la VM au switch '$SwitchName'..." -ForegroundColor Yellow
$vmNic = Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1

if (-not $vmNic) {
    Write-Host "  -> Aucune carte reseau sur la VM. Ajout..." -ForegroundColor Yellow
    Add-VMNetworkAdapter -VMName $VMName -SwitchName $SwitchName
    Write-Host "  -> Carte reseau ajoutee." -ForegroundColor Green
} elseif ($vmNic.SwitchName -ne $SwitchName) {
    Connect-VMNetworkAdapter -VMName $VMName -Name $vmNic.Name -SwitchName $SwitchName
    Write-Host "  -> Carte reconnectee de '$($vmNic.SwitchName)' vers '$SwitchName'." -ForegroundColor Green
} else {
    Write-Host "  -> Deja connectee a '$SwitchName'." -ForegroundColor Green
}

# --- 4. Retirer le VLAN (cause principale du probleme) ---
Write-Host "`n[4/5] Verification et correction du VLAN..." -ForegroundColor Yellow
$vlanConfig = Get-VMNetworkAdapterVlan -VMName $VMName

if ($vlanConfig.OperationMode -eq "Access" -and $vlanConfig.AccessVlanId -gt 0) {
    Write-Host "  -> PROBLEME DETECTE: VLAN $($vlanConfig.AccessVlanId) configure!" -ForegroundColor Red
    Write-Host "  -> Suppression du VLAN..." -ForegroundColor Yellow
    Set-VMNetworkAdapterVlan -VMName $VMName -Untagged
    Write-Host "  -> VLAN retire. Carte en mode Untagged." -ForegroundColor Green
} elseif ($vlanConfig.OperationMode -eq "Untagged") {
    Write-Host "  -> OK: Pas de VLAN (mode Untagged)." -ForegroundColor Green
} else {
    Write-Host "  -> Mode actuel: $($vlanConfig.OperationMode). Passage en Untagged..." -ForegroundColor Yellow
    Set-VMNetworkAdapterVlan -VMName $VMName -Untagged
    Write-Host "  -> Carte en mode Untagged." -ForegroundColor Green
}

# --- 5. Verification finale ---
Write-Host "`n[5/5] Verification finale..." -ForegroundColor Yellow

$vmNicFinal = Get-VMNetworkAdapter -VMName $VMName | Select-Object -First 1
$vlanFinal = Get-VMNetworkAdapterVlan -VMName $VMName

Write-Host ""
Write-Host "  ================================================" -ForegroundColor Cyan
Write-Host "  Configuration reseau VM:" -ForegroundColor White
Write-Host "    VM           : $VMName"
Write-Host "    Switch       : $($vmNicFinal.SwitchName)"
Write-Host "    MAC          : $($vmNicFinal.MacAddress)"
Write-Host "    VLAN Mode    : $($vlanFinal.OperationMode)"
Write-Host "    Status       : $($vmNicFinal.Status)"
Write-Host "    IP detectees : $($vmNicFinal.IPAddresses -join ', ')"
Write-Host "  ================================================" -ForegroundColor Cyan

# Test de connectivite depuis l'hote
Write-Host "`n  Test de connectivite..." -ForegroundColor Yellow
$hostNic = Get-NetIPConfiguration | Where-Object { $_.InterfaceAlias -like "*$SwitchName*" }
if ($hostNic) {
    Write-Host "    Hote ($($hostNic.InterfaceAlias)): $($hostNic.IPv4Address.IPAddress)" -ForegroundColor Gray
}

# Ping la passerelle
$gwPing = Test-Connection -ComputerName 192.168.0.1 -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($gwPing) {
    Write-Host "    Passerelle 192.168.0.1 : OK" -ForegroundColor Green
} else {
    Write-Host "    Passerelle 192.168.0.1 : ECHEC" -ForegroundColor Red
}

# Ping Internet
$inetPing = Test-Connection -ComputerName 8.8.8.8 -Count 1 -Quiet -ErrorAction SilentlyContinue
if ($inetPing) {
    Write-Host "    Internet 8.8.8.8      : OK" -ForegroundColor Green
} else {
    Write-Host "    Internet 8.8.8.8      : ECHEC" -ForegroundColor Red
}

Write-Host ""
Write-Host "  [NEXT] Dans la VM, verifiez avec:" -ForegroundColor Yellow
Write-Host "    ipconfig /all" -ForegroundColor White
Write-Host "    ping 192.168.0.1" -ForegroundColor White
Write-Host "    ping 8.8.8.8" -ForegroundColor White
Write-Host ""
Write-Host "  Si la VM n'a pas la bonne IP, executez dans la VM:" -ForegroundColor Yellow
Write-Host "    netsh interface ip set address ""Ethernet"" static 192.168.0.10 255.255.255.0 192.168.0.1" -ForegroundColor White
Write-Host "    netsh interface ip set dns ""Ethernet"" static 127.0.0.1" -ForegroundColor White
Write-Host "    netsh interface ip add dns ""Ethernet"" 8.8.8.8 index=2" -ForegroundColor White

Read-Host "`nAppuyez sur Entree pour terminer"
