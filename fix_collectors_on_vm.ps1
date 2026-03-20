#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Applique les 12 corrections directement sur les .ps1 dans C:\Share\collectors de la VM
.DESCRIPTION
    Corrige les bugs in-place sur la VM via PowerShell Direct.
    Pas de wrapper — chaque script est patche directement.
#>
param(
    [string]$VMName  = 'DC01-LAB',
    [string]$Password = ''
)

if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  CORRECTION DES COLLECTORS SUR LA VM'       -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

$fixCount = 0
$errCount = 0

# --- Helper : applique un fix sur un script dans la VM ---
function Fix-ScriptOnVM {
    param(
        [string]$ScriptName,
        [string]$Description,
        [scriptblock]$FixBlock
    )
    try {
        $result = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($name, $fix)
            $path = "C:\Share\collectors\$name"
            if (-not (Test-Path $path)) { return "MISSING" }
            $content = Get-Content $path -Raw -Encoding UTF8
            $fixed = & $fix $content
            if ($fixed -ne $content) {
                Set-Content $path -Value $fixed -Encoding UTF8 -Force
                return "FIXED"
            }
            return "ALREADY_OK"
        } -ArgumentList $ScriptName, $FixBlock -ErrorAction Stop

        $color = switch ($result) {
            'FIXED'      { $script:fixCount++; 'Green' }
            'ALREADY_OK' { 'DarkGray' }
            'MISSING'    { $script:errCount++; 'Red' }
        }
        Write-Host "  [$result] $ScriptName - $Description" -ForegroundColor $color
    } catch {
        $script:errCount++
        Write-Host "  [ERROR] $ScriptName - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# ============================================================
# FIX 1 : Collect-ADAntivirus.ps1 - Cle dupliquee CSFalconService
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-ADAntivirus.ps1' -Description 'Cle dupliquee CSFalconService' -FixBlock {
    param($c)
    $c -replace '(?m)^\s+"CSFalconService"\s+=\s+"CrowdStrike"\s*\r?\n', ''
}

# ============================================================
# FIX 2 : Collect-AADConnect.ps1 - Filtre AZUREADSSOACC sans $
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-AADConnect.ps1' -Description 'Ajout $ a AZUREADSSOACC' -FixBlock {
    param($c)
    $c.Replace('SamAccountName -eq "AZUREADSSOACC"', 'SamAccountName -eq "AZUREADSSOACC$"')
}

# ============================================================
# FIX 3-5 : Export-Clixml -Depth (parametre inexistant)
# ============================================================
foreach ($name in @('Collect-Delegations.ps1', 'Collect-GPOAuditSettings.ps1', 'Collect-SIDHistory.ps1')) {
    Fix-ScriptOnVM -ScriptName $name -Description 'Suppression -Depth sur Export-Clixml' -FixBlock {
        param($c)
        $c -replace '\s+-Depth\s+\d+', ''
    }
}

# ============================================================
# FIX 6-7 : -Encoding duplique ou invalide sur Export-Clixml
# ============================================================
foreach ($name in @('Collect-DsHeuristics.ps1', 'Collect-KerberosPreAuth.ps1')) {
    Fix-ScriptOnVM -ScriptName $name -Description 'Suppression -Encoding invalide/duplique' -FixBlock {
        param($c)
        # Supprimer -Encoding sur Export-Clixml (parametre inexistant)
        $c = $c -replace '(Export-Clixml\b[^|]*?)\s+-Encoding\s+\w+', '$1'
        # Si -Encoding apparait 2 fois sur une meme ligne, supprimer le 2e
        $lines = $c -split "`n"
        $fixed = foreach ($line in $lines) {
            if (($line | Select-String -Pattern '-Encoding' -AllMatches).Matches.Count -gt 1) {
                $line -replace '(\s+-Encoding\s+\w+)(.*?)(\s+-Encoding\s+\w+)', '$1$2'
            } else { $line }
        }
        $fixed -join "`n"
    }
}

# ============================================================
# FIX 8 : Collect-GMSADelegation.ps1 - $gmsaName: syntaxe invalide
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-GMSADelegation.ps1' -Description '$gmsaName: -> ${gmsaName}:' -FixBlock {
    param($c)
    $c.Replace('$gmsaName:', '${gmsaName}:')
}

# ============================================================
# FIX 9 : Collect-SysvolPermissions.ps1 - $p: syntaxe invalide
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-SysvolPermissions.ps1' -Description '$p: -> ${p}:' -FixBlock {
    param($c)
    $c.Replace('$p:', '${p}:')
}

# ============================================================
# FIX 10 : Collect-PrivilegedAdminCount.ps1 - Try sans Catch
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-PrivilegedAdminCount.ps1' -Description 'Ajout catch manquant' -FixBlock {
    param($c)
    $lines = $c -split "`n"
    $newLines = @()
    $inTry = $false
    $braceCount = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $newLines += $line
        if ($line -match '^\s*try\s*\{?\s*$') { $inTry = $true; $braceCount = 0 }
        if ($inTry) {
            $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            if ($braceCount -eq 0 -and $line -match '\}') {
                $inTry = $false
                $nextIdx = $i + 1
                while ($nextIdx -lt $lines.Count -and $lines[$nextIdx] -match '^\s*$') { $nextIdx++ }
                if ($nextIdx -ge $lines.Count -or $lines[$nextIdx] -notmatch '^\s*catch') {
                    $indent = if ($line -match '^(\s*)') { $Matches[1] } else { '' }
                    $newLines += "${indent}catch { Write-Warning `$_.Exception.Message }"
                }
            }
        }
    }
    $newLines -join "`n"
}

# ============================================================
# FIX 11 : Collect-ADLapsBitLocker.ps1 - attribut LDAP invalide
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-ADLapsBitLocker.ps1' -Description 'Suppression ms-Mcs-AdmPwdExpirationTime' -FixBlock {
    param($c)
    $c = $c -replace ",?\s*'ms-Mcs-AdmPwdExpirationTime'", ''
    $c = $c -replace ',?\s*"ms-Mcs-AdmPwdExpirationTime"', ''
    $c -replace ",?\s*ms-Mcs-AdmPwdExpirationTime", ''
}

# ============================================================
# FIX 12 : Collect-Trusts.ps1 - attribut LDAP mal ecrit
# ============================================================
Fix-ScriptOnVM -ScriptName 'Collect-Trusts.ps1' -Description 'msDSSupportedEncryptionTypes -> msDS-SupportedEncryptionTypes' -FixBlock {
    param($c)
    $c.Replace('msDSSupportedEncryptionTypes', 'msDS-SupportedEncryptionTypes')
}

# ============================================================
# RESUME
# ============================================================
Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host "  FIXED  : $fixCount" -ForegroundColor Green
Write-Host "  ERRORS : $errCount" -ForegroundColor $(if ($errCount -eq 0) {'Green'} else {'Red'})
Write-Host '============================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================
# RELANCER LES 13 COLLECTORS EN ERREUR
# ============================================================
Write-Host '[ETAPE 2] Relance des collectors corriges...' -ForegroundColor Yellow

$rerunScripts = @(
    'Collect-Delegations.ps1'
    'Collect-GPOAuditSettings.ps1'
    'Collect-SIDHistory.ps1'
    'Collect-DsHeuristics.ps1'
    'Collect-KerberosPreAuth.ps1'
    'Collect-GMSADelegation.ps1'
    'Collect-SysvolPermissions.ps1'
    'Collect-PrivilegedAdminCount.ps1'
    'Collect-ADLapsBitLocker.ps1'
    'Collect-Trusts.ps1'
    'Collect-ADAntivirus.ps1'
    'Collect-AADConnect.ps1'
)

$rerunResults = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($scripts)
    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
    Import-Module ActiveDirectory -ErrorAction SilentlyContinue

    $outDir = 'C:\Share\collectors_output'
    Set-Location $outDir

    $results = @()
    foreach ($name in $scripts) {
        $path = "C:\Share\collectors\$name"
        if (-not (Test-Path $path)) {
            $results += [PSCustomObject]@{ Script=$name; Status='MISSING'; Duree='0s'; Erreur='Script introuvable' }
            continue
        }
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $status = 'OK'; $errorMsg = ''
        try {
            $null = & $path 2>&1
        } catch {
            $status = 'ERREUR'
            $errorMsg = $_.Exception.Message.Substring(0, [Math]::Min(120, $_.Exception.Message.Length))
        }
        $sw.Stop()
        $dur = "$([math]::Round($sw.Elapsed.TotalSeconds,1))s"
        $results += [PSCustomObject]@{ Script=$name; Status=$status; Duree=$dur; Erreur=$errorMsg }
        $c = if ($status -eq 'OK') { 'Green' } else { 'Red' }
        Write-Host "  [$status] $name ($dur)" -ForegroundColor $c
    }
    $results
} -ArgumentList (,$rerunScripts)

$okC  = ($rerunResults | Where-Object Status -eq 'OK').Count
$errC = ($rerunResults | Where-Object Status -ne 'OK').Count

Write-Host ''
Write-Host '============================================' -ForegroundColor Cyan
Write-Host '  RELANCE TERMINEE' -ForegroundColor Cyan
Write-Host "  OK     : $okC / $($rerunScripts.Count)" -ForegroundColor $(if ($errC -eq 0) {'Green'} else {'Yellow'})
Write-Host "  ERREUR : $errC" -ForegroundColor $(if ($errC -eq 0) {'Green'} else {'Red'})
Write-Host '============================================' -ForegroundColor Cyan

if ($errC -gt 0) {
    Write-Host ''
    Write-Host '  Erreurs restantes :' -ForegroundColor Red
    $rerunResults | Where-Object Status -ne 'OK' | ForEach-Object {
        Write-Host "    $($_.Script) : $($_.Erreur)" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host 'Prochaine etape : copy_collects.ps1 pour rapatrier les nouvelles donnees' -ForegroundColor Gray
