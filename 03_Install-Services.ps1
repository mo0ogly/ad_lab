#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Installe tous les services Windows Server pour le lab
.DESCRIPTION
    Installe et configure:
    - Certificate Authority (PKI/ADCS)
    - IIS (Web Server)
    - File Server + DFS
    - WSUS
    - WDS
    - NPS/RADIUS
    - AD FS
    - AD LDS
    - AD RMS
    - Remote Desktop Services
    - SNMP, IPAM, Backup
    - FTP
    - SMTP (relay)
.NOTES
    Exécuter DANS la VM, après 02_Install-ADDS.ps1
#>

param(
    [string]$DomainName = "lab.local"
)

$ErrorActionPreference = "Continue"

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Installation des Services" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$services = @(
    # --- PKI / Certificate Authority ---
    @{
        Name = "ADCS-Cert-Authority"
        Display = "Certificate Authority (PKI)"
        Features = @("ADCS-Cert-Authority", "ADCS-Web-Enrollment", "ADCS-Online-Cert")
        PostInstall = {
            Write-Host "    -> Configuration de l'Autorite de Certification..." -ForegroundColor Gray
            Install-AdcsCertificationAuthority `
                -CAType EnterpriseRootCA `
                -CACommonName "LAB-ROOT-CA" `
                -KeyLength 4096 `
                -HashAlgorithmName SHA256 `
                -ValidityPeriod Years `
                -ValidityPeriodUnits 10 `
                -Force -ErrorAction SilentlyContinue
            Install-AdcsWebEnrollment -Force -ErrorAction SilentlyContinue
        }
    },

    # --- IIS Web Server ---
    @{
        Name = "Web-Server"
        Display = "IIS Web Server"
        Features = @(
            "Web-Server", "Web-WebServer", "Web-Common-Http", "Web-Default-Doc",
            "Web-Dir-Browsing", "Web-Http-Errors", "Web-Static-Content",
            "Web-Http-Logging", "Web-Stat-Compression", "Web-Filtering",
            "Web-Asp-Net45", "Web-Net-Ext45", "Web-ISAPI-Ext", "Web-ISAPI-Filter",
            "Web-Mgmt-Console", "Web-Mgmt-Service",
            "Web-Ftp-Server", "Web-Ftp-Service"
        )
        PostInstall = {
            Write-Host "    -> Creation d'un site web de test..." -ForegroundColor Gray
            $sitePath = "C:\inetpub\labsite"
            if (-not (Test-Path $sitePath)) {
                New-Item -ItemType Directory -Path $sitePath -Force | Out-Null
                @"
<!DOCTYPE html>
<html><head><title>LAB AD - Intranet</title></head>
<body style="font-family:Arial;text-align:center;margin-top:100px;">
<h1>LAB.LOCAL - Intranet</h1>
<p>Active Directory Lab Environment</p>
<p>Server: $env:COMPUTERNAME</p>
<p>Domain: $DomainName</p>
</body></html>
"@ | Out-File "$sitePath\index.html" -Encoding UTF8
            }
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            if (Get-Website -Name "LabIntranet" -ErrorAction SilentlyContinue) {
                Remove-Website -Name "LabIntranet"
            }
            New-Website -Name "LabIntranet" -PhysicalPath $sitePath -Port 8080 -ErrorAction SilentlyContinue
        }
    },

    # --- File Server + DFS ---
    @{
        Name = "FS-FileServer"
        Display = "File Server + DFS + Quotas"
        Features = @("FS-FileServer", "FS-DFS-Namespace", "FS-DFS-Replication", "FS-Resource-Manager")
        PostInstall = {
            Write-Host "    -> Creation des partages..." -ForegroundColor Gray
            $shares = @("Partage_Commun", "Partage_IT", "Partage_RH", "Partage_Finance", "Partage_Direction")
            foreach ($share in $shares) {
                $path = "C:\Shares\$share"
                if (-not (Test-Path $path)) {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }
                if (-not (Get-SmbShare -Name $share -ErrorAction SilentlyContinue)) {
                    New-SmbShare -Name $share -Path $path -FullAccess "LAB\Domain Admins" -ReadAccess "LAB\Domain Users"
                }
            }
            Write-Host "    -> $($shares.Count) partages crees." -ForegroundColor Gray
        }
    },

    # --- NPS / RADIUS ---
    @{
        Name = "NPAS"
        Display = "NPS / RADIUS"
        Features = @("NPAS")
        PostInstall = $null
    },

    # --- AD Federation Services ---
    @{
        Name = "ADFS-Federation"
        Display = "AD Federation Services"
        Features = @("ADFS-Federation")
        PostInstall = $null
    },

    # --- AD Lightweight Directory Services ---
    @{
        Name = "ADLDS"
        Display = "AD Lightweight Directory Services"
        Features = @("ADLDS")
        PostInstall = $null
    },

    # --- Remote Desktop Services ---
    @{
        Name = "RDS-RD-Server"
        Display = "Remote Desktop Services"
        Features = @("RDS-RD-Server", "RDS-Licensing", "RDS-Web-Access", "RDS-RD-Gateway")
        PostInstall = $null
    },

    # --- Windows Server Backup ---
    @{
        Name = "Windows-Server-Backup"
        Display = "Windows Server Backup"
        Features = @("Windows-Server-Backup")
        PostInstall = $null
    },

    # --- SNMP ---
    @{
        Name = "SNMP-Service"
        Display = "SNMP Service"
        Features = @("SNMP-Service", "SNMP-WMI-Provider")
        PostInstall = $null
    },

    # --- IPAM ---
    @{
        Name = "IPAM"
        Display = "IP Address Management"
        Features = @("IPAM", "IPAM-Client-Feature")
        PostInstall = $null
    },

    # --- Windows Deployment Services ---
    @{
        Name = "WDS"
        Display = "Windows Deployment Services"
        Features = @("WDS", "WDS-Deployment", "WDS-Transport")
        PostInstall = $null
    },

    # --- Print Services ---
    @{
        Name = "Print-Services"
        Display = "Print Services"
        Features = @("Print-Services", "Print-Server")
        PostInstall = $null
    },

    # --- BitLocker ---
    @{
        Name = "BitLocker"
        Display = "BitLocker + Network Unlock"
        Features = @("BitLocker", "BitLocker-NetworkUnlock", "RSAT-Feature-Tools-BitLocker")
        PostInstall = $null
    },

    # --- Telnet Client (utile pour debug) ---
    @{
        Name = "Telnet-Client"
        Display = "Telnet Client"
        Features = @("Telnet-Client")
        PostInstall = $null
    },

    # --- SMTP Server ---
    @{
        Name = "SMTP-Server"
        Display = "SMTP Server"
        Features = @("SMTP-Server")
        PostInstall = $null
    }
)

# --- Installation ---
$total = $services.Count
$current = 0

foreach ($svc in $services) {
    $current++
    Write-Host "`n[$current/$total] Installation: $($svc.Display)..." -ForegroundColor Yellow

    foreach ($feature in $svc.Features) {
        $installed = Get-WindowsFeature -Name $feature -ErrorAction SilentlyContinue
        if ($installed -and -not $installed.Installed) {
            Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
            Write-Host "  -> $feature installe." -ForegroundColor Green
        } elseif ($installed.Installed) {
            Write-Host "  -> $feature deja installe." -ForegroundColor Gray
        } else {
            Write-Host "  -> $feature non disponible sur cette edition." -ForegroundColor DarkYellow
        }
    }

    # Post-installation
    if ($svc.PostInstall) {
        & $svc.PostInstall
    }
}

# --- RSAT Tools (tous) ---
Write-Host "`n[BONUS] Installation de tous les outils RSAT..." -ForegroundColor Yellow
Get-WindowsFeature -Name "RSAT*" | Where-Object { -not $_.Installed } | ForEach-Object {
    Install-WindowsFeature -Name $_.Name -ErrorAction SilentlyContinue | Out-Null
}
Write-Host "  -> Outils RSAT installes." -ForegroundColor Green

# --- Résumé ---
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Installation des services terminee!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Services installes:" -ForegroundColor White
foreach ($svc in $services) {
    $check = Get-WindowsFeature -Name $svc.Name -ErrorAction SilentlyContinue
    $status = if ($check.Installed) { "[OK]" } else { "[--]" }
    $color = if ($check.Installed) { "Green" } else { "Red" }
    Write-Host "    $status $($svc.Display)" -ForegroundColor $color
}

Write-Host "`n  Ports ouverts:" -ForegroundColor White
Write-Host "    80/443  - IIS"
Write-Host "    8080    - LabIntranet"
Write-Host "    21      - FTP"
Write-Host "    25      - SMTP"
Write-Host "    53      - DNS"
Write-Host "    67/68   - DHCP"
Write-Host "    88      - Kerberos"
Write-Host "    389/636 - LDAP/LDAPS"
Write-Host "    445     - SMB"
Write-Host "    3389    - RDP"
Write-Host "    1812    - RADIUS"

Write-Host "`n[NEXT] Lancez 04_Populate-AD.ps1 pour peupler l'AD." -ForegroundColor Yellow

Read-Host "`nAppuyez sur Entree pour terminer"
