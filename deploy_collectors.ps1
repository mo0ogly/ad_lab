#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Copie les 60 collecteurs dans C:\Share\collectors sur la VM via PowerShell Direct
    Les orchestrateurs/wrappers sont archives dans C:\Share\collectors\archive\
.DESCRIPTION
    Extrait ad.zip et envoie chaque script .ps1 dans la VM sans Copy-VMFile
.NOTES
    Executer sur l'HOTE en admin
#>

param(
    [string]$VMName    = "DC01-LAB",
    [string]$ZipPath   = "E:\ad.zip",
    [string]$Password  = ""
)

# Charger config si pas de mot de passe
if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot "config.ps1"
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host "[ERREUR] Mot de passe requis. Copiez config.example.ps1 en config.ps1" -ForegroundColor Red; exit 1 }
}

# Verifier le zip
if (-not (Test-Path $ZipPath)) {
    Write-Host "[ERREUR] $ZipPath introuvable" -ForegroundColor Red
    exit 1
}

Write-Host "=== Deploiement des collecteurs ===" -ForegroundColor Cyan

# Credentials domaine
$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

# Extraire le zip localement
$tempDir = "$env:TEMP\ad_collectors"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
Write-Host "[1/3] Extraction de $ZipPath..." -ForegroundColor Yellow
Expand-Archive -Path $ZipPath -DestinationPath $tempDir -Force

# Lister les .ps1
$scripts = Get-ChildItem $tempDir -Recurse -Filter *.ps1
Write-Host "      $($scripts.Count) scripts trouves" -ForegroundColor Green

# Appliquer les corrections automatiques
$fixScript = Join-Path $PSScriptRoot "fix_collectors.ps1"
if (Test-Path $fixScript) {
    Write-Host "[1b/3] Application des corrections..." -ForegroundColor Yellow
    & $fixScript -SourceDir $tempDir
}

# Scripts orchestrateurs/wrappers -> archive (pas executes directement)
$archiveScripts = @(
    'Run-LIAScan-Collectors.ps1'
    'Discover-ADTargets.ps1'
    'web_execution_wrapper.ps1'
)

# Creer les dossiers sur la VM
Write-Host "[2/3] Creation de C:\Share\collectors sur la VM..." -ForegroundColor Yellow
Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    New-Item -Path C:\Share\collectors -ItemType Directory -Force | Out-Null
    New-Item -Path C:\Share\collectors\archive -ItemType Directory -Force | Out-Null
}

# Copier chaque script via PowerShell Direct (contenu en parametre)
Write-Host "[3/3] Copie des collecteurs via PowerShell Direct..." -ForegroundColor Yellow
$ok = 0; $fail = 0; $archived = 0
foreach ($f in $scripts) {
    $name    = $f.Name
    $content = Get-Content $f.FullName -Raw -Encoding UTF8

    # Determiner si c'est un orchestrateur -> archive
    if ($name -in $archiveScripts) {
        $destPath = "C:\Share\collectors\archive\$name"
        $label = "ARCHIVE"
    } else {
        $destPath = "C:\Share\collectors\$name"
        $label = "OK"
    }

    try {
        Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
            param($dest, $c)
            Set-Content -Path $dest -Value $c -Encoding UTF8 -Force
        } -ArgumentList $destPath, $content -ErrorAction Stop

        if ($label -eq "ARCHIVE") {
            Write-Host "  [ARCHIVE] $name -> archive/" -ForegroundColor DarkYellow
            $archived++
        } else {
            Write-Host "  [OK] $name" -ForegroundColor Green
        }
        $ok++
    } catch {
        Write-Host "  [FAIL] $name : $_" -ForegroundColor Red
        $fail++
    }
}

Write-Host "`n=== Resultat ===" -ForegroundColor Cyan
Write-Host "  OK      : $($ok - $archived)" -ForegroundColor Green
Write-Host "  ARCHIVE : $archived (orchestrateurs dans archive/)" -ForegroundColor DarkYellow
Write-Host "  FAIL    : $fail" -ForegroundColor $(if ($fail -gt 0) {'Red'} else {'Green'})
Write-Host "  Chemin VM : C:\Share\collectors\" -ForegroundColor White
Write-Host "  Chemin UNC: \\192.168.0.10\Share\collectors\" -ForegroundColor White

# Nettoyage
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

pause
