<#
.SYNOPSIS
    Configure des vulnerabilites IIS realistes pour le lab AD
.DESCRIPTION
    Ajoute des configurations IIS volontairement dangereuses detectables
    par les outils d'audit (PingCastle, Nessus, Qualys, ANSSI ADS).

    Vulnerabilites injectees :
      1.  Directory Browsing active sur tous les sites
      2.  TLS 1.0 / TLS 1.1 / SSL 3.0 actives (protocoles obsoletes)
      3.  Headers de securite manquants (X-Frame-Options, CSP, HSTS, X-Content-Type)
      4.  WebDAV active (vecteur d'attaque connu)
      5.  Default pages exposees (iisstart.htm)
      6.  Application Pool en LocalSystem (privilege excessif)
      7.  .NET Tracing / Custom Errors OFF (fuite d'informations)
      8.  Certificat auto-signe avec SHA1
      9.  HTTP (pas HTTPS) sur le site principal
      10. FTP anonymous actif
      11. TRACE/TRACK method activee (XST attack)
      12. Server header expose la version IIS
      13. ASP.NET debug mode active
      14. Weak ciphers (RC4, DES, 3DES)
      15. Site avec injection de path traversal possible

.NOTES
    Prerequis : 03_Install-Services.ps1 execute (IIS installe)
    Fait partie de populate/ — appele par 04_Populate-AD.ps1
#>

param(
    [string]$DomainName = "lab.local"
)

Import-Module WebAdministration -ErrorAction SilentlyContinue

Write-Host "`n=== Configuration des vulnerabilites IIS ===" -ForegroundColor Cyan

# ============================================================
# 1. DIRECTORY BROWSING — active sur tous les sites
# ============================================================
Write-Host "[1/15] Directory Browsing active..." -ForegroundColor Yellow
try {
    Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse `
        -Name enabled -Value $true -PSPath 'IIS:\' -ErrorAction Stop
    # Aussi sur le site LabIntranet
    if (Get-Website -Name "LabIntranet" -ErrorAction SilentlyContinue) {
        Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse `
            -Name enabled -Value $true -PSPath 'IIS:\Sites\LabIntranet'
    }
    Write-Host "  [OK] Directory Browsing active globalement" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 2. PROTOCOLES OBSOLETES — TLS 1.0, TLS 1.1, SSL 3.0
# ============================================================
Write-Host "[2/15] Activation des protocoles obsoletes (TLS 1.0, TLS 1.1, SSL 3.0)..." -ForegroundColor Yellow

$protocols = @(
    @{ Name = 'SSL 3.0';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0' },
    @{ Name = 'TLS 1.0';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0' },
    @{ Name = 'TLS 1.1';  Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1' }
)

foreach ($proto in $protocols) {
    foreach ($side in @('Server', 'Client')) {
        $regPath = "$($proto.Path)\$side"
        New-Item -Path $regPath -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $regPath -Name 'Enabled' -Value 1 -Type DWord -ErrorAction SilentlyContinue
        Set-ItemProperty -Path $regPath -Name 'DisabledByDefault' -Value 0 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] $($proto.Name) active" -ForegroundColor Green
}

# ============================================================
# 3. HEADERS DE SECURITE MANQUANTS
# ============================================================
Write-Host "[3/15] Suppression des headers de securite..." -ForegroundColor Yellow
try {
    # Supprimer les headers de securite s'ils existent
    $headersToRemove = @('X-Frame-Options', 'X-Content-Type-Options', 'X-XSS-Protection',
                         'Content-Security-Policy', 'Strict-Transport-Security')
    foreach ($h in $headersToRemove) {
        Remove-WebConfigurationProperty -PSPath 'IIS:\' `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name=$h} -ErrorAction SilentlyContinue
    }
    Write-Host "  [OK] Headers de securite retires" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 4. WEBDAV ACTIVE
# ============================================================
Write-Host "[4/15] Activation de WebDAV..." -ForegroundColor Yellow
try {
    Install-WindowsFeature Web-DAV-Publishing -ErrorAction SilentlyContinue | Out-Null
    Set-WebConfigurationProperty -Filter /system.webServer/webdav/authoring `
        -Name enabled -Value $true -PSPath 'IIS:\' -ErrorAction SilentlyContinue
    # Authoring Rules — permettre a tout le monde d'ecrire
    Add-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/webdav/authoringRules" `
        -Name "." -Value @{users='*';path='*';access='Read,Write,Source'} -ErrorAction SilentlyContinue
    Write-Host "  [OK] WebDAV active avec ecriture pour tous" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 5. DEFAULT PAGES EXPOSEES
# ============================================================
Write-Host "[5/15] Exposition des pages par defaut..." -ForegroundColor Yellow
try {
    # Ajouter des default documents dangereux
    $defaultDocs = @('iisstart.htm', 'default.asp', 'index.php', 'web.config', 'phpinfo.php')
    foreach ($doc in $defaultDocs) {
        Add-WebConfigurationProperty -PSPath 'IIS:\' `
            -Filter "system.webServer/defaultDocument/files" `
            -Name "." -Value @{value=$doc} -ErrorAction SilentlyContinue
    }

    # Creer une page phpinfo simulee (fuite d'infos)
    $infoPage = "C:\inetpub\wwwroot\server-info.html"
    @"
<!DOCTYPE html>
<html><head><title>Server Information</title></head>
<body>
<h1>Server Configuration</h1>
<table border="1">
<tr><td>Server</td><td>$env:COMPUTERNAME</td></tr>
<tr><td>Domain</td><td>$DomainName</td></tr>
<tr><td>OS</td><td>Windows Server 2022</td></tr>
<tr><td>IIS Version</td><td>10.0</td></tr>
<tr><td>.NET Version</td><td>4.8</td></tr>
<tr><td>Internal IP</td><td>192.168.0.10</td></tr>
<tr><td>Admin Email</td><td>admin@$DomainName</td></tr>
<tr><td>LDAP Base</td><td>DC=lab,DC=local</td></tr>
</table>
<!-- DEBUG: Connection string = Server=DC01;Database=LabDB;User=sa;Password=P@ssw0rd123! -->
</body></html>
"@ | Out-File $infoPage -Encoding UTF8

    Write-Host "  [OK] Pages par defaut + server-info.html avec fuite d'infos" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 6. APP POOL EN LOCALSYSTEM (privilege excessif)
# ============================================================
Write-Host "[6/15] App Pool en LocalSystem..." -ForegroundColor Yellow
try {
    # Creer un App Pool vulnerable
    if (-not (Test-Path 'IIS:\AppPools\VulnPool')) {
        New-WebAppPool -Name "VulnPool" -ErrorAction Stop | Out-Null
    }
    Set-ItemProperty 'IIS:\AppPools\VulnPool' -Name processModel.identityType -Value 0  # LocalSystem
    Set-ItemProperty 'IIS:\AppPools\VulnPool' -Name processModel.loadUserProfile -Value $true

    # Aussi mettre le DefaultAppPool en NetworkService (moins grave mais pas ideal)
    Set-ItemProperty 'IIS:\AppPools\DefaultAppPool' -Name processModel.identityType -Value 2  # NetworkService

    Write-Host "  [OK] VulnPool = LocalSystem, DefaultAppPool = NetworkService" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 7. CUSTOM ERRORS OFF (fuite d'infos stack trace)
# ============================================================
Write-Host "[7/15] Custom Errors OFF (DetailedLocalOnly -> Off)..." -ForegroundColor Yellow
try {
    Set-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.web/customErrors" `
        -Name mode -Value "Off" -ErrorAction SilentlyContinue

    Set-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/httpErrors" `
        -Name errorMode -Value "Detailed" -ErrorAction SilentlyContinue

    Write-Host "  [OK] Errors detaillees exposees (stack traces)" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 8. CERTIFICAT AUTO-SIGNE SHA1 (obsolete)
# ============================================================
Write-Host "[8/15] Certificat auto-signe SHA1..." -ForegroundColor Yellow
try {
    $cert = New-SelfSignedCertificate `
        -DnsName "dc01.$DomainName", "dc01", "localhost", "intranet.$DomainName" `
        -CertStoreLocation Cert:\LocalMachine\My `
        -NotAfter (Get-Date).AddYears(10) `
        -KeyLength 1024 `
        -HashAlgorithm SHA1 `
        -KeyExportPolicy Exportable `
        -ErrorAction Stop

    # Binding HTTPS sur le Default Web Site avec ce cert faible
    New-WebBinding -Name "Default Web Site" -Protocol https -Port 443 -ErrorAction SilentlyContinue
    $binding = Get-WebBinding -Name "Default Web Site" -Protocol https -ErrorAction SilentlyContinue
    if ($binding) {
        $binding.AddSslCertificate($cert.Thumbprint, "My")
    }

    Write-Host "  [OK] Cert SHA1/1024-bit sur port 443" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 9. SITE HTTP SANS REDIRECTION HTTPS
# ============================================================
Write-Host "[9/15] HTTP sans redirection HTTPS..." -ForegroundColor Yellow
try {
    # Creer un site sur port 80 sans HTTPS
    $vulnSitePath = "C:\inetpub\vulnsite"
    New-Item -ItemType Directory -Path $vulnSitePath -Force -ErrorAction SilentlyContinue | Out-Null

    @"
<!DOCTYPE html>
<html><head><title>RH Portail - LAB</title></head>
<body>
<h1>Portail RH - LAB.LOCAL</h1>
<form method="POST" action="/login">
    <label>Utilisateur:</label><br>
    <input type="text" name="username"><br>
    <label>Mot de passe:</label><br>
    <input type="password" name="password"><br>
    <input type="submit" value="Connexion">
</form>
<!-- Form login sur HTTP non chiffre = credentials en clair -->
</body></html>
"@ | Out-File "$vulnSitePath\index.html" -Encoding UTF8

    if (Get-Website -Name "RH-Portail" -ErrorAction SilentlyContinue) {
        Remove-Website -Name "RH-Portail"
    }
    New-Website -Name "RH-Portail" -PhysicalPath $vulnSitePath -Port 8081 `
        -ApplicationPool "VulnPool" -ErrorAction Stop | Out-Null

    Write-Host "  [OK] Site RH sur HTTP:8081 (formulaire login en clair)" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 10. FTP ANONYMOUS ACTIF
# ============================================================
Write-Host "[10/15] FTP anonymous actif..." -ForegroundColor Yellow
try {
    $ftpPath = "C:\inetpub\ftproot\public"
    New-Item -ItemType Directory -Path $ftpPath -Force -ErrorAction SilentlyContinue | Out-Null

    # Fichier sensible dans le FTP
    @"
# Configuration de deploiement interne
server=DC01.lab.local
database=LabDB
sa_password=P@ssw0rd123!
ldap_bind=CN=svc_ldap,OU=Services,DC=lab,DC=local
ldap_password=LdapBind2024!
"@ | Out-File "$ftpPath\deploy_config.txt" -Encoding UTF8

    @"
Backup admin credentials:
  admin / AdminBackup2024!
  svc_backup / Backup#Str0ng
"@ | Out-File "$ftpPath\backup_notes.txt" -Encoding UTF8

    if (Get-WebSite -Name "LabFTP" -ErrorAction SilentlyContinue) {
        Remove-Website -Name "LabFTP"
    }

    New-WebFtpSite -Name "LabFTP" -PhysicalPath "C:\inetpub\ftproot" -Port 21 `
        -ErrorAction SilentlyContinue | Out-Null

    # Activer l'authentification anonyme sur FTP
    Set-ItemProperty "IIS:\Sites\LabFTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true -ErrorAction SilentlyContinue
    Set-ItemProperty "IIS:\Sites\LabFTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true -ErrorAction SilentlyContinue

    # Autoriser lecture/ecriture pour anonymous
    Add-WebConfigurationProperty -PSPath 'IIS:\Sites\LabFTP' `
        -Filter "system.ftpServer/security/authorization" `
        -Name "." -Value @{accessType='Allow';users='*';permissions='Read,Write'} -ErrorAction SilentlyContinue

    Write-Host "  [OK] FTP anonymous avec fichiers sensibles (credentials)" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 11. TRACE/TRACK METHOD (XST attack)
# ============================================================
Write-Host "[11/15] TRACE method activee..." -ForegroundColor Yellow
try {
    # Par defaut TRACE est active sur IIS, on s'assure qu'il reste actif
    # En enlevant la restriction
    Remove-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -AtElement @{verb="TRACE"} -ErrorAction SilentlyContinue
    Remove-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -AtElement @{verb="TRACK"} -ErrorAction SilentlyContinue

    Write-Host "  [OK] TRACE/TRACK non bloques" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 12. SERVER HEADER EXPOSE
# ============================================================
Write-Host "[12/15] Server header expose..." -ForegroundColor Yellow
try {
    Set-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/security/requestFiltering" `
        -Name removeServerHeader -Value $false -ErrorAction SilentlyContinue

    # Ajouter un header X-Powered-By ASP.NET (fuite techno)
    Add-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." -Value @{name='X-Powered-By';value='ASP.NET 4.8'} -ErrorAction SilentlyContinue

    Add-WebConfigurationProperty -PSPath 'IIS:\' `
        -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." -Value @{name='X-AspNet-Version';value='4.0.30319'} -ErrorAction SilentlyContinue

    Write-Host "  [OK] Server + X-Powered-By + X-AspNet-Version exposes" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 13. ASP.NET DEBUG MODE
# ============================================================
Write-Host "[13/15] ASP.NET debug mode actif..." -ForegroundColor Yellow
try {
    # web.config global avec debug=true
    $webConfigPath = "C:\inetpub\wwwroot\web.config"
    @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.web>
        <compilation debug="true" targetFramework="4.8" />
        <customErrors mode="Off" />
        <trace enabled="true" localOnly="false" pageOutput="true" />
        <sessionState mode="InProc" timeout="120" />
        <authentication mode="None" />
    </system.web>
    <system.webServer>
        <directoryBrowse enabled="true" />
        <httpErrors errorMode="Detailed" />
        <validation validateIntegratedModeConfiguration="false" />
    </system.webServer>
    <connectionStrings>
        <add name="LabDB" connectionString="Server=DC01;Database=LabDB;User Id=sa;Password=P@ssw0rd123!;" />
        <add name="LDAP" connectionString="LDAP://DC01.lab.local/DC=lab,DC=local" />
    </connectionStrings>
    <appSettings>
        <add key="AdminEmail" value="admin@lab.local" />
        <add key="ApiKey" value="sk-lab-fake-api-key-12345-VULN" />
        <add key="JwtSecret" value="LabSecretKey123!NotSecure" />
    </appSettings>
</configuration>
"@ | Out-File $webConfigPath -Encoding UTF8

    Write-Host "  [OK] Debug ON + trace ON + connection strings exposees" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# 14. WEAK CIPHERS (RC4, DES, 3DES, NULL)
# ============================================================
Write-Host "[14/15] Activation des ciphers faibles..." -ForegroundColor Yellow

$weakCiphers = @(
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\DES 56/56',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168',
    'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\NULL'
)

foreach ($cipher in $weakCiphers) {
    New-Item -Path $cipher -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path $cipher -Name 'Enabled' -Value 0xFFFFFFFF -Type DWord -ErrorAction SilentlyContinue
}
Write-Host "  [OK] RC4, DES, 3DES, NULL actives" -ForegroundColor Green

# ============================================================
# 15. SITE VULNERABLE (path traversal + upload)
# ============================================================
Write-Host "[15/15] Site vulnerable (upload + path traversal)..." -ForegroundColor Yellow
try {
    $vulnAppPath = "C:\inetpub\vulnapp"
    New-Item -ItemType Directory -Path "$vulnAppPath\uploads" -Force -ErrorAction SilentlyContinue | Out-Null

    # Page d'upload sans validation
    @"
<!DOCTYPE html>
<html><head><title>Document Upload - LAB</title></head>
<body>
<h1>Document Management System</h1>
<h2>Upload Document</h2>
<form method="POST" enctype="multipart/form-data" action="/upload.aspx">
    <input type="file" name="document" accept="*/*">
    <input type="submit" value="Upload">
</form>
<h2>Download Document</h2>
<!-- Vulnerable: file parameter not sanitized -> path traversal -->
<form method="GET" action="/download.aspx">
    <input type="text" name="file" placeholder="document.pdf" size="50">
    <input type="submit" value="Download">
</form>
<hr>
<p><small>Internal use only - LAB.LOCAL IT Department</small></p>
</body></html>
"@ | Out-File "$vulnAppPath\index.html" -Encoding UTF8

    # Fichier sensible accessible via path traversal
    @"
# Internal IT Credentials - DO NOT SHARE
DC Admin: LAB\adm.it / Adm1nIT2024!
SQL SA: sa / P@ssw0rd123!
LDAP Bind: svc_ldap / LdapBind2024!
Backup Key: AES256-BACKUP-KEY-LAB-2024
WiFi PSK: LabWifi2024!
"@ | Out-File "$vulnAppPath\uploads\internal_creds.txt" -Encoding UTF8

    if (Get-Website -Name "DocManager" -ErrorAction SilentlyContinue) {
        Remove-Website -Name "DocManager"
    }
    New-Website -Name "DocManager" -PhysicalPath $vulnAppPath -Port 8082 `
        -ApplicationPool "VulnPool" -ErrorAction Stop | Out-Null

    # Activer directory browsing sur uploads
    Set-WebConfigurationProperty -Filter /system.webServer/directoryBrowse `
        -Name enabled -Value $true -PSPath "IIS:\Sites\DocManager"

    Write-Host "  [OK] DocManager sur HTTP:8082 (upload + path traversal + dir browsing)" -ForegroundColor Green
} catch { Write-Host "  [WARN] $_" -ForegroundColor DarkYellow }

# ============================================================
# RESUME
# ============================================================
Write-Host "`n============================================" -ForegroundColor Cyan
Write-Host "  VULNERABILITES IIS INJECTEES" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  1.  Directory Browsing actif" -ForegroundColor White
Write-Host "  2.  SSL 3.0 / TLS 1.0 / TLS 1.1 actifs" -ForegroundColor White
Write-Host "  3.  Headers securite manquants (CSP, HSTS, X-Frame)" -ForegroundColor White
Write-Host "  4.  WebDAV actif (ecriture pour tous)" -ForegroundColor White
Write-Host "  5.  Pages par defaut + fuite server-info" -ForegroundColor White
Write-Host "  6.  App Pool LocalSystem (privilege max)" -ForegroundColor White
Write-Host "  7.  Errors detaillees (stack traces exposees)" -ForegroundColor White
Write-Host "  8.  Certificat SHA1 / 1024-bit" -ForegroundColor White
Write-Host "  9.  Formulaire login sur HTTP (port 8081)" -ForegroundColor White
Write-Host "  10. FTP anonymous + fichiers sensibles" -ForegroundColor White
Write-Host "  11. TRACE/TRACK method non bloquee" -ForegroundColor White
Write-Host "  12. Server/X-Powered-By headers exposes" -ForegroundColor White
Write-Host "  13. ASP.NET debug + trace + connection strings" -ForegroundColor White
Write-Host "  14. Ciphers faibles (RC4, DES, 3DES, NULL)" -ForegroundColor White
Write-Host "  15. Site upload sans validation (port 8082)" -ForegroundColor White
Write-Host ""
Write-Host "  Sites web :" -ForegroundColor Gray
Write-Host "    http://192.168.0.10:8080   - LabIntranet" -ForegroundColor Gray
Write-Host "    http://192.168.0.10:8081   - RH Portail (login HTTP)" -ForegroundColor Gray
Write-Host "    http://192.168.0.10:8082   - DocManager (upload vuln)" -ForegroundColor Gray
Write-Host "    https://192.168.0.10:443   - Default (cert SHA1)" -ForegroundColor Gray
Write-Host "    ftp://192.168.0.10:21      - FTP anonymous" -ForegroundColor Gray
Write-Host "============================================" -ForegroundColor Cyan
