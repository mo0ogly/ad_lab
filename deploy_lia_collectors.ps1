#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploie et lance les collectors LIA-Scan (Exchange + IIS) dans la VM
.DESCRIPTION
    1. Copie Collect-Exchange.ps1 et Collect-IIS.ps1 dans la VM
    2. Lance les collectors dans la VM via PowerShell Direct
    3. Rapatrie les resultats JSON vers collects/
.NOTES
    Executer sur l'HOTE en admin apres deploy_collectors.ps1
#>
param(
    [string]$VMName  = 'DC01-LAB',
    [string]$Password = '',
    [string]$CollectsRoot = (Join-Path (Split-Path $PSScriptRoot -Parent) 'collects')
)

$ErrorActionPreference = 'Stop'

# Charger config
if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  DEPLOIEMENT COLLECTORS LIA-SCAN' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan

# ============================================================
# 1. COPIER LES COLLECTORS DANS LA VM
# ============================================================
Write-Host ''
Write-Host '[1/4] Copie des collectors dans la VM...' -ForegroundColor Cyan

$collectors = @(
    @{ Name = 'Collect-Exchange.ps1'; Source = Join-Path $CollectsRoot 'EXCHANGE\Collect-Exchange.ps1' }
    @{ Name = 'Collect-IIS.ps1';      Source = Join-Path $CollectsRoot 'iis\Collect-IIS.ps1' }
)

foreach ($c in $collectors) {
    if (-not (Test-Path $c.Source)) {
        Write-Host "  [SKIP] $($c.Name) non trouve : $($c.Source)" -ForegroundColor Yellow
        continue
    }
    $content = Get-Content $c.Source -Raw
    Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
        param($name, $content)
        $dir = 'C:\Share\lia_collectors'
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        Set-Content -Path "C:\Share\lia_collectors\$name" -Value $content -Encoding UTF8
    } -ArgumentList $c.Name, $content
    Write-Host "  [OK] $($c.Name)" -ForegroundColor Green
}

# ============================================================
# 2. LANCER LE COLLECTOR EXCHANGE
# ============================================================
Write-Host ''
Write-Host '[2/4] Collector Exchange...' -ForegroundColor Cyan

$exchResult = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

    # Tenter de charger le snap-in Exchange
    $snapin = Get-PSSnapin -Name Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue
    if (-not $snapin) {
        Add-PSSnapin Microsoft.Exchange.Management.PowerShell.SnapIn -ErrorAction SilentlyContinue
    }

    $scriptPath = 'C:\Share\lia_collectors\Collect-Exchange.ps1'
    if (-not (Test-Path $scriptPath)) {
        Write-Host '  [ERREUR] Collect-Exchange.ps1 non trouve' -ForegroundColor Red
        return 'MISSING'
    }

    Set-Location 'C:\Share\lia_collectors'
    try {
        & $scriptPath -Mode Full -OutputPath 'C:\Share\exchange_events.json'
        if (Test-Path 'C:\Share\exchange_events.json') {
            $size = (Get-Item 'C:\Share\exchange_events.json').Length
            Write-Host "  [OK] exchange_events.json ($([math]::Round($size/1KB,1)) KB)" -ForegroundColor Green
            return 'OK'
        } else {
            Write-Host '  [WARN] Pas de sortie generee' -ForegroundColor Yellow
            return 'NO_OUTPUT'
        }
    } catch {
        Write-Host "  [ERREUR] $($_.Exception.Message)" -ForegroundColor Red
        return 'ERROR'
    }
}
Write-Host "  Exchange: $exchResult"

# ============================================================
# 3. LANCER LE COLLECTOR IIS
# ============================================================
Write-Host ''
Write-Host '[3/4] Collector IIS...' -ForegroundColor Cyan

$iisResult = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

    $scriptPath = 'C:\Share\lia_collectors\Collect-IIS.ps1'
    if (-not (Test-Path $scriptPath)) {
        Write-Host '  [ERREUR] Collect-IIS.ps1 non trouve' -ForegroundColor Red
        return 'MISSING'
    }

    Set-Location 'C:\Share\lia_collectors'
    try {
        & $scriptPath -OutputPath 'C:\Share\iis_cis_config.json'
        if (Test-Path 'C:\Share\iis_cis_config.json') {
            $size = (Get-Item 'C:\Share\iis_cis_config.json').Length
            Write-Host "  [OK] iis_cis_config.json ($([math]::Round($size/1KB,1)) KB)" -ForegroundColor Green
            return 'OK'
        } else {
            Write-Host '  [WARN] Pas de sortie generee' -ForegroundColor Yellow
            return 'NO_OUTPUT'
        }
    } catch {
        Write-Host "  [ERREUR] $($_.Exception.Message)" -ForegroundColor Red
        return 'ERROR'
    }
}
Write-Host "  IIS: $iisResult"

# ============================================================
# 4. RAPATRIER LES RESULTATS
# ============================================================
Write-Host ''
Write-Host '[4/4] Rapatriement des resultats...' -ForegroundColor Cyan

# Exchange
$exchLocalDir = Join-Path $CollectsRoot 'EXCHANGE\real_data'
if (-not (Test-Path $exchLocalDir)) { New-Item -Path $exchLocalDir -ItemType Directory -Force | Out-Null }

$exchJson = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    if (Test-Path 'C:\Share\exchange_events.json') {
        Get-Content 'C:\Share\exchange_events.json' -Raw
    } else { '' }
}
if ($exchJson) {
    Set-Content -Path (Join-Path $exchLocalDir 'exchange_events.json') -Value $exchJson -Encoding UTF8
    Write-Host "  [OK] exchange_events.json -> collects/EXCHANGE/real_data/" -ForegroundColor Green
} else {
    Write-Host '  [SKIP] Pas de donnees Exchange' -ForegroundColor Yellow
}

# IIS
$iisLocalDir = Join-Path $CollectsRoot 'iis\real_data'
if (-not (Test-Path $iisLocalDir)) { New-Item -Path $iisLocalDir -ItemType Directory -Force | Out-Null }

$iisJson = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    if (Test-Path 'C:\Share\iis_cis_config.json') {
        Get-Content 'C:\Share\iis_cis_config.json' -Raw
    } else { '' }
}
if ($iisJson) {
    Set-Content -Path (Join-Path $iisLocalDir 'iis_cis_config.json') -Value $iisJson -Encoding UTF8
    Write-Host "  [OK] iis_cis_config.json -> collects/iis/real_data/" -ForegroundColor Green
} else {
    Write-Host '  [SKIP] Pas de donnees IIS' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  COLLECTE TERMINEE' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host "  Exchange : $exchResult"
Write-Host "  IIS      : $iisResult"
Write-Host ''
Write-Host '  Fichiers locaux :'
if (Test-Path (Join-Path $exchLocalDir 'exchange_events.json')) {
    Write-Host "    $(Join-Path $exchLocalDir 'exchange_events.json')"
}
if (Test-Path (Join-Path $iisLocalDir 'iis_cis_config.json')) {
    Write-Host "    $(Join-Path $iisLocalDir 'iis_cis_config.json')"
}
pause
