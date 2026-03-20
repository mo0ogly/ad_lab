#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Pipeline complet de recette ADDS : collecte sur le lab + test avec le vrai moteur
.DESCRIPTION
    1. Lance les collectors AD sur DC01-LAB (mode 2 = AD uniquement)
    2. Recupere les XML/JSON collectes vers le host
    3. Teste les 405 regles ADDS avec lia-test.exe (vrai moteur Go)
.NOTES
    Prerequis : VM DC01-LAB demarree, collectors deployes, lia-test.exe compile
#>
param(
    [string]$VMName   = 'DC01-LAB',
    [string]$Password = '',
    [string]$LiaTest  = 'C:\Users\pizzif\Documents\GitHub\lia-security-platform-v2\lia-test.exe',
    [string]$RulesDir = 'C:\Users\pizzif\Documents\GitHub\lia-security-platform-v2\lia_rules\rule_analysis\ADDS',
    [string]$OutputDir = 'C:\Users\pizzif\Documents\GitHub\ad_lab\collects\ADDS'
)

# --- Config ---
if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  RECETTE ADDS - Pipeline complet' -ForegroundColor Cyan
Write-Host '  1. Collecte sur le lab (mode AD only)' -ForegroundColor Gray
Write-Host '  2. Recuperation des donnees' -ForegroundColor Gray
Write-Host '  3. Test avec le vrai moteur LIA-Scan' -ForegroundColor Gray
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================
# ETAPE 1 : Collecte sur la VM (mode 2 = AD uniquement)
# ============================================================
Write-Host '[ETAPE 1/3] Collecte sur la VM...' -ForegroundColor Yellow

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

$excludeAlways = @(
    'Run-LIAScan-Collectors.ps1'
    'Discover-ADTargets.ps1'
    'web_execution_wrapper.ps1'
)

$exclude = $excludeAlways + $excludeRemote

$collectResults = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($exclude)

    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    $outDir = 'C:\Share\collectors_output'
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    Set-Location $outDir

    $allScripts = Get-ChildItem C:\Share\collectors\*.ps1 | Sort-Object Name
    $runScripts = $allScripts | Where-Object { $_.Name -notin $exclude }

    Write-Host "  $($runScripts.Count) collecteurs a executer" -ForegroundColor Cyan

    $results = @()
    foreach ($s in $runScripts) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $status = 'OK'; $errorMsg = ''
        try {
            $null = & $s.FullName 2>&1
        } catch {
            $status = 'ERREUR'
            $errorMsg = $_.Exception.Message.Substring(0, [Math]::Min(120, $_.Exception.Message.Length))
        }
        $sw.Stop()
        $dur = "$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
        $results += [PSCustomObject]@{ Script = $s.Name; Status = $status; Duree = $dur; Erreur = $errorMsg }
        $c = if ($status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  [$status] $($s.Name) ($dur)" -ForegroundColor $c
    }

    # Lister les fichiers generes
    $files = Get-ChildItem $outDir -File | Select-Object Name, Length, LastWriteTime
    [PSCustomObject]@{ Results = $results; Files = $files }

} -ArgumentList (,$exclude)

$okC  = ($collectResults.Results | Where-Object Status -eq 'OK').Count
$errC = ($collectResults.Results | Where-Object Status -eq 'ERREUR').Count
Write-Host "  Collecte terminee : $okC OK / $errC ERREUR" -ForegroundColor $(if ($errC -eq 0) {'Green'} else {'Yellow'})
Write-Host "  Fichiers generes  : $($collectResults.Files.Count)" -ForegroundColor Gray

# ============================================================
# ETAPE 2 : Recuperation des donnees
# ============================================================
Write-Host ''
Write-Host '[ETAPE 2/3] Recuperation des donnees...' -ForegroundColor Yellow

New-Item -Path $OutputDir -ItemType Directory -Force | Out-Null

# Recuperer chaque fichier via PowerShell Direct
$fileList = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Get-ChildItem 'C:\Share\collectors_output' -File | ForEach-Object {
        @{ Name = $_.Name; Content = [IO.File]::ReadAllText($_.FullName) }
    }
}

$copied = 0
foreach ($f in $fileList) {
    $destPath = Join-Path $OutputDir $f.Name
    [IO.File]::WriteAllText($destPath, $f.Content, [Text.UTF8Encoding]::new($false))
    $copied++
}
Write-Host "  $copied fichiers copies vers $OutputDir" -ForegroundColor Green

# ============================================================
# ETAPE 3 : Test avec le vrai moteur
# ============================================================
Write-Host ''
Write-Host '[ETAPE 3/3] Test des regles ADDS avec lia-test.exe...' -ForegroundColor Yellow

$ymlFiles = Get-ChildItem $RulesDir -Recurse -Filter '*.yml' | Where-Object { $_.Name -notlike 'README*' }
$pass = 0; $fail = 0; $error_count = 0; $skip = 0

foreach ($yml in $ymlFiles) {
    $ruleDir  = $yml.DirectoryName
    $ruleId   = $yml.BaseName
    $testData = Join-Path $ruleDir 'test_data.json'

    if (-not (Test-Path $testData)) { $skip++; continue }

    # Nettoyer BOM si present
    $bytes = [IO.File]::ReadAllBytes($testData)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        [IO.File]::WriteAllBytes($testData, $bytes[3..($bytes.Length-1)])
    }

    $result = & $LiaTest --rule $yml.FullName --events $testData --format txt 2>&1 | Out-String

    if ($result -match 'PASSED') {
        $matches_count = if ($result -match 'Matches:\s+(\d+)') { $Matches[1] } else { '?' }
        $pass++
    } elseif ($result -match 'ERROR') {
        $errLine = ($result -split "`n" | Where-Object { $_ -match 'Status:' }) -replace 'Status:\s*ERROR - ', ''
        Write-Host "  [ERR]  $ruleId  $errLine" -ForegroundColor Red
        $error_count++
    } else {
        Write-Host "  [FAIL] $ruleId" -ForegroundColor Yellow
        $fail++
    }
}

# ============================================================
# RESUME FINAL
# ============================================================
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  RESUME RECETTE ADDS' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Collecte  : $okC OK / $errC ERREUR" -ForegroundColor $(if ($errC -eq 0) {'Green'} else {'Yellow'})
Write-Host "  Fichiers  : $copied recuperes" -ForegroundColor Gray
Write-Host "  Regles    : $($ymlFiles.Count) testees" -ForegroundColor Gray
Write-Host "  PASS      : $pass" -ForegroundColor Green
Write-Host "  FAIL      : $fail" -ForegroundColor $(if ($fail -eq 0) {'Green'} else {'Red'})
Write-Host "  ERROR     : $error_count" -ForegroundColor $(if ($error_count -eq 0) {'Green'} else {'Red'})
Write-Host "  SKIP      : $skip (no test_data)" -ForegroundColor DarkGray
Write-Host ''

# Exporter le rapport
$reportPath = Join-Path $OutputDir "RECETTE_ADDS_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
@"
RECETTE ADDS - $(Get-Date -Format 'yyyy-MM-dd HH:mm')
Collecte: $okC OK / $errC ERREUR
Fichiers: $copied
Regles testees: $($ymlFiles.Count)
PASS: $pass | FAIL: $fail | ERROR: $error_count | SKIP: $skip
"@ | Set-Content $reportPath -Encoding UTF8
Write-Host "  Rapport : $reportPath" -ForegroundColor Gray
