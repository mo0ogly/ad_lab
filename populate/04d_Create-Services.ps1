<#
.SYNOPSIS
    Cree les comptes de service (normaux + vulnerables)
    Anomalies: Kerberoasting, AS-REP Roasting, delegation non contrainte/contrainte/RBCD,
    reversible enc, password=username, SVC dans DA, DES/RC4, password dans description,
    GMSA non utilise, service avec AdminCount
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$DefaultPassword = "Cim22091956!!??",
    [string]$WeakPassword = "Password1"
)

Write-Host "`n[SERVICES] Comptes de service..." -ForegroundColor Yellow

$securePass = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$weakPass = ConvertTo-SecureString $WeakPassword -AsPlainText -Force
$svcPath = "OU=Services_Comptes,$DomainDN"

# --- Comptes normaux ---
$normalSvcs = @("svc_backup","svc_sql","svc_iis","svc_monitor","svc_antivirus","svc_scan","svc_print","svc_mail","svc_sccm","svc_sap","svc_crm","svc_sharepoint","svc_adfs","svc_wsus","svc_nps")
foreach ($name in $normalSvcs) {
    try {
        New-ADUser -Name $name -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
            -Description "Service $name" -Path $svcPath -AccountPassword $securePass `
            -PasswordNeverExpires $true -CannotChangePassword $true -Enabled $true -ErrorAction Stop
        Write-Host "  -> $name" -ForegroundColor Green
    } catch { Write-Host "  -> $name existe deja." -ForegroundColor Gray }
}

# ================================================================
# COMPTES VULNERABLES
# ================================================================
Write-Host "`n  --- Comptes VULNERABLES ---" -ForegroundColor Red

# [KERBEROASTING] SPN sur comptes avec mdp faible
$kerberoastable = @(
    @{Name="svc_sql_legacy"; SPN="MSSQLSvc/sql2008.lab.local:1433"; Desc="SQL Server 2008 legacy"},
    @{Name="svc_http_intra"; SPN="HTTP/intranet.lab.local"; Desc="Intranet IIS legacy"},
    @{Name="svc_cifs_backup"; SPN="CIFS/backup-srv.lab.local"; Desc="CIFS backup legacy"},
    @{Name="svc_mssql_dev"; SPN="MSSQLSvc/sqldev.lab.local:1433"; Desc="SQL dev instance"},
    @{Name="svc_exchange_auto"; SPN="exchangeAB/exchange.lab.local"; Desc="Exchange Autodiscover"},
    @{Name="svc_ftp_legacy"; SPN="FTP/ftp.lab.local"; Desc="FTP service legacy"},
    @{Name="svc_oracle_prod"; SPN="oracle/oradb.lab.local:1521"; Desc="Oracle DB prod"},
    @{Name="svc_vmware"; SPN="STS/vcenter.lab.local"; Desc="vCenter service"}
)
foreach ($svc in $kerberoastable) {
    try {
        New-ADUser -Name $svc.Name -SamAccountName $svc.Name -UserPrincipalName "$($svc.Name)@$DomainName" `
            -Description $svc.Desc -Path $svcPath -AccountPassword $weakPass `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Set-ADUser -Identity $svc.Name -ServicePrincipalNames @{Add=$svc.SPN}
        Write-Host "  -> [KERBEROAST] $($svc.Name) SPN=$($svc.SPN)" -ForegroundColor Red
    } catch { Write-Host "  -> $($svc.Name) existe deja." -ForegroundColor Gray }
}

# [AS-REP ROASTING] Pre-auth Kerberos desactivee
foreach ($name in @("svc_legacy_app","svc_old_scanner","svc_ftp_anon","svc_telnet_mgmt","svc_snmp_poll")) {
    try {
        New-ADUser -Name $name -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
            -Description "Pre-authentication OFF" -Path $svcPath -AccountPassword $weakPass `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Set-ADAccountControl -Identity $name -DoesNotRequirePreAuth $true
        Write-Host "  -> [AS-REP ROAST] $name" -ForegroundColor Red
    } catch { Write-Host "  -> $name existe deja." -ForegroundColor Gray }
}

# [PASSWORD = USERNAME]
foreach ($name in @("svc_test_app","svc_dev_api","svc_staging")) {
    try {
        New-ADUser -Name $name -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
            -Description "App de test" -Path $svcPath -AccountPassword (ConvertTo-SecureString $name -AsPlainText -Force) `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Write-Host "  -> [WEAK PWD] $name (mdp=nom du compte)" -ForegroundColor Red
    } catch { Write-Host "  -> $name existe deja." -ForegroundColor Gray }
}

# [SERVICE dans Domain Admins]
try {
    New-ADUser -Name "svc_deploy_prod" -SamAccountName "svc_deploy_prod" -UserPrincipalName "svc_deploy_prod@$DomainName" `
        -Description "Deploy prod" -Path $svcPath -AccountPassword $securePass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "svc_deploy_prod"
    Write-Host "  -> [SVC IN DA] svc_deploy_prod dans Domain Admins!" -ForegroundColor Red
} catch { Write-Host "  -> svc_deploy_prod existe deja." -ForegroundColor Gray }

# [PASSWORD DANS LA DESCRIPTION] - Tres frequent dans les audits reels
try {
    New-ADUser -Name "svc_legacy_db" -SamAccountName "svc_legacy_db" -UserPrincipalName "svc_legacy_db@$DomainName" `
        -Description "Service DB legacy - Password: Sql2008!Pass - NE PAS MODIFIER" -Path $svcPath `
        -AccountPassword (ConvertTo-SecureString "Sql2008!Pass" -AsPlainText -Force) `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] svc_legacy_db description contient le mot de passe!" -ForegroundColor Red
} catch { Write-Host "  -> svc_legacy_db existe deja." -ForegroundColor Gray }

try {
    New-ADUser -Name "svc_monitoring_old" -SamAccountName "svc_monitoring_old" -UserPrincipalName "svc_monitoring_old@$DomainName" `
        -Description "Mot de passe: M0n1t0r!ng2020 - Contact: thomas.laurent" -Path $svcPath `
        -AccountPassword (ConvertTo-SecureString "M0n1t0r!ng2020" -AsPlainText -Force) `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] svc_monitoring_old description contient le mot de passe!" -ForegroundColor Red
} catch { Write-Host "  -> svc_monitoring_old existe deja." -ForegroundColor Gray }

try {
    New-ADUser -Name "svc_printer_mgmt" -SamAccountName "svc_printer_mgmt" -UserPrincipalName "svc_printer_mgmt@$DomainName" `
        -Description "Imprimantes etage 3 - pwd=Print3r$2019 - voir wiki IT" -Path $svcPath `
        -AccountPassword (ConvertTo-SecureString 'Print3r$2019' -AsPlainText -Force) `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] svc_printer_mgmt description contient le mot de passe!" -ForegroundColor Red
} catch { Write-Host "  -> svc_printer_mgmt existe deja." -ForegroundColor Gray }

# [DELEGATION NON CONTRAINTE]
try {
    New-ADUser -Name "svc_web_front" -SamAccountName "svc_web_front" -UserPrincipalName "svc_web_front@$DomainName" `
        -Description "Web Frontend" -Path $svcPath -AccountPassword $securePass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Set-ADAccountControl -Identity "svc_web_front" -TrustedForDelegation $true
    Write-Host "  -> [UNCONSTR DELEG] svc_web_front (delegation non contrainte)" -ForegroundColor Red
} catch { Write-Host "  -> svc_web_front existe deja." -ForegroundColor Gray }

try {
    Set-ADAccountControl -Identity "svc_iis" -TrustedForDelegation $true -ErrorAction Stop
    Write-Host "  -> [UNCONSTR DELEG] svc_iis (delegation non contrainte)" -ForegroundColor Red
} catch {}

# [DELEGATION CONTRAINTE avec PROTOCOL TRANSITION (S4U2Self + S4U2Proxy)]
try {
    New-ADUser -Name "svc_portal_web" -SamAccountName "svc_portal_web" -UserPrincipalName "svc_portal_web@$DomainName" `
        -Description "Portail web - constrained delegation" -Path $svcPath -AccountPassword $securePass `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Set-ADUser -Identity "svc_portal_web" -Add @{
        "msDS-AllowedToDelegateTo"=@("CIFS/DC01.lab.local","LDAP/DC01.lab.local","HTTP/DC01.lab.local")
    }
    # Activer T2A4D (TrustedToAuthForDelegation) = protocol transition
    Set-ADAccountControl -Identity "svc_portal_web" -TrustedToAuthForDelegation $true
    Write-Host "  -> [CONSTR DELEG+T2A4D] svc_portal_web peut impersonner vers DC01 (CIFS/LDAP/HTTP)!" -ForegroundColor Red
} catch { Write-Host "  -> svc_portal_web existe deja ou erreur: $_" -ForegroundColor Gray }

# [DELEGATION CONTRAINTE vers service sensible]
try {
    New-ADUser -Name "svc_middleware" -SamAccountName "svc_middleware" -UserPrincipalName "svc_middleware@$DomainName" `
        -Description "Middleware applicatif" -Path $svcPath -AccountPassword $securePass `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Set-ADUser -Identity "svc_middleware" -Add @{
        "msDS-AllowedToDelegateTo"=@("MSSQLSvc/SRV-SQL01.lab.local:1433","CIFS/SRV-FILE01.lab.local")
    }
    Write-Host "  -> [CONSTR DELEG] svc_middleware vers SQL01 + FILE01" -ForegroundColor Red
} catch { Write-Host "  -> svc_middleware existe deja." -ForegroundColor Gray }

# [RBCD - Resource-Based Constrained Delegation]
# Un compte qui peut configurer msDS-AllowedToActOnBehalfOfOtherIdentity
try {
    New-ADUser -Name "svc_rbcd_vuln" -SamAccountName "svc_rbcd_vuln" -UserPrincipalName "svc_rbcd_vuln@$DomainName" `
        -Description "RBCD misconfigured" -Path $svcPath -AccountPassword $securePass `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    # Configurer RBCD: svc_rbcd_vuln peut agir au nom de n'importe qui sur DC01
    $rbcdSid = (Get-ADUser "svc_rbcd_vuln").SID
    $dc = Get-ADComputer "DC01"
    $sd = New-Object Security.AccessControl.RawSecurityDescriptor("O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;$rbcdSid)")
    $sdBytes = New-Object byte[] ($sd.BinaryLength)
    $sd.GetBinaryForm($sdBytes, 0)
    Set-ADComputer -Identity $dc -Replace @{"msDS-AllowedToActOnBehalfOfOtherIdentity"=$sdBytes}
    Write-Host "  -> [RBCD] svc_rbcd_vuln peut impersonner vers DC01 via RBCD!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur RBCD: $_" -ForegroundColor Gray }

# [REVERSIBLE ENCRYPTION]
try {
    New-ADUser -Name "svc_radius_auth" -SamAccountName "svc_radius_auth" -UserPrincipalName "svc_radius_auth@$DomainName" `
        -Description "RADIUS auth" -Path $svcPath -AccountPassword $securePass -PasswordNeverExpires $true `
        -AllowReversiblePasswordEncryption $true -Enabled $true -ErrorAction Stop
    Write-Host "  -> [REVERSIBLE] svc_radius_auth chiffrement reversible" -ForegroundColor Red
} catch { Write-Host "  -> svc_radius_auth existe deja." -ForegroundColor Gray }

try {
    Set-ADUser -Identity "svc_adfs" -AllowReversiblePasswordEncryption $true -ErrorAction SilentlyContinue
    Write-Host "  -> [REVERSIBLE] svc_adfs chiffrement reversible" -ForegroundColor Red
} catch {}

# [PASSWORD NOT REQUIRED]
try {
    New-ADUser -Name "svc_old_erp" -SamAccountName "svc_old_erp" -UserPrincipalName "svc_old_erp@$DomainName" `
        -Description "Ancien ERP" -Path $svcPath -AccountPassword $weakPass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Set-ADAccountControl -Identity "svc_old_erp" -PasswordNotRequired $true
    Write-Host "  -> [NO PWD REQ] svc_old_erp PasswordNotRequired" -ForegroundColor Red
} catch { Write-Host "  -> svc_old_erp existe deja." -ForegroundColor Gray }

try {
    Set-ADAccountControl -Identity "svc_ftp_legacy" -PasswordNotRequired $true -ErrorAction SilentlyContinue
    Write-Host "  -> [NO PWD REQ] svc_ftp_legacy PasswordNotRequired" -ForegroundColor Red
} catch {}

# [ADMIN COUNT = 1 sur service] (shadow admin - SDProp impacte)
try {
    Set-ADUser -Identity "svc_sccm" -Replace @{AdminCount=1} -ErrorAction SilentlyContinue
    Write-Host "  -> [ADMINCOUNT] svc_sccm AdminCount=1 (heritage ACL bloque)" -ForegroundColor Red
} catch {}
try {
    Set-ADUser -Identity "svc_deploy_prod" -Replace @{AdminCount=1} -ErrorAction SilentlyContinue
    Write-Host "  -> [ADMINCOUNT] svc_deploy_prod AdminCount=1" -ForegroundColor Red
} catch {}

# [GROUP MEMBERSHIP excessif pour un service]
try {
    Add-ADGroupMember -Identity "GRP_Legacy_Services" -Members @("svc_sql_legacy","svc_http_intra","svc_old_erp","svc_ftp_legacy","svc_oracle_prod") -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "GRP_Backup_Operators" -Members "svc_backup" -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "GRP_IT" -Members @("svc_sccm","svc_wsus","svc_monitor") -ErrorAction SilentlyContinue
    Write-Host "  -> Services ajoutes aux groupes respectifs." -ForegroundColor Green
} catch {}

# [GMSA NON UTILISE] - Message d'info pour les collecteurs
Write-Host "  -> [INFO] AUCUN gMSA (Group Managed Service Account) utilise - tous sont des comptes standards" -ForegroundColor Yellow
Write-Host "         -> Recommandation ANSSI: utiliser gMSA pour la rotation automatique" -ForegroundColor Yellow

Write-Host "`n  -> Comptes de service configures." -ForegroundColor Cyan
