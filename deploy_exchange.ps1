#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Deploie Exchange 2019 Management Tools dans la VM via PowerShell Direct
.DESCRIPTION
    1. Monte l'ISO Exchange sur la VM Hyper-V (DVD drive)
    2. Copie le script 05_Install-Exchange.ps1 dans la VM
    3. Execute le script dans la VM via PowerShell Direct
.NOTES
    Executer sur l'HOTE en admin
#>
param(
    [string]$VMName  = 'DC01-LAB',
    [string]$Password = '',
    [string]$ISOPath = ''
)

$ErrorActionPreference = 'Stop'

# Charger config
if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

# Trouver l'ISO Exchange
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    $searchPaths = @(
        (Join-Path $env:USERPROFILE 'Downloads')
        (Join-Path $env:USERPROFILE 'Desktop')
        'E:\'
        'D:\'
    )
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter 'ExchangeServer*.iso' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) { $ISOPath = $found.FullName; break }
        }
    }
}
if (-not $ISOPath -or -not (Test-Path $ISOPath)) {
    Write-Host '[ERREUR] ISO Exchange introuvable' -ForegroundColor Red
    $ISOPath = Read-Host 'Chemin vers l ISO Exchange 2019'
}
Write-Host ('[*] ISO : ' + $ISOPath) -ForegroundColor Cyan

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

# ============================================================
# 1. MONTER L'ISO SUR LA VM (DVD DRIVE HYPER-V)
# ============================================================
Write-Host ''
Write-Host '[1/4] Montage ISO sur la VM via Hyper-V...' -ForegroundColor Cyan

# Ajouter un DVD drive si absent
$dvd = Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue
if (-not $dvd) {
    Add-VMDvdDrive -VMName $VMName
    $dvd = Get-VMDvdDrive -VMName $VMName
}
Set-VMDvdDrive -VMName $VMName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $ISOPath
Write-Host '  [OK] ISO montee sur DVD drive de la VM' -ForegroundColor Green

# ============================================================
# 2. COPIER LE SCRIPT DANS LA VM
# ============================================================
Write-Host ''
Write-Host '[2/4] Copie du script dans la VM...' -ForegroundColor Cyan

$scriptContent = Get-Content (Join-Path $PSScriptRoot '05_Install-Exchange.ps1') -Raw

Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($content)
    $dir = 'C:\Share\ad_lab'
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    Set-Content -Path 'C:\Share\ad_lab\05_Install-Exchange.ps1' -Value $content -Encoding UTF8
} -ArgumentList $scriptContent

Write-Host '  [OK] Script copie' -ForegroundColor Green

# ============================================================
# 3. DETECTER LA LETTRE DU DVD DANS LA VM
# ============================================================
Write-Host ''
Write-Host '[3/4] Detection du DVD dans la VM...' -ForegroundColor Cyan

$dvdLetter = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    $cd = Get-Volume | Where-Object { $_.DriveType -eq 'CD-ROM' -and $_.Size -gt 0 } | Select-Object -First 1
    if ($cd) { return $cd.DriveLetter }
    # Fallback
    $drives = Get-PSDrive -PSProvider FileSystem | Where-Object { Test-Path ($_.Root + 'Setup.exe') }
    if ($drives) { return $drives[0].Name }
    return $null
}

if (-not $dvdLetter) {
    Write-Host '  [ERREUR] DVD non detecte dans la VM' -ForegroundColor Red
    exit 1
}
Write-Host ('  [OK] DVD detecte sur ' + $dvdLetter + ':\') -ForegroundColor Green

# ============================================================
# 4. LANCER L'INSTALLATION DANS LA VM
# ============================================================
Write-Host ''
Write-Host '[4/4] Lancement de l installation Exchange dans la VM...' -ForegroundColor Cyan
Write-Host '  Cela peut prendre 30-60 minutes...' -ForegroundColor Yellow
Write-Host ''

Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    param($dvdLetter)
    Set-ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue

    $isoPath = $dvdLetter + ':\'
    $setupExe = $dvdLetter + ':\Setup.exe'

    if (-not (Test-Path $setupExe)) {
        Write-Host ('[ERREUR] Setup.exe introuvable sur ' + $isoPath) -ForegroundColor Red
        return
    }

    Import-Module ServerManager -ErrorAction SilentlyContinue

    # Prerequis Windows Features
    Write-Host '[1/5] Installation des prerequis Windows...' -ForegroundColor Cyan
    $features = @(
        'NET-Framework-45-Features','Server-Media-Foundation','RPC-over-HTTP-proxy',
        'RSAT-Clustering','RSAT-Clustering-CmdInterface','RSAT-Clustering-Mgmt',
        'RSAT-Clustering-PowerShell','WAS-Process-Model','Web-Asp-Net45',
        'Web-Basic-Auth','Web-Client-Auth','Web-Digest-Auth','Web-Dir-Browsing',
        'Web-Dyn-Compression','Web-Http-Errors','Web-Http-Logging',
        'Web-Http-Redirect','Web-Http-Tracing','Web-ISAPI-Ext','Web-ISAPI-Filter',
        'Web-Lgcy-Mgmt-Console','Web-Metabase','Web-Mgmt-Console','Web-Mgmt-Service',
        'Web-Net-Ext45','Web-Request-Monitor','Web-Server','Web-Stat-Compression',
        'Web-Static-Content','Web-Windows-Auth','Web-WMI',
        'Windows-Identity-Foundation','RSAT-ADDS'
    )
    foreach ($f in $features) {
        Install-WindowsFeature $f -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Host '  [OK] Features installees' -ForegroundColor Green

    # UCMA 4.0 (inclus dans le media Exchange)
    Write-Host '[2/5] Installation UCMA 4.0...' -ForegroundColor Cyan
    $ucmaPath = $dvdLetter + ':\UCMARedist\Setup.exe'
    if (Test-Path $ucmaPath) {
        Start-Process -FilePath $ucmaPath -ArgumentList '/quiet /norestart' -Wait -NoNewWindow
        Write-Host '  [OK] UCMA installe' -ForegroundColor Green
    } else {
        Write-Host '  [SKIP] UCMA non trouve dans le media' -ForegroundColor Yellow
    }

    # PrepareSchema
    Write-Host '[3/5] PrepareSchema (extension AD)...' -ForegroundColor Cyan
    Write-Host '  Peut prendre 5-10 min...' -ForegroundColor Gray
    $proc = Start-Process -FilePath $setupExe -ArgumentList '/PrepareSchema /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF' -Wait -PassThru -NoNewWindow
    Write-Host ('  Exit code: ' + $proc.ExitCode) -ForegroundColor $(if ($proc.ExitCode -eq 0) {'Green'} else {'Yellow'})

    # PrepareAD
    Write-Host '[4/5] PrepareAD (organisation LabOrg)...' -ForegroundColor Cyan
    $proc = Start-Process -FilePath $setupExe -ArgumentList '/PrepareAD /OrganizationName:LabOrg /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF' -Wait -PassThru -NoNewWindow
    Write-Host ('  Exit code: ' + $proc.ExitCode) -ForegroundColor $(if ($proc.ExitCode -eq 0) {'Green'} else {'Yellow'})

    # Management Tools
    Write-Host '[5/5] Installation Management Tools...' -ForegroundColor Cyan
    Write-Host '  Peut prendre 15-30 min...' -ForegroundColor Gray
    $proc = Start-Process -FilePath $setupExe -ArgumentList '/Mode:Install /Roles:ManagementTools /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF' -Wait -PassThru -NoNewWindow
    Write-Host ('  Exit code: ' + $proc.ExitCode) -ForegroundColor $(if ($proc.ExitCode -eq 0) {'Green'} else {'Yellow'})

    # Vulnerabilites Exchange
    Write-Host ''
    Write-Host '=== Configuration des vulnerabilites Exchange ===' -ForegroundColor Cyan

    Import-Module ActiveDirectory -ErrorAction SilentlyContinue
    $domainDN = (Get-ADDomain).DistinguishedName

    # WriteDacl
    Write-Host '  -> WriteDacl sur racine domaine...' -ForegroundColor Gray
    try {
        $exchGroup = Get-ADGroup 'Exchange Windows Permissions' -ErrorAction SilentlyContinue
        if ($exchGroup) {
            $adPath = 'AD:\' + $domainDN
            $acl = Get-Acl $adPath
            $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
                $exchGroup.SID, 'WriteDacl', 'Allow', 'All', [guid]::Empty
            )
            $acl.AddAccessRule($ace)
            Set-Acl $adPath $acl
            Write-Host '  [OK] CVE-2019-1136 - WriteDacl' -ForegroundColor Green
        }
    } catch {
        $msg = $_.Exception.Message; Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow
    }

    # svc_exchange Kerberoastable
    Write-Host '  -> svc_exchange Kerberoastable...' -ForegroundColor Gray
    try {
        $svcExch = Get-ADUser 'svc_exchange' -ErrorAction SilentlyContinue
        if (-not $svcExch) {
            $ouPath = 'OU=Services,OU=Tier0,' + $domainDN
            if (-not (Get-ADOrganizationalUnit -Filter {Name -eq 'Services'} -SearchBase ('OU=Tier0,' + $domainDN) -ErrorAction SilentlyContinue)) {
                $ouPath = $domainDN
            }
            New-ADUser -Name 'svc_exchange' -SamAccountName 'svc_exchange' `
                -UserPrincipalName ('svc_exchange@' + (Get-ADDomain).DNSRoot) `
                -Path $ouPath `
                -AccountPassword (ConvertTo-SecureString 'Exchange2019!' -AsPlainText -Force) `
                -Enabled $true -PasswordNeverExpires $true `
                -Description 'Exchange Service Account (LAB)' `
                -ErrorAction SilentlyContinue
        }
        Set-ADUser 'svc_exchange' -ServicePrincipalNames @{Add='exchangeMDB/DC01.lab.local'}
        Add-ADGroupMember 'Organization Management' -Members 'svc_exchange' -ErrorAction SilentlyContinue
        Write-Host '  [OK] svc_exchange + SPN + OrgManagement' -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message; Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow
    }

    # Exchange Trusted Subsystem dans DA
    Write-Host '  -> Exchange Trusted Subsystem dans Domain Admins...' -ForegroundColor Gray
    try {
        Add-ADGroupMember 'Domain Admins' -Members 'Exchange Trusted Subsystem' -ErrorAction SilentlyContinue
        Write-Host '  [OK] Privilege escalation Exchange' -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message; Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow
    }

    # OWA simule
    Write-Host '  -> OWA simule sur HTTP...' -ForegroundColor Gray
    try {
        Import-Module WebAdministration -ErrorAction SilentlyContinue
        $owaPath = 'C:\inetpub\owa'
        New-Item -Path $owaPath -ItemType Directory -Force | Out-Null
        $html = '<html><head><title>Outlook Web App</title></head><body><h1>OWA - LAB</h1><form method=POST><input name=user><br><input type=password name=pass><br><button>Login</button></form></body></html>'
        Set-Content -Path (Join-Path $owaPath 'index.html') -Value $html
        $existing = Get-Website -Name 'OWA-LAB' -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-Website -Name 'OWA-LAB' -PhysicalPath $owaPath -Port 8443 -Force | Out-Null
        }
        Write-Host '  [OK] OWA sur http://192.168.0.10:8443' -ForegroundColor Green
    } catch {
        $msg = $_.Exception.Message; Write-Host ('  [WARN] ' + $msg) -ForegroundColor Yellow
    }

    Write-Host ''
    Write-Host '================================================' -ForegroundColor Cyan
    Write-Host '  EXCHANGE - TERMINE' -ForegroundColor Cyan
    Write-Host '================================================' -ForegroundColor Cyan

} -ArgumentList $dvdLetter

# Demonter l'ISO du DVD
Write-Host ''
Write-Host 'Demontage ISO du DVD...' -ForegroundColor Gray
Set-VMDvdDrive -VMName $VMName -ControllerNumber $dvd.ControllerNumber -ControllerLocation $dvd.ControllerLocation -Path $null -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  DEPLOIEMENT EXCHANGE TERMINE' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
pause
