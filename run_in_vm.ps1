#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploie automatiquement le lab AD dans la VM DC01-LAB via PowerShell Direct
.DESCRIPTION
    Copie tous les scripts (y compris populate/) dans la VM et les execute
    Necessite que la VM soit demarree avec Windows Server installe
.NOTES
    Executer sur l'HOTE Windows 11
#>

param(
    [string]$VMName     = "DC01-LAB",
    [string]$Password   = "Cim22091956!!??",
    [string]$ScriptsPath = $PSScriptRoot  # Utilise le dossier du script lui-meme
)

Write-Host "=== Deploiement automatique dans la VM ===" -ForegroundColor Cyan
Write-Host "  VM      : $VMName" -ForegroundColor White
Write-Host "  Scripts : $ScriptsPath" -ForegroundColor White

# Verifier que les scripts existent
if (-not (Test-Path "$ScriptsPath\02_Install-ADDS.ps1")) {
    Write-Host "[ERREUR] Scripts introuvables dans $ScriptsPath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path "$ScriptsPath\populate")) {
    Write-Host "[ERREUR] Dossier populate/ introuvable dans $ScriptsPath" -ForegroundColor Red
    exit 1
}

# Credentials
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("Administrator", $secPass)

# Activer le Guest Service pour copier des fichiers
Write-Host "`n[1/7] Activation Guest Service Integration..." -ForegroundColor Yellow
Enable-VMIntegrationService -VMName $VMName -Name "Guest Service Interface" -ErrorAction SilentlyContinue

# Copier les scripts principaux dans la VM
Write-Host "[2/7] Copie des scripts principaux..." -ForegroundColor Yellow
$mainScripts = @("02_Install-ADDS.ps1", "03_Install-Services.ps1", "04_Populate-AD.ps1")
foreach ($s in $mainScripts) {
    $src = Join-Path $ScriptsPath $s
    if (Test-Path $src) {
        Copy-VMFile -VMName $VMName -SourcePath $src -DestinationPath "C:\LabScripts\$s" -CreateFullPath -FileSource Host -Force -ErrorAction SilentlyContinue
        if ($?) { Write-Host "  [OK] $s" -ForegroundColor Green }
        else    { Write-Host "  [FAIL] $s — Guest Services peut-etre pas pret" -ForegroundColor Red }
    }
}

# Copier le dossier populate/ (tous les sous-scripts 04a-04m)
Write-Host "[3/7] Copie du dossier populate/ (13 sous-scripts)..." -ForegroundColor Yellow
$populateDir = Join-Path $ScriptsPath "populate"
$populateScripts = Get-ChildItem "$populateDir\*.ps1"
foreach ($ps in $populateScripts) {
    Copy-VMFile -VMName $VMName -SourcePath $ps.FullName `
        -DestinationPath "C:\LabScripts\populate\$($ps.Name)" `
        -CreateFullPath -FileSource Host -Force -ErrorAction SilentlyContinue
    if ($?) { Write-Host "  [OK] populate/$($ps.Name)" -ForegroundColor Green }
    else    { Write-Host "  [FAIL] populate/$($ps.Name)" -ForegroundColor Red }
}

# Executer le script 02 via PowerShell Direct
Write-Host "`n[4/7] Execution de 02_Install-ADDS.ps1 dans la VM..." -ForegroundColor Yellow
Write-Host "    (AD DS + DNS + DHCP + promotion DC — 5-10 min)" -ForegroundColor Gray

Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Set-ExecutionPolicy Bypass -Force
    if (Test-Path "C:\LabScripts\02_Install-ADDS.ps1") {
        & "C:\LabScripts\02_Install-ADDS.ps1"
    } else {
        Write-Host "ERREUR: 02_Install-ADDS.ps1 non trouve!" -ForegroundColor Red
    }
} -ErrorAction Continue

Write-Host "`n=== Script 02 termine ===" -ForegroundColor Cyan
Write-Host "La VM va redemarrer pour finaliser AD DS." -ForegroundColor Yellow
Write-Host "Attendez le redemarrage complet (~3 min)." -ForegroundColor Yellow
Read-Host "Appuyez sur Entree quand la VM a redemarree"

# Apres reboot, finaliser (DNS inverse + DHCP)
Write-Host "`n[5/7] Finalisation post-reboot (DNS + DHCP)..." -ForegroundColor Yellow
$domCred = New-Object System.Management.Automation.PSCredential("LAB\Administrator", $secPass)

Invoke-Command -VMName $VMName -Credential $domCred -ScriptBlock {
    & "C:\LabScripts\02_Install-ADDS.ps1"
} -ErrorAction Continue

# Executer script 03
Write-Host "`n[6/7] Execution de 03_Install-Services.ps1..." -ForegroundColor Yellow
Write-Host "    (15+ services: PKI, IIS, DFS, RDS, NPS... — 15-30 min)" -ForegroundColor Gray

Invoke-Command -VMName $VMName -Credential $domCred -ScriptBlock {
    & "C:\LabScripts\03_Install-Services.ps1"
} -ErrorAction Continue

# Executer script 04 (orchestrateur + populate/)
Write-Host "`n[7/7] Execution de 04_Populate-AD.ps1..." -ForegroundColor Yellow
Write-Host "    (80+ users, groupes, OUs, GPOs, 85+ anomalies)" -ForegroundColor Gray

Invoke-Command -VMName $VMName -Credential $domCred -ScriptBlock {
    & "C:\LabScripts\04_Populate-AD.ps1"
} -ErrorAction Continue

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  DEPLOIEMENT COMPLET!" -ForegroundColor Green
Write-Host "  Lab AD operationnel sur DC01-LAB" -ForegroundColor Green
Write-Host "  Domaine : lab.local" -ForegroundColor Green
Write-Host "  IP      : 192.168.0.10" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Prochaines etapes optionnelles :" -ForegroundColor Yellow
Write-Host "    - 05_Deploy-SecondDC.ps1 → RODC + partner.local (trust)" -ForegroundColor White
Write-Host "    - 06_Install-Claude-Code.ps1 → dans la VM" -ForegroundColor White

pause
