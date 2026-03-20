#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe Exchange 2019 Management Tools + vulnerabilites
.DESCRIPTION
    1. Installe les prerequis (.NET 4.8, VC++ Redist, RSAT)
    2. Etend le schema AD avec les attributs Exchange
    3. Installe les Management Tools (pas de mailbox)
    4. Configure des vulnerabilites detectables par les collecteurs
.NOTES
    Executer DANS la VM (DC01-LAB), apres 02_Install-ADDS.ps1
    Necessite l'ISO Exchange 2019 CU14 (ou plus recent)
    Telecharger : https://www.microsoft.com/en-us/download/details.aspx?id=104131
#>
param(
    [string]$ExchangeISOPath = '',
    [string]$DomainName = 'lab.local'
)

$ErrorActionPreference = 'Continue'

Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  INSTALLATION EXCHANGE 2019 MANAGEMENT TOOLS' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''

# ============================================================
# 1. TROUVER L'ISO EXCHANGE
# ============================================================
if (-not $ExchangeISOPath -or -not (Test-Path $ExchangeISOPath)) {
    # Chercher sur le bureau, downloads, C:\Share, E:\
    $searchPaths = @(
        (Join-Path $env:USERPROFILE 'Desktop')
        (Join-Path $env:USERPROFILE 'Downloads')
        'C:\Share'
        'E:\'
        'D:\'
    )
    foreach ($sp in $searchPaths) {
        if (Test-Path $sp) {
            $found = Get-ChildItem -Path $sp -Filter 'ExchangeServer*.iso' -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                $ExchangeISOPath = $found.FullName
                Write-Host ('[*] ISO trouvee : ' + $ExchangeISOPath) -ForegroundColor Green
                break
            }
        }
    }
}

if (-not $ExchangeISOPath -or -not (Test-Path $ExchangeISOPath)) {
    Write-Host '[!] ISO Exchange 2019 non trouvee.' -ForegroundColor Red
    Write-Host '    Telechargez-la depuis :' -ForegroundColor Yellow
    Write-Host '    https://www.microsoft.com/en-us/download/details.aspx?id=104131' -ForegroundColor Yellow
    Write-Host ''
    $ExchangeISOPath = Read-Host 'Chemin vers l ISO Exchange 2019'
    if (-not (Test-Path $ExchangeISOPath)) {
        Write-Host '[ERREUR] Fichier introuvable. Abandon.' -ForegroundColor Red
        exit 1
    }
}

# ============================================================
# 2. PREREQUIS
# ============================================================
Write-Host ''
Write-Host '[1/6] Installation des prerequis...' -ForegroundColor Cyan

# RSAT Tools
Write-Host '  -> RSAT-ADDS Tools...' -ForegroundColor Gray
Install-WindowsFeature RSAT-ADDS -ErrorAction SilentlyContinue | Out-Null

# IIS Management (requis par Exchange)
Write-Host '  -> IIS Management Console...' -ForegroundColor Gray
Install-WindowsFeature Web-Mgmt-Console -ErrorAction SilentlyContinue | Out-Null

# .NET Framework 4.8 (deja inclus dans Server 2019+)
Write-Host '  -> Verification .NET Framework...' -ForegroundColor Gray
$dotnet = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue
if ($dotnet.Release -ge 528040) {
    Write-Host '  [OK] .NET 4.8+ detecte' -ForegroundColor Green
} else {
    Write-Host '  [WARN] .NET 4.8 peut etre requis' -ForegroundColor Yellow
}

# Visual C++ Redistributable (souvent deja present)
Write-Host '  -> VC++ Redistributable check...' -ForegroundColor Gray
$vcRedist = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' -ErrorAction SilentlyContinue
if ($vcRedist) {
    Write-Host '  [OK] VC++ Redist detecte' -ForegroundColor Green
} else {
    Write-Host '  [WARN] VC++ 2012/2013 peut etre requis — sera installe par Exchange Setup' -ForegroundColor Yellow
}

# UCMA 4.0 Runtime
Write-Host '  -> Installation des features Windows requises...' -ForegroundColor Gray
$features = @(
    'NET-Framework-45-Features'
    'Server-Media-Foundation'
    'RPC-over-HTTP-proxy'
    'RSAT-Clustering'
    'RSAT-Clustering-CmdInterface'
    'RSAT-Clustering-Mgmt'
    'RSAT-Clustering-PowerShell'
    'WAS-Process-Model'
    'Web-Asp-Net45'
    'Web-Basic-Auth'
    'Web-Client-Auth'
    'Web-Digest-Auth'
    'Web-Dir-Browsing'
    'Web-Dyn-Compression'
    'Web-Http-Errors'
    'Web-Http-Logging'
    'Web-Http-Redirect'
    'Web-Http-Tracing'
    'Web-ISAPI-Ext'
    'Web-ISAPI-Filter'
    'Web-Lgcy-Mgmt-Console'
    'Web-Metabase'
    'Web-Mgmt-Console'
    'Web-Mgmt-Service'
    'Web-Net-Ext45'
    'Web-Request-Monitor'
    'Web-Server'
    'Web-Stat-Compression'
    'Web-Static-Content'
    'Web-Windows-Auth'
    'Web-WMI'
    'Windows-Identity-Foundation'
    'RSAT-ADDS'
)
foreach ($f in $features) {
    Install-WindowsFeature $f -ErrorAction SilentlyContinue | Out-Null
}
Write-Host '  [OK] Features Windows installees' -ForegroundColor Green

# ============================================================
# 3. MONTER L'ISO ET PREPARER LE SCHEMA
# ============================================================
Write-Host ''
Write-Host '[2/6] Montage de l ISO Exchange...' -ForegroundColor Cyan
$mount = Mount-DiskImage -ImagePath $ExchangeISOPath -PassThru
$driveLetter = ($mount | Get-Volume).DriveLetter
$setupPath = $driveLetter + ':\Setup.exe'

if (-not (Test-Path $setupPath)) {
    Write-Host ('[ERREUR] Setup.exe introuvable sur ' + $driveLetter + ':\') -ForegroundColor Red
    Dismount-DiskImage -ImagePath $ExchangeISOPath
    exit 1
}
Write-Host ('  [OK] ISO montee sur ' + $driveLetter + ':\') -ForegroundColor Green

# ============================================================
# 4. PREPARER LE SCHEMA AD
# ============================================================
Write-Host ''
Write-Host '[3/6] Preparation du schema AD (PrepareSchema)...' -ForegroundColor Cyan
Write-Host '  Cela peut prendre 5-10 minutes...' -ForegroundColor Gray
$proc = Start-Process -FilePath $setupPath -ArgumentList '/PrepareSchema /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF' -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -eq 0) {
    Write-Host '  [OK] Schema AD etendu' -ForegroundColor Green
} else {
    Write-Host ('  [WARN] PrepareSchema exit code: ' + $proc.ExitCode + ' - verifier les logs') -ForegroundColor Yellow
}

Write-Host ''
Write-Host '[4/6] Preparation du domaine AD (PrepareAD)...' -ForegroundColor Cyan
$proc = Start-Process -FilePath $setupPath -ArgumentList "/PrepareAD /OrganizationName:LabOrg /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF" -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -eq 0) {
    Write-Host '  [OK] Domaine prepare pour Exchange' -ForegroundColor Green
} else {
    Write-Host ('  [WARN] PrepareAD exit code: ' + $proc.ExitCode + ' - verifier les logs') -ForegroundColor Yellow
}

# ============================================================
# 5. INSTALLER MANAGEMENT TOOLS
# ============================================================
Write-Host ''
Write-Host '[5/6] Installation Management Tools (pas de mailbox)...' -ForegroundColor Cyan
Write-Host '  Cela peut prendre 15-30 minutes...' -ForegroundColor Gray
$proc = Start-Process -FilePath $setupPath -ArgumentList '/Mode:Install /Roles:ManagementTools /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF' -Wait -PassThru -NoNewWindow
if ($proc.ExitCode -eq 0) {
    Write-Host '  [OK] Exchange Management Tools installes' -ForegroundColor Green
} else {
    Write-Host ('  [WARN] Install exit code: ' + $proc.ExitCode + ' - verifier les logs') -ForegroundColor Yellow
}

# Demonter l'ISO
Dismount-DiskImage -ImagePath $ExchangeISOPath -ErrorAction SilentlyContinue

# ============================================================
# 6. VULNERABILITES EXCHANGE
# ============================================================
Write-Host ''
Write-Host '[6/6] Configuration des vulnerabilites Exchange...' -ForegroundColor Cyan

Import-Module ActiveDirectory -ErrorAction SilentlyContinue
$domainDN = (Get-ADDomain).DistinguishedName

# --- 6a. Exchange Shared Permissions (WriteDacl sur racine) ---
Write-Host '  -> Shared Permissions (WriteDacl)...' -ForegroundColor Gray
try {
    $exchGroup = Get-ADGroup 'Exchange Windows Permissions' -ErrorAction SilentlyContinue
    if ($exchGroup) {
        $adPath = 'AD:\' + $domainDN
        $acl = Get-Acl $adPath
        $sid = $exchGroup.SID
        $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $sid, 'WriteDacl', 'Allow', 'All', [guid]::Empty
        )
        $acl.AddAccessRule($ace)
        Set-Acl $adPath $acl
        Write-Host '  [OK] Exchange Windows Permissions = WriteDacl sur domaine (CVE-2019-1136)' -ForegroundColor Green
    }
} catch {
    $msg = $_.Exception.Message; Write-Host ('  [WARN] WriteDacl: ' + $msg) -ForegroundColor Yellow
}

# --- 6b. Compte Exchange avec SPN (Kerberoasting) ---
Write-Host '  -> Service Account Kerberoastable...' -ForegroundColor Gray
try {
    $svcExch = Get-ADUser 'svc_exchange' -ErrorAction SilentlyContinue
    if (-not $svcExch) {
        $upn = 'svc_exchange@' + $DomainName
        $ouPath = 'OU=Services,OU=Tier0,' + $domainDN
        New-ADUser -Name 'svc_exchange' -SamAccountName 'svc_exchange' `
            -UserPrincipalName $upn `
            -Path $ouPath `
            -AccountPassword (ConvertTo-SecureString 'Exchange2019!' -AsPlainText -Force) `
            -Enabled $true -PasswordNeverExpires $true `
            -Description 'Exchange Service Account (LAB)' `
            -ErrorAction SilentlyContinue
    }
    Set-ADUser 'svc_exchange' -ServicePrincipalNames @{Add='exchangeMDB/DC01.lab.local'}
    Add-ADGroupMember 'Organization Management' -Members 'svc_exchange' -ErrorAction SilentlyContinue
    Write-Host '  [OK] svc_exchange avec SPN + Organization Management' -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message; Write-Host ('  [WARN] svc_exchange: ' + $msg) -ForegroundColor Yellow
}

# --- 6c. AutoDiscover SCP mal securise ---
Write-Host '  -> AutoDiscover SCP expose...' -ForegroundColor Gray
try {
    $svcCN = 'CN=Microsoft Exchange,CN=Services,CN=Configuration,' + $domainDN
    $scpExists = Get-ADObject -SearchBase $svcCN -Filter {Name -eq 'AutodiscoverHTTP'} -ErrorAction SilentlyContinue
    if (-not $scpExists) {
        New-ADObject -Name 'AutodiscoverHTTP' -Type 'serviceConnectionPoint' `
            -Path $svcCN `
            -OtherAttributes @{
                'serviceBindingInformation' = 'http://dc01.lab.local/autodiscover/autodiscover.xml'
                'keywords' = @('67661D7F-8FC4-4fa7-BFAC-E1D7794C1F68','77378F46-2C66-4aa9-A6A6-3E7A48B19596')
            } -ErrorAction SilentlyContinue
    }
    Write-Host '  [OK] AutoDiscover SCP sur HTTP (pas HTTPS)' -ForegroundColor Green
} catch {
    $msg = $_.Exception.Message; Write-Host ('  [WARN] AutoDiscover SCP: ' + $msg) -ForegroundColor Yellow
}

# --- 6d. OWA sans forcer TLS (si IIS present) ---
Write-Host '  -> OWA simule sur HTTP...' -ForegroundColor Gray
try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-Command New-WebSite -ErrorAction SilentlyContinue) {
        $owaPath = 'C:\inetpub\owa'
        New-Item -Path $owaPath -ItemType Directory -Force | Out-Null
        $owaHtml = '<html><head><title>Outlook Web App</title></head><body><h1>Outlook Web App - LAB</h1><form method=POST action=/owa/auth.owa><input name=username placeholder=user><br><input type=password name=password placeholder=password><br><button type=submit>Sign In</button></form></body></html>'
        $owaIndex = Join-Path $owaPath 'index.html'
        Set-Content -Path $owaIndex -Value $owaHtml
        # Site OWA sur port 8443 HTTP (pas HTTPS = vuln)
        $existing = Get-Website -Name 'OWA-LAB' -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-Website -Name 'OWA-LAB' -PhysicalPath $owaPath -Port 8443 -Force | Out-Null
        }
        Write-Host '  [OK] OWA simule sur http://192.168.0.10:8443 (login en clair)' -ForegroundColor Green
    }
} catch {
    $msg = $_.Exception.Message; Write-Host ('  [WARN] OWA: ' + $msg) -ForegroundColor Yellow
}

# --- 6e. Mailbox exports permission (trop large) ---
Write-Host '  -> Mailbox Import/Export pour tout le monde...' -ForegroundColor Gray
try {
    $exchTrusted = Get-ADGroup 'Exchange Trusted Subsystem' -ErrorAction SilentlyContinue
    if ($exchTrusted) {
        Add-ADGroupMember 'Domain Admins' -Members 'Exchange Trusted Subsystem' -ErrorAction SilentlyContinue
        Write-Host '  [OK] Exchange Trusted Subsystem dans Domain Admins (elevation de privileges)' -ForegroundColor Green
    }
} catch {
    $msg = $_.Exception.Message; Write-Host ('  [WARN] Mailbox Export: ' + $msg) -ForegroundColor Yellow
}

# ============================================================
# RESUME
# ============================================================
Write-Host ''
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  EXCHANGE MANAGEMENT TOOLS - RESUME' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  Schema AD etendu avec attributs Exchange' -ForegroundColor Green
Write-Host '  Management Tools installes (pas de mailbox)' -ForegroundColor Green
Write-Host ''
Write-Host '  Vulnerabilites injectees :' -ForegroundColor Yellow
Write-Host '    1. WriteDacl sur racine domaine (CVE-2019-1136)'
Write-Host '    2. svc_exchange Kerberoastable + Organization Management'
Write-Host '    3. AutoDiscover SCP sur HTTP (pas HTTPS)'
Write-Host '    4. OWA simule sur HTTP:8443 (login en clair)'
Write-Host '    5. Exchange Trusted Subsystem dans Domain Admins'
Write-Host ''
Write-Host '  Sites web :' -ForegroundColor Yellow
Write-Host '    http://192.168.0.10:8443  - OWA (login en clair)'
Write-Host ''
Write-Host '  ISO Exchange : peut etre supprimee' -ForegroundColor Gray
Write-Host '================================================' -ForegroundColor Cyan
pause
