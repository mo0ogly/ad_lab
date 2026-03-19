<#
.SYNOPSIS
    Vulnerabilites ADCS completes (certificats PKI)
    Anomalies: ESC1, ESC2, ESC3, ESC4, ESC6, ESC8, CA misconfiguration,
    templates dangereux, enrollment agent abuse, EDITF_ATTRIBUTESUBJECTALTNAME2
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[ADCS] Vulnerabilites certificats PKI..." -ForegroundColor Yellow

try {
    $caInstalled = Get-WindowsFeature -Name "ADCS-Cert-Authority"
    if (-not ($caInstalled -and $caInstalled.Installed)) {
        Write-Host "  -> ADCS non installe, skip." -ForegroundColor Gray
        return
    }
} catch { Write-Host "  -> Impossible de verifier ADCS: $_" -ForegroundColor Gray; return }

$configDN = (Get-ADRootDSE).configurationNamingContext
$templatesDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$configDN"
$enrollDN = "CN=Enrollment Services,CN=Public Key Services,CN=Services,$configDN"
$authUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")  # Authenticated Users
$domainUsers = (Get-ADGroup "Domain Users").SID
$enrollGuid = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"  # Certificate-Enrollment

# ============================================================
# [ESC1] Template avec ENROLLEE_SUPPLIES_SUBJECT + Client Auth
# L'utilisateur peut specifier un SAN arbitraire → impersonation
# ============================================================
$esc1Name = "VulnerableWebServer"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc1Name'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $esc1Name -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Vulnerable Web Server"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=1; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("1.3.6.1.5.5.7.3.1","1.3.6.1.5.5.7.3.2")  # Server Auth + Client Auth
            "msPKI-Certificate-Name-Flag"=1          # CT_FLAG_ENROLLEE_SUPPLIES_SUBJECT
            "msPKI-Enrollment-Flag"=0
            "msPKI-RA-Signature"=0                    # Pas de signature RA requise
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        # Enrollment pour Authenticated Users
        $vulnObj = Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc1Name'"
        $acl = Get-Acl "AD:\$($vulnObj.DistinguishedName)"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($authUsers, "ExtendedRight", "Allow", $enrollGuid)))
        Set-Acl "AD:\$($vulnObj.DistinguishedName)" $acl
        Write-Host "  -> [ESC1] VulnerableWebServer: ENROLLEE_SUPPLIES_SUBJECT + Client Auth + Auth Users enroll" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC1: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template ESC1 existe deja." -ForegroundColor Gray }

# ============================================================
# [ESC1-bis] Second template ESC1 plus discret (SubCA-like)
# ============================================================
$esc1bName = "LegacyUserCert"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc1bName'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $esc1bName -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Legacy User Certificate"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=1; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("1.3.6.1.5.5.7.3.2","1.3.6.1.5.5.7.3.4")  # Client Auth + Email Protection
            "msPKI-Certificate-Name-Flag"=1          # ENROLLEE_SUPPLIES_SUBJECT
            "msPKI-Enrollment-Flag"=0
            "msPKI-RA-Signature"=0
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        $obj = Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc1bName'"
        $acl = Get-Acl "AD:\$($obj.DistinguishedName)"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($domainUsers, "ExtendedRight", "Allow", $enrollGuid)))
        Set-Acl "AD:\$($obj.DistinguishedName)" $acl
        Write-Host "  -> [ESC1-bis] LegacyUserCert: ENROLLEE_SUPPLIES_SUBJECT + Domain Users enroll" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC1-bis: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template ESC1-bis existe deja." -ForegroundColor Gray }

# ============================================================
# [ESC2] Template avec Any Purpose EKU ou pas d'EKU
# Un cert sans EKU specifique peut etre utilise pour n'importe quoi
# ============================================================
$esc2Name = "VulnerableAnyPurpose"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc2Name'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $esc2Name -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Vulnerable Any Purpose"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=1; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("2.5.29.37.0")   # anyExtendedKeyUsage OID
            "msPKI-Certificate-Name-Flag"=0
            "msPKI-Enrollment-Flag"=0
            "msPKI-RA-Signature"=0
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        $obj = Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc2Name'"
        $acl = Get-Acl "AD:\$($obj.DistinguishedName)"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($authUsers, "ExtendedRight", "Allow", $enrollGuid)))
        Set-Acl "AD:\$($obj.DistinguishedName)" $acl
        Write-Host "  -> [ESC2] VulnerableAnyPurpose: Any Purpose EKU + Auth Users enroll" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC2: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template ESC2 existe deja." -ForegroundColor Gray }

# ============================================================
# [ESC3] Template Certificate Request Agent (Enrollment Agent)
# Permet de demander des certs au nom d'autres users
# ============================================================
$esc3Name = "VulnerableEnrollAgent"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc3Name'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $esc3Name -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Vulnerable Enrollment Agent"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=2; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("1.3.6.1.4.1.311.20.2.1")  # Certificate Request Agent OID
            "msPKI-Certificate-Name-Flag"=0
            "msPKI-Enrollment-Flag"=0
            "msPKI-RA-Signature"=0                    # Pas de co-signature
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        $obj = Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$esc3Name'"
        $acl = Get-Acl "AD:\$($obj.DistinguishedName)"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($authUsers, "ExtendedRight", "Allow", $enrollGuid)))
        Set-Acl "AD:\$($obj.DistinguishedName)" $acl
        Write-Host "  -> [ESC3] VulnerableEnrollAgent: Certificate Request Agent pour Auth Users" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC3: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template ESC3 existe deja." -ForegroundColor Gray }

# ============================================================
# [ESC4] GenericAll/WriteDACL/WriteOwner sur un template existant
# Permet de modifier le template pour le rendre ESC1
# ============================================================
$webTpl = Get-ADObject -SearchBase $templatesDN -Filter {name -eq "WebServer"} -ErrorAction SilentlyContinue
if ($webTpl) {
    try {
        $acl = Get-Acl "AD:\$($webTpl.DistinguishedName)"
        # GenericAll pour chloe.fournier
        $sid1 = (Get-ADUser "chloe.fournier").SID
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid1, "GenericAll", "Allow")))
        # WriteDACL pour lea.dubois
        $sid2 = (Get-ADUser "lea.dubois").SID
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid2, "WriteDacl", "Allow")))
        # WriteOwner pour hugo.blanc
        $sid3 = (Get-ADUser "hugo.blanc").SID
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid3, "WriteOwner", "Allow")))
        Set-Acl "AD:\$($webTpl.DistinguishedName)" $acl
        Write-Host "  -> [ESC4] GenericAll(chloe.fournier) + WriteDACL(lea.dubois) + WriteOwner(hugo.blanc) sur WebServer" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC4: $_" -ForegroundColor Gray }
}

# ESC4 sur User template aussi
$userTpl = Get-ADObject -SearchBase $templatesDN -Filter {name -eq "User"} -ErrorAction SilentlyContinue
if ($userTpl) {
    try {
        $acl = Get-Acl "AD:\$($userTpl.DistinguishedName)"
        $sid = (Get-ADGroup "GRP_IT_Dev").SID
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericWrite", "Allow")))
        Set-Acl "AD:\$($userTpl.DistinguishedName)" $acl
        Write-Host "  -> [ESC4] GenericWrite(GRP_IT_Dev) sur User template" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur ESC4 User: $_" -ForegroundColor Gray }
}

# ============================================================
# [ESC6] EDITF_ATTRIBUTESUBJECTALTNAME2 sur la CA
# La CA accepte les SAN dans toutes les requetes
# ============================================================
try {
    $caName = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction Stop).Active
    if ($caName) {
        # Activer le flag dangereux
        & certutil -setreg "policy\EditFlags" "+EDITF_ATTRIBUTESUBJECTALTNAME2" 2>$null
        Write-Host "  -> [ESC6] EDITF_ATTRIBUTESUBJECTALTNAME2 active sur CA '$caName'" -ForegroundColor Red
        Write-Host "         Toute requete peut specifier un SAN arbitraire!" -ForegroundColor Red

        # Restart du service pour appliquer
        Restart-Service certsvc -Force -ErrorAction SilentlyContinue
    }
} catch { Write-Host "  -> Erreur ESC6: $_" -ForegroundColor Gray }

# ============================================================
# [ESC8] Web Enrollment HTTP (pas HTTPS) - NTLM relay vers CA
# Si le Web Enrollment est installe en HTTP, on peut relayer NTLM
# ============================================================
try {
    $webEnroll = Get-WindowsFeature -Name "ADCS-Web-Enrollment" -ErrorAction SilentlyContinue
    if ($webEnroll -and $webEnroll.Installed) {
        # Verifier si HTTP est actif (pas force HTTPS)
        $binding = Get-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue | Where-Object { $_.protocol -eq "http" }
        if ($binding) {
            Write-Host "  -> [ESC8] Web Enrollment accessible en HTTP (NTLM relay possible)" -ForegroundColor Red
            Write-Host "         URL: http://$(hostname)/certsrv/" -ForegroundColor Red
        }

        # S'assurer que EPA (Extended Protection for Authentication) est OFF
        try {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            Set-WebConfigurationProperty -pspath 'MACHINE/WEBROOT/APPHOST/Default Web Site/CertSrv' `
                -filter "system.webServer/security/authentication/windowsAuthentication" `
                -name "extendedProtection.tokenChecking" -value "None" -ErrorAction SilentlyContinue
            Write-Host "  -> [ESC8] Extended Protection desactivee sur /certsrv" -ForegroundColor Red
        } catch {}
    } else {
        Write-Host "  -> Web Enrollment non installe, ESC8 skip." -ForegroundColor Gray
    }
} catch { Write-Host "  -> Erreur ESC8: $_" -ForegroundColor Gray }

# ============================================================
# [VULN-CA] Permissions trop larges sur la CA elle-meme
# ============================================================
try {
    $caObj = Get-ADObject -SearchBase $enrollDN -Filter {objectClass -eq "pKIEnrollmentService"} -ErrorAction SilentlyContinue
    if ($caObj) {
        $acl = Get-Acl "AD:\$($caObj.DistinguishedName)"
        # ManageCA pour un user IT
        $sid = (Get-ADUser "nicolas.bernard").SID
        $manageCaGuid = [GUID]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericAll", "Allow")))
        Set-Acl "AD:\$($caObj.DistinguishedName)" $acl
        Write-Host "  -> [VULN-CA] nicolas.bernard GenericAll sur l'objet CA" -ForegroundColor Red
    }
} catch { Write-Host "  -> Erreur VULN-CA: $_" -ForegroundColor Gray }

# ============================================================
# [VULN-CA] CA certificate avec duree trop longue
# ============================================================
try {
    $caConfig = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\CertSvc\Configuration" -ErrorAction SilentlyContinue).Active
    if ($caConfig) {
        $validityPeriod = & certutil -getreg CA\ValidityPeriod 2>$null
        $validityUnits = & certutil -getreg CA\ValidityPeriodUnits 2>$null
        Write-Host "  -> [INFO-CA] CA validity: verifier si > 5 ans (defaut pour issued certs)" -ForegroundColor Yellow
    }
} catch {}

# ============================================================
# [VULN-PKI] Pas de CRL Distribution Point HTTP accessible
# ============================================================
Write-Host "  -> [INFO-PKI] Verifier CDP/AIA HTTP accessibility manuellement" -ForegroundColor Yellow

# ============================================================
# [VULN-PKI] Template avec clef privee exportable
# ============================================================
$exportName = "VulnerableExportable"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$exportName'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $exportName -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Vulnerable Exportable Key"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=1; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("1.3.6.1.5.5.7.3.2")  # Client Auth
            "msPKI-Certificate-Name-Flag"=0
            "msPKI-Enrollment-Flag"=0
            "msPKI-Private-Key-Flag"=16                     # CT_FLAG_EXPORTABLE_KEY
            "msPKI-RA-Signature"=0
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        $obj = Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$exportName'"
        $acl = Get-Acl "AD:\$($obj.DistinguishedName)"
        $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($authUsers, "ExtendedRight", "Allow", $enrollGuid)))
        Set-Acl "AD:\$($obj.DistinguishedName)" $acl
        Write-Host "  -> [VULN-PKI] VulnerableExportable: cle privee exportable + Auth Users" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur VulnerableExportable: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template Exportable existe deja." -ForegroundColor Gray }

# ============================================================
# [VULN-PKI] Template avec duree de validite excessive
# ============================================================
$longName = "LongValidityCert"
if (-not (Get-ADObject -SearchBase $templatesDN -Filter "name -eq '$longName'" -ErrorAction SilentlyContinue)) {
    try {
        New-ADObject -Name $longName -Type "pKICertificateTemplate" -Path $templatesDN -OtherAttributes @{
            "displayName"="Long Validity Certificate (10 years)"
            "msPKI-Cert-Template-OID"="1.3.6.1.4.1.311.21.8.$(Get-Random).$(Get-Random).$(Get-Random)"
            "flags"=131680; "revision"=100; "pKIDefaultKeySpec"=1; "pKIMaxIssuingDepth"=0
            "pKICriticalExtensions"=@("2.5.29.15")
            "pKIExtendedKeyUsage"=@("1.3.6.1.5.5.7.3.2")
            "pKIExpirationPeriod"=[byte[]](0x00,0x40,0xA4,0x53,0x07,0xFB,0xFF,0xFF)  # ~10 years
            "msPKI-Certificate-Name-Flag"=0
            "msPKI-Enrollment-Flag"=0
            "msPKI-RA-Signature"=0
            "msPKI-Template-Schema-Version"=2
            "msPKI-Template-Minor-Revision"=0
        } -ErrorAction Stop
        Write-Host "  -> [VULN-PKI] LongValidityCert: duree 10 ans" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur LongValidityCert: $_" -ForegroundColor Gray }
} else { Write-Host "  -> Template LongValidity existe deja." -ForegroundColor Gray }

Write-Host "`n  -> Vulnerabilites ADCS configurees." -ForegroundColor Cyan
