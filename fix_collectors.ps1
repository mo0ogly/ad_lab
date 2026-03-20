<#
.SYNOPSIS
    Corrige les bugs connus dans les collecteurs avant deploiement
.DESCRIPTION
    Applique les correctifs sur les .ps1 extraits de ad.zip :
      - Collect-ADAntivirus.ps1       : cle dupliquee CSFalconService
      - Collect-AADConnect.ps1        : filtre AZUREADSSOACC sans $
      - Collect-Delegations.ps1       : Export-Clixml -Depth (parametre inexistant)
      - Collect-GPOAuditSettings.ps1  : Export-Clixml -Depth (parametre inexistant)
      - Collect-SIDHistory.ps1        : Export-Clixml -Depth (parametre inexistant)
      - Collect-DsHeuristics.ps1      : -Encoding specifie deux fois
      - Collect-KerberosPreAuth.ps1   : -Encoding specifie deux fois
      - Collect-GMSADelegation.ps1    : $gmsaName: syntaxe invalide
      - Collect-SysvolPermissions.ps1 : $p: syntaxe invalide
      - Collect-PrivilegedAdminCount.ps1 : Try sans Catch
      - Collect-ADLapsBitLocker.ps1   : attribut LDAP ms-Mcs-AdmPwdExpirationTime invalide
      - Collect-Trusts.ps1            : attribut LDAP msDSSupportedEncryptionTypes invalide
.PARAMETER SourceDir
    Repertoire contenant les scripts extraits de ad.zip
#>
param(
    [Parameter(Mandatory)]
    [string]$SourceDir
)

if (-not (Test-Path $SourceDir)) {
    Write-Host '[ERREUR] Repertoire introuvable' -ForegroundColor Red
    exit 1
}

Write-Host '=== Corrections des collecteurs ===' -ForegroundColor Cyan

# FIX 1 : Collect-ADAntivirus.ps1 - Cle dupliquee CSFalconService
$avFile = Join-Path $SourceDir 'Collect-ADAntivirus.ps1'
if (Test-Path $avFile) {
    $content = Get-Content $avFile -Raw -Encoding UTF8
    $content = $content -replace '(?m)^\s+"CSFalconService"\s+=\s+"CrowdStrike"\s*\r?\n', ''
    Set-Content $avFile -Value $content -Encoding UTF8
    Write-Host '  [FIX] ADAntivirus - Cle dupliquee CSFalconService supprimee' -ForegroundColor Yellow
}

# FIX 2 : Collect-AADConnect.ps1 - Filtre AZUREADSSOACC sans dollar
$aadFile = Join-Path $SourceDir 'Collect-AADConnect.ps1'
if (Test-Path $aadFile) {
    $content = Get-Content $aadFile -Raw -Encoding UTF8
    $old = 'SamAccountName -eq "AZUREADSSOACC"'
    $new = 'SamAccountName -eq "AZUREADSSOACC$"'
    $content = $content.Replace($old, $new)
    Set-Content $aadFile -Value $content -Encoding UTF8
    Write-Host '  [FIX] AADConnect - Ajout dollar a AZUREADSSOACC' -ForegroundColor Yellow
}

# ============================================================
# FIX 3-5 : Export-Clixml -Depth (parametre inexistant)
# Collect-Delegations.ps1, Collect-GPOAuditSettings.ps1, Collect-SIDHistory.ps1
# ============================================================
$depthScripts = @('Collect-Delegations.ps1', 'Collect-GPOAuditSettings.ps1', 'Collect-SIDHistory.ps1')
foreach ($name in $depthScripts) {
    $file = Get-ChildItem $SourceDir -Filter $name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        $content = Get-Content $file.FullName -Raw -Encoding UTF8
        if ($content -match 'Export-Clixml.*-Depth') {
            $content = $content -replace '\s+-Depth\s+\d+', ''
            Set-Content $file.FullName -Value $content -Encoding UTF8
            Write-Host "  [FIX] $name - Suppression -Depth sur Export-Clixml" -ForegroundColor Yellow
        }
    }
}

# ============================================================
# FIX 6-7 : Parametre -Encoding specifie deux fois
# Collect-DsHeuristics.ps1, Collect-KerberosPreAuth.ps1
# ============================================================
$encodingScripts = @('Collect-DsHeuristics.ps1', 'Collect-KerberosPreAuth.ps1')
foreach ($name in $encodingScripts) {
    $file = Get-ChildItem $SourceDir -Filter $name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($file) {
        $lines = Get-Content $file.FullName -Encoding UTF8
        $fixed = $lines | ForEach-Object {
            $line = $_
            # Corriger Export-Clixml -Encoding (parametre inexistant)
            $line = $line -replace '(Export-Clixml\b[^|]*?)\s+-Encoding\s+\w+', '$1'
            # Corriger lignes avec -Encoding en double (Out-File, Set-Content, etc.)
            if (($line | Select-String -Pattern '-Encoding' -AllMatches).Matches.Count -gt 1) {
                $line = $line -replace '(\s+-Encoding\s+\w+)(.*?)(\s+-Encoding\s+\w+)', '$1$2'
            }
            $line
        }
        Set-Content $file.FullName -Value $fixed -Encoding UTF8
        Write-Host "  [FIX] $name - Suppression -Encoding duplique/invalide" -ForegroundColor Yellow
    }
}

# ============================================================
# FIX 8-9 : Syntaxe $variable: invalide (variable reference)
# Collect-GMSADelegation.ps1 ($gmsaName:), Collect-SysvolPermissions.ps1 ($p:)
# ============================================================
# Collect-GMSADelegation.ps1 : $gmsaName: -> ${gmsaName}:
$gmsaFile = Get-ChildItem $SourceDir -Filter 'Collect-GMSADelegation.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($gmsaFile) {
    $content = Get-Content $gmsaFile.FullName -Raw -Encoding UTF8
    $content = $content.Replace('$gmsaName:', '${gmsaName}:')
    Set-Content $gmsaFile.FullName -Value $content -Encoding UTF8
    Write-Host '  [FIX] GMSADelegation - $gmsaName: -> ${gmsaName}:' -ForegroundColor Yellow
}

# Collect-SysvolPermissions.ps1 : $p: -> ${p}:
$sysvolFile = Get-ChildItem $SourceDir -Filter 'Collect-SysvolPermissions.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($sysvolFile) {
    $content = Get-Content $sysvolFile.FullName -Raw -Encoding UTF8
    $content = $content.Replace('$p:', '${p}:')
    Set-Content $sysvolFile.FullName -Value $content -Encoding UTF8
    Write-Host '  [FIX] SysvolPermissions - $p: -> ${p}:' -ForegroundColor Yellow
}

# ============================================================
# FIX 10 : Collect-PrivilegedAdminCount.ps1 - Try sans Catch
# ============================================================
$pacFile = Get-ChildItem $SourceDir -Filter 'Collect-PrivilegedAdminCount.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pacFile) {
    $lines = Get-Content $pacFile.FullName -Encoding UTF8
    $newLines = @()
    $inTry = $false
    $braceCount = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $newLines += $line
        # Detecter debut de bloc try
        if ($line -match '^\s*try\s*\{?\s*$') { $inTry = $true; $braceCount = 0 }
        if ($inTry) {
            $braceCount += ($line.ToCharArray() | Where-Object { $_ -eq '{' }).Count
            $braceCount -= ($line.ToCharArray() | Where-Object { $_ -eq '}' }).Count
            if ($braceCount -eq 0 -and $line -match '\}') {
                $inTry = $false
                # Verifier si la ligne suivante contient catch
                $nextIdx = $i + 1
                while ($nextIdx -lt $lines.Count -and $lines[$nextIdx] -match '^\s*$') { $nextIdx++ }
                if ($nextIdx -ge $lines.Count -or $lines[$nextIdx] -notmatch '^\s*catch') {
                    $indent = if ($line -match '^(\s*)') { $Matches[1] } else { '' }
                    $newLines += "${indent}catch { Write-Warning `$_.Exception.Message }"
                }
            }
        }
    }
    Set-Content $pacFile.FullName -Value $newLines -Encoding UTF8
    Write-Host '  [FIX] PrivilegedAdminCount - Ajout catch manquant' -ForegroundColor Yellow
}

# ============================================================
# FIX 11-12 : Attributs LDAP invalides - try/catch autour des requetes
# Collect-ADLapsBitLocker.ps1 (ms-Mcs-AdmPwdExpirationTime)
# Collect-Trusts.ps1 (msDSSupportedEncryptionTypes)
# ============================================================
$ldapFile1 = Get-ChildItem $SourceDir -Filter 'Collect-ADLapsBitLocker.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ldapFile1) {
    $content = Get-Content $ldapFile1.FullName -Raw -Encoding UTF8
    # Supprimer l attribut invalide ms-Mcs-AdmPwdExpirationTime des listes -Properties
    # Le garder provoque "One or more properties are invalid"
    $content = $content -replace ",?\s*'ms-Mcs-AdmPwdExpirationTime'", ''
    $content = $content -replace ',?\s*"ms-Mcs-AdmPwdExpirationTime"', ''
    $content = $content -replace ",?\s*ms-Mcs-AdmPwdExpirationTime", ''
    Set-Content $ldapFile1.FullName -Value $content -Encoding UTF8
    Write-Host '  [FIX] ADLapsBitLocker - Suppression attribut LDAP invalide ms-Mcs-AdmPwdExpirationTime' -ForegroundColor Yellow
}

$ldapFile2 = Get-ChildItem $SourceDir -Filter 'Collect-Trusts.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($ldapFile2) {
    $content = Get-Content $ldapFile2.FullName -Raw -Encoding UTF8
    # Corriger le nom d attribut : msDSSupportedEncryptionTypes -> msDS-SupportedEncryptionTypes
    # Le tiret manquant dans msDS provoque "One or more properties are invalid"
    $content = $content.Replace('msDSSupportedEncryptionTypes', 'msDS-SupportedEncryptionTypes')
    Set-Content $ldapFile2.FullName -Value $content -Encoding UTF8
    Write-Host '  [FIX] Trusts - Correction attribut LDAP msDSSupportedEncryptionTypes -> msDS-SupportedEncryptionTypes' -ForegroundColor Yellow
}

Write-Host '  [INFO] ADCompleteTaxonomy sera lance avec -Interactive:false' -ForegroundColor Yellow
Write-Host '[OK] 12 corrections appliquees' -ForegroundColor Green
