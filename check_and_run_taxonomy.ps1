#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Verifie et lance Collect-ADCompleteTaxonomy.ps1 sur la VM
.DESCRIPTION
    1. Verifie si le script existe dans C:\Share\collectors\ sur la VM
    2. Liste tous les Collect-*.ps1 disponibles
    3. Lance Collect-ADCompleteTaxonomy.ps1 si present
    4. Rapatrie les fichiers produits
#>

. "$PSScriptRoot\config.ps1"
$secPass = ConvertTo-SecureString $LabPassword -AsPlainText -Force
$cred = New-Object PSCredential('LAB\Administrator', $secPass)
$VMName = 'DC01-LAB'

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  CHECK COLLECTORS SUR LA VM' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

# ============================================================
# ETAPE 1 : Lister les collectors deployes
# ============================================================
Write-Host ''
Write-Host '[1/4] Liste des collectors deployes...' -ForegroundColor Yellow

$vmScripts = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    $scripts = Get-ChildItem C:\Share\collectors\*.ps1 -ErrorAction SilentlyContinue | Sort-Object Name
    $scripts | ForEach-Object {
        [PSCustomObject]@{ Name = $_.Name; Size = $_.Length; LastWrite = $_.LastWriteTime }
    }
}

Write-Host "  $($vmScripts.Count) scripts trouves sur la VM" -ForegroundColor Green
$vmScripts | ForEach-Object { Write-Host "    $($_.Name) ($([math]::Round($_.Size/1KB,1)) KB)" }

# ============================================================
# ETAPE 2 : Verifier Collect-ADCompleteTaxonomy.ps1
# ============================================================
Write-Host ''
Write-Host '[2/4] Verification Collect-ADCompleteTaxonomy.ps1...' -ForegroundColor Yellow

$hasTaxonomy = $vmScripts | Where-Object { $_.Name -eq 'Collect-ADCompleteTaxonomy.ps1' }

if ($hasTaxonomy) {
    Write-Host "  [OK] Collect-ADCompleteTaxonomy.ps1 PRESENT ($([math]::Round($hasTaxonomy.Size/1KB,1)) KB)" -ForegroundColor Green
} else {
    Write-Host "  [ABSENT] Collect-ADCompleteTaxonomy.ps1 NON TROUVE" -ForegroundColor Red
    Write-Host "  Les scripts disponibles :" -ForegroundColor Yellow
    $vmScripts | ForEach-Object { Write-Host "    $($_.Name)" }
    Write-Host ''
    Write-Host "  ACTION REQUISE : Creer ou deployer Collect-ADCompleteTaxonomy.ps1" -ForegroundColor Red
    pause
    exit 1
}

# ============================================================
# ETAPE 3 : Lancer le collecteur taxonomy + run_collectors mode COMPLET
# ============================================================
Write-Host ''
Write-Host '[3/4] Execution de run_collectors.ps1 mode COMPLET...' -ForegroundColor Yellow
Write-Host '  Cela va executer TOUS les collectors dont ADCompleteTaxonomy' -ForegroundColor Gray

$confirm = Read-Host '  Lancer ? (O/n)'
if ($confirm -eq 'n') { Write-Host '  Annule.'; pause; exit 0 }

$results = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    $outDir = 'C:\Share\collectors_output'
    New-Item -Path $outDir -ItemType Directory -Force | Out-Null
    Set-Location $outDir

    # Scripts orchestrateurs a exclure
    $excludeAlways = @('Run-LIAScan-Collectors.ps1', 'Discover-ADTargets.ps1', 'web_execution_wrapper.ps1')

    $allScripts = Get-ChildItem C:\Share\collectors\*.ps1 | Where-Object { $_.Name -notin $excludeAlways } | Sort-Object Name

    Write-Host "=== Mode COMPLET : $($allScripts.Count) collectors ===" -ForegroundColor Cyan

    $results = @()
    foreach ($s in $allScripts) {
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $status = 'OK'; $errorMsg = ''
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
        $results += [PSCustomObject]@{ Script = $s.Name; Status = $status; Duree = $dur; Erreur = $errorMsg }
        $c = if ($status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  [$status] $($s.Name) ($dur)" -ForegroundColor $c
        if ($errorMsg) { Write-Host "         $errorMsg" -ForegroundColor DarkRed }
    }
    $results | Export-Csv 'C:\Share\collectors_results.csv' -NoTypeInformation -Encoding UTF8
    $results
}

$okC  = ($results | Where-Object Status -eq 'OK').Count
$errC = ($results | Where-Object Status -eq 'ERREUR').Count
Write-Host ''
Write-Host "  OK: $okC / ERREUR: $errC" -ForegroundColor $(if ($errC -gt 0) {'Yellow'} else {'Green'})

# ============================================================
# ETAPE 4 : Rapatrier les nouveaux fichiers
# ============================================================
Write-Host ''
Write-Host '[4/4] Rapatriement des fichiers...' -ForegroundColor Yellow

$destDir = "$PSScriptRoot\collects\ADDS\real_data"
New-Item -Path $destDir -ItemType Directory -Force | Out-Null

# Trouver le repertoire de sortie le plus recent
$latestDir = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    $base = 'C:\Share\collectors_output\collect\AD01'
    if (Test-Path $base) {
        $latest = Get-ChildItem $base -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if ($latest) {
            $collectDir = Join-Path $latest.FullName 'collect'
            if (Test-Path $collectDir) { return $collectDir }
        }
    }
    # Fallback: chercher dans collectors_output directement
    return 'C:\Share\collectors_output'
}

Write-Host "  Source VM : $latestDir" -ForegroundColor Gray

$files = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($dir)
    $allFiles = Get-ChildItem $dir -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in '.xml','.json' }
    $allFiles | ForEach-Object {
        @{ Name = $_.Name; Content = [IO.File]::ReadAllBytes($_.FullName); Size = $_.Length }
    }
} -ArgumentList $latestDir

$count = 0
foreach ($f in $files) {
    $dest = Join-Path $destDir $f.Name
    [IO.File]::WriteAllBytes($dest, $f.Content)
    $sizeKB = [math]::Round($f.Size / 1KB, 1)
    Write-Host "  [OK] $($f.Name) ($sizeKB KB)" -ForegroundColor Green
    $count++
}

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  COLLECTE TERMINEE' -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  Collectors executes : $okC OK / $errC erreurs"
Write-Host "  Fichiers rapatries  : $count"
Write-Host "  Destination         : $destDir"
Write-Host ''
pause
