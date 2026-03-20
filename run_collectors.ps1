#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Execute les collecteurs sur la VM avec menu de selection
.DESCRIPTION
    Menu interactif pour choisir le mode d'execution :
      1. TOUS les collecteurs (production)
      2. AD uniquement (pas de scan remote — lab)
      3. Rapide (AD sans les lourds — test)
    Exporte les resultats dans C:\Share\collectors_results.csv
.NOTES
    Prerequis : deploy_collectors.ps1 deja execute
#>
param(
    [string]$VMName  = 'DC01-LAB',
    [string]$Password = ''
)

# Charger config
if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

# ============================================================
# MENU DE SELECTION
# ============================================================
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  COLLECTEURS LIA-SCAN — MODE D EXECUTION' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''
Write-Host '  1. COMPLET (production)' -ForegroundColor Green
Write-Host '     Tous les 60 collecteurs. Necessite des machines' -ForegroundColor Gray
Write-Host '     jointes au domaine accessibles en WMI/RPC.' -ForegroundColor Gray
Write-Host ''
Write-Host '  2. AD UNIQUEMENT (recommande pour le lab)' -ForegroundColor Yellow
Write-Host '     Exclut les collecteurs qui scannent des machines' -ForegroundColor Gray
Write-Host '     distantes (WMI, Registry remote). Ideal quand' -ForegroundColor Gray
Write-Host '     seul le DC existe.' -ForegroundColor Gray
Write-Host '     Exclus :' -ForegroundColor Gray
Write-Host '       - Collect-ADAntivirus.ps1        (WMI Win32_Service sur chaque PC)' -ForegroundColor DarkGray
Write-Host '       - Collect-ADLocalAdmins.ps1      (WMI groupes locaux sur chaque PC)' -ForegroundColor DarkGray
Write-Host '       - Collect-ADSpooler.ps1          (Test PrintSpooler sur chaque PC)' -ForegroundColor DarkGray
Write-Host '       - Collect-ADRemoteSolutions.ps1  (Scan RDP/VNC/TeamViewer)' -ForegroundColor DarkGray
Write-Host '       - Collect-ADUptimeAndVersion.ps1 (WMI OS version sur chaque PC)' -ForegroundColor DarkGray
Write-Host '       - Collect-DCRegistry.ps1         (Registry remote sur DCs)' -ForegroundColor DarkGray
Write-Host '       - Collect-DCRegistryKey.ps1      (Registry remote sur DCs)' -ForegroundColor DarkGray
Write-Host '       - Collect-DCTLSConfig.ps1        (Registry TLS sur DCs)' -ForegroundColor DarkGray
Write-Host '       - Collect-DCHardening.ps1        (Registry hardening sur DCs)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '  3. RAPIDE (test)' -ForegroundColor Magenta
Write-Host '     Mode 2 + exclut les collecteurs lourds' -ForegroundColor Gray
Write-Host '     (schema complet, ACLs, taxonomie).' -ForegroundColor Gray
Write-Host '     Exclus en plus :' -ForegroundColor Gray
Write-Host '       - Collect-ADCompleteTaxonomy.ps1 (dump schema complet — 10+ min)' -ForegroundColor DarkGray
Write-Host '       - Collect-ADAcls.ps1             (ACLs tous objets — 5+ min)' -ForegroundColor DarkGray
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan

$choice = Read-Host '  Choix (1/2/3) [2]'
if ([string]::IsNullOrWhiteSpace($choice)) { $choice = '2' }

# Definir les exclusions selon le mode
$excludeRemote = @(
    'Collect-ADAntivirus.ps1'
    'Collect-ADLocalAdmins.ps1'
    'Collect-ADSpooler.ps1'
    'Collect-ADRemoteSolutions.ps1'
    'Collect-ADUptimeAndVersion.ps1'
    'Collect-DCRegistry.ps1'
    'Collect-DCRegistryKey.ps1'
    'Collect-DCTLSConfig.ps1'
    'Collect-DCHardening.ps1'
    'Collect-ADCompleteTaxonomy.ps1'
)

$excludeHeavy = @(
    'Collect-ADAcls.ps1'
)

# Scripts non-collecteurs (orchestrateurs, wrappers)
$excludeAlways = @(
    'Run-LIAScan-Collectors.ps1'
    'Discover-ADTargets.ps1'
    'web_execution_wrapper.ps1'
)

switch ($choice) {
    '1' {
        $exclude = $excludeAlways
        $modeName = 'COMPLET'
    }
    '3' {
        $exclude = $excludeAlways + $excludeRemote + $excludeHeavy
        $modeName = 'RAPIDE'
    }
    default {
        $exclude = $excludeAlways + $excludeRemote
        $modeName = 'AD UNIQUEMENT'
    }
}

Write-Host ''
Write-Host "  Mode selectionne : $modeName" -ForegroundColor Cyan
Write-Host "  Exclusions       : $($exclude.Count) scripts" -ForegroundColor Gray
Write-Host ''

# ============================================================
# EXECUTION DANS LA VM
# ============================================================
$results = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($exclude, $modeName)

    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    $outDir = 'C:\Share\collectors_output'
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    Set-Location $outDir

    $allScripts = Get-ChildItem C:\Share\collectors\*.ps1 | Sort-Object Name
    $runScripts = $allScripts | Where-Object { $_.Name -notin $exclude }
    $skipScripts = $allScripts | Where-Object { $_.Name -in $exclude }

    Write-Host "=== Mode: $modeName ===" -ForegroundColor Cyan
    Write-Host "=== $($runScripts.Count) a executer / $($skipScripts.Count) exclus ===" -ForegroundColor Cyan
    Write-Host ''

    $results = @()

    # Marquer les exclus comme SKIP
    foreach ($sk in $skipScripts) {
        $results += [PSCustomObject]@{
            Script = $sk.Name; Status = 'SKIP'; Duree = '0s'; Erreur = 'Exclu par le mode choisi'
        }
        Write-Host "  [SKIP] $($sk.Name)" -ForegroundColor DarkGray
    }

    # Executer les collecteurs
    foreach ($s in $runScripts) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $errorMsg = ''
        $status = 'OK'

        try {
            if ($s.Name -eq 'Collect-ADCompleteTaxonomy.ps1') {
                $null = & $s.FullName -Interactive:$false 2>&1
            } else {
                $null = & $s.FullName 2>&1
            }
        } catch {
            $status = 'ERREUR'
            $errorMsg = $_.Exception.Message
            if ($errorMsg.Length -gt 120) { $errorMsg = $errorMsg.Substring(0,120) + '...' }
        }

        $sw.Stop()
        $dur = "$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
        $results += [PSCustomObject]@{
            Script = $s.Name; Status = $status; Duree = $dur; Erreur = $errorMsg
        }

        $c = if ($status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  [$status] $($s.Name) ($dur)" -ForegroundColor $c
        if ($errorMsg) { Write-Host "         $errorMsg" -ForegroundColor DarkRed }
    }

    $results | Export-Csv 'C:\Share\collectors_results.csv' -NoTypeInformation -Encoding UTF8
    $results

} -ArgumentList (,$exclude), $modeName

# ============================================================
# RESUME
# ============================================================
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  RESUME ($modeName)" -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

$okC   = ($results | Where-Object Status -eq 'OK').Count
$errC  = ($results | Where-Object Status -eq 'ERREUR').Count
$skipC = ($results | Where-Object Status -eq 'SKIP').Count
Write-Host "  Total    : $($results.Count)"
Write-Host "  OK       : $okC" -ForegroundColor Green
Write-Host "  ERREUR   : $errC" -ForegroundColor $(if ($errC -gt 0) {'Red'} else {'Green'})
Write-Host "  SKIP     : $skipC" -ForegroundColor DarkGray

if ($errC -gt 0) {
    Write-Host ''
    Write-Host '  Erreurs :' -ForegroundColor Red
    $results | Where-Object Status -eq 'ERREUR' | ForEach-Object {
        Write-Host "    - $($_.Script) : $($_.Erreur)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '  CSV : \\192.168.0.10\Share\collectors_results.csv'
pause
