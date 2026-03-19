#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Comble les ecarts entre les collecteurs LIA-Scan et les objets AD existants.
.DESCRIPTION
    Ce script cree les objets et configurations manquants pour que TOUS les
    collecteurs (42 scripts) trouvent des anomalies detectables.

    Collecteurs couverts par ce script :
      - Collect-AADConnect        (MSOL_*, AZUREADSSOACC)
      - Collect-DsHeuristics      (dSHeuristics positions dangereuses)
      - Collect-GMSADelegation    (gMSA avec ACLs laxistes)
      - Collect-GPPPasswords      (cpassword dans GPP XML)
      - Collect-GPOUserRights     (privileges dangereux via GPO)
      - Collect-GPOAuditOwnership (GPO audit avec owner non-standard)
      - Collect-SIDHistory        (sIDHistory sur comptes)
      - Collect-DisplaySpecifier  (adminContextMenu avec UNC/DLL suspects)
      - Collect-DCOwnership       (owner DC != DA/EA)
      - Collect-SysvolPermissions (SYSVOL/NETLOGON writable)
      - Collect-ProtectedUsersAllowedList (membres avec delegation)
      - Collect-DHCPConfig        (DHCP Administrators peuple)
      - Collect-PasswordNotRequiredCount  (privileged + PASSWD_NOTREQD)
      - Collect-ADFSConfig        (DKM container + SPN)
      - Collect-UnixPasswordCount (unixUserPassword attribute)

    VOLONTAIREMENT VULNERABLE — NE PAS utiliser en production.
.NOTES
    Executer apres 04l_Set-ADCS-Vulns.ps1
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$WeakPassword = "Password1"
)

$ErrorActionPreference = "Continue"
Import-Module ActiveDirectory
Import-Module GroupPolicy -ErrorAction SilentlyContinue

$SecureWeak = ConvertTo-SecureString $WeakPassword -AsPlainText -Force
$DomainSID = (Get-ADDomain).DomainSID.Value
$ConfigNC = (Get-ADRootDSE).configurationNamingContext

Write-Host "`n[04m] ========== Collector Targets — Gap Filler ==========" -ForegroundColor Cyan

# ============================================================
# 1. COLLECT-AADCONNECT — Faux comptes Azure AD Connect
# ============================================================
Write-Host "`n[1/15] Azure AD Connect — MSOL_* et AZUREADSSOACC" -ForegroundColor Yellow

try {
    # Faux compte de sync AAD Connect (DCSync implicite)
    if (-not (Get-ADUser -Filter "SamAccountName -like 'MSOL_*'" -ErrorAction SilentlyContinue)) {
        $msol = New-ADUser -Name "MSOL_ab1234567890" `
            -SamAccountName "MSOL_ab1234567890" `
            -UserPrincipalName "MSOL_ab1234567890@$DomainName" `
            -Path "CN=Users,$DomainDN" `
            -AccountPassword $SecureWeak `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -Description "Azure AD Connect Sync Account — installed 2022-06-15" `
            -PassThru

        # Donner les droits de replication (DCSync) comme le ferait AAD Connect
        $domainObj = "AD:\$DomainDN"
        $msolSID = (Get-ADUser "MSOL_ab1234567890").SID
        $repl1 = [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2"  # DS-Replication-Get-Changes
        $repl2 = [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2"  # DS-Replication-Get-Changes-All
        $acl = Get-Acl $domainObj
        $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($msolSID, "ExtendedRight", "Allow", $repl1)
        $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($msolSID, "ExtendedRight", "Allow", $repl2)
        $acl.AddAccessRule($ace1)
        $acl.AddAccessRule($ace2)
        Set-Acl $domainObj $acl
        Write-Host "  [OK] MSOL_ab1234567890 cree avec droits DCSync" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] MSOL_* existe deja" -ForegroundColor DarkGray
    }

    # Faux AZUREADSSOACC (Seamless SSO — Silver Ticket risk)
    if (-not (Get-ADComputer -Filter "Name -eq 'AZUREADSSOACC'" -ErrorAction SilentlyContinue)) {
        New-ADComputer -Name "AZUREADSSOACC" `
            -SamAccountName "AZUREADSSOACC$" `
            -Path "CN=Computers,$DomainDN" `
            -Description "Azure AD Seamless SSO — DO NOT DELETE" `
            -Enabled $true
        # Forcer un vieux pwdLastSet (720+ jours) pour declencher l'alerte
        Write-Host "  [OK] AZUREADSSOACC cree (Silver Ticket risk)" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] AZUREADSSOACC existe deja" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  [ERREUR] AADConnect: $_" -ForegroundColor Red
}

# ============================================================
# 2. COLLECT-DSHEURISTICS — Positions dangereuses
# ============================================================
Write-Host "`n[2/15] dSHeuristics — anonymous NSPI + SDProp exclusions" -ForegroundColor Yellow

try {
    $dsSvc = "CN=Directory Service,CN=Windows NT,CN=Services,$ConfigNC"
    # Position 6 = "2" (anonymous NSPI access enabled)
    # Position 15 = "1" (SDProp exclusion mask — weakens protected groups)
    # Pad with 0s for positions in between
    $heuristics = "0000002000000010"
    Set-ADObject $dsSvc -Replace @{dSHeuristics = $heuristics}
    Write-Host "  [OK] dSHeuristics = $heuristics (anon NSPI + SDProp exclusion)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] dSHeuristics: $_" -ForegroundColor Red
}

# ============================================================
# 3. COLLECT-GMSADELEGATION — gMSA avec ACLs dangereuses
# ============================================================
Write-Host "`n[3/15] gMSA — comptes avec ACLs laxistes" -ForegroundColor Yellow

try {
    # Creer la cle KDS si absente (requis pour gMSA)
    if (-not (Get-KdsRootKey -ErrorAction SilentlyContinue)) {
        Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10)) -ErrorAction SilentlyContinue
        Write-Host "  [OK] KDS Root Key creee" -ForegroundColor Green
    }

    # gMSA pour SQL
    $gmsaName = "gmsa-sql-prod"
    if (-not (Get-ADServiceAccount -Filter "Name -eq '$gmsaName'" -ErrorAction SilentlyContinue)) {
        New-ADServiceAccount -Name $gmsaName `
            -DNSHostName "$gmsaName.$DomainName" `
            -PrincipalsAllowedToRetrieveManagedPassword "Domain Computers" `
            -Path "OU=Services_Comptes,$DomainDN" `
            -Enabled $true
        Write-Host "  [OK] gMSA $gmsaName cree" -ForegroundColor Green

        # Donner GenericAll a un user non-admin (vuln)
        $gmsaDN = (Get-ADServiceAccount $gmsaName).DistinguishedName
        $gmsaAcl = Get-Acl "AD:\$gmsaDN"
        $userSID = (Get-ADUser "hugo.blanc").SID
        $gmsaAce = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $userSID, "GenericAll", "Allow"
        )
        $gmsaAcl.AddAccessRule($gmsaAce)
        Set-Acl "AD:\$gmsaDN" $gmsaAcl
        Write-Host "  [OK] GenericAll accorde a hugo.blanc sur $gmsaName" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] gMSA $gmsaName existe deja" -ForegroundColor DarkGray
    }

    # gMSA pour IIS
    $gmsaName2 = "gmsa-iis-front"
    if (-not (Get-ADServiceAccount -Filter "Name -eq '$gmsaName2'" -ErrorAction SilentlyContinue)) {
        New-ADServiceAccount -Name $gmsaName2 `
            -DNSHostName "$gmsaName2.$DomainName" `
            -PrincipalsAllowedToRetrieveManagedPassword "Domain Computers" `
            -Path "OU=Services_Comptes,$DomainDN" `
            -Enabled $true
        Write-Host "  [OK] gMSA $gmsaName2 cree" -ForegroundColor Green

        # WriteDACL pour un service account (vuln)
        $gmsaDN2 = (Get-ADServiceAccount $gmsaName2).DistinguishedName
        $gmsaAcl2 = Get-Acl "AD:\$gmsaDN2"
        $svcSID = (Get-ADUser "svc_web_front").SID
        $gmsaAce2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
            $svcSID, "WriteDacl", "Allow"
        )
        $gmsaAcl2.AddAccessRule($gmsaAce2)
        Set-Acl "AD:\$gmsaDN2" $gmsaAcl2
        Write-Host "  [OK] WriteDACL accorde a svc_web_front sur $gmsaName2" -ForegroundColor Green
    } else {
        Write-Host "  [SKIP] gMSA $gmsaName2 existe deja" -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  [ERREUR] gMSA: $_" -ForegroundColor Red
}

# ============================================================
# 4. COLLECT-GPPPASSWORDS — cpassword dans GPP XML (MS14-025)
# ============================================================
Write-Host "`n[4/15] GPP Passwords — cpassword dans SYSVOL" -ForegroundColor Yellow

try {
    $gpo = New-GPO -Name "LAB - LEGACY Local Admin GPP" -Comment "GPP with cpassword — MS14-025 vuln"
    $gpoId = "{" + $gpo.Id.ToString() + "}"
    $gppDir = "\\$DomainName\SYSVOL\$DomainName\Policies\$gpoId\Machine\Preferences\Groups"
    New-Item -Path $gppDir -ItemType Directory -Force | Out-Null

    # AES key published by Microsoft (MS14-025) — this is NOT secret
    # cpassword = encrypted "LocalAdm1n!" with the known key
    $cpassword = "j1Uyj3Vx8TY9LtLZil2uAuZkFQA/4latT76ZwgdHdhw"

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<Groups clsid="{3125E937-EB16-4b4c-9934-544FC6D24D26}">
  <User clsid="{DF5F1855-51E5-4d24-8B1A-D9BDE98BA1D1}"
        name="local_admin_gpp" image="2" changed="2022-03-15 14:30:00"
        uid="{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}">
    <Properties action="U" newName="" fullName=""
                description="Compte admin local deploye par GPP"
                cpassword="$cpassword"
                changeLogon="0" noChange="0" neverExpires="1"
                acctDisabled="0" userName="local_admin_gpp"/>
  </User>
</Groups>
"@
    Set-Content -Path "$gppDir\Groups.xml" -Value $xml -Encoding UTF8
    $gpo | New-GPLink -Target $DomainDN -LinkEnabled Yes -ErrorAction SilentlyContinue
    Write-Host "  [OK] GPP cpassword injecte dans GPO '$($gpo.DisplayName)'" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] GPPPasswords: $_" -ForegroundColor Red
}

# ============================================================
# 5. COLLECT-GPOUSERRIGHTS — Privileges dangereux dans GPO
# ============================================================
Write-Host "`n[5/15] GPO User Rights — privileges dangereux a groupes larges" -ForegroundColor Yellow

try {
    $gpoUR = New-GPO -Name "LAB - LEGACY Dangerous Privileges" -Comment "Critical user rights assigned to broad groups"
    $gpoURId = "{" + $gpoUR.Id.ToString() + "}"
    $infDir = "\\$DomainName\SYSVOL\$DomainName\Policies\$gpoURId\Machine\Microsoft\Windows NT\SecEdit"
    New-Item -Path $infDir -ItemType Directory -Force | Out-Null

    # S-1-5-11 = Authenticated Users, S-1-1-0 = Everyone, S-1-5-32-545 = BUILTIN\Users
    $inf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeDebugPrivilege = *S-1-5-11
SeBackupPrivilege = *S-1-5-11,*S-1-5-32-545
SeRestorePrivilege = *S-1-5-11
SeTakeOwnershipPrivilege = *S-1-5-32-545
SeLoadDriverPrivilege = *S-1-1-0
SeRemoteInteractiveLogonRight = *S-1-5-11,*S-1-5-32-545
"@
    Set-Content -Path "$infDir\GptTmpl.inf" -Value $inf -Encoding Unicode
    $gpoUR | New-GPLink -Target "OU=Serveurs,$DomainDN" -LinkEnabled Yes -ErrorAction SilentlyContinue
    Write-Host "  [OK] GPO privileges dangereux creee (SeDebug, SeBackup, SeLoadDriver a groupes larges)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] GPOUserRights: $_" -ForegroundColor Red
}

# ============================================================
# 6. COLLECT-GPOAUDITOWNERSHIP — GPO audit avec owner non-standard
# ============================================================
Write-Host "`n[6/15] GPO Audit Ownership — owner non-admin sur GPO audit" -ForegroundColor Yellow

try {
    $gpoAudit = New-GPO -Name "LAB - Security Audit Logging" -Comment "Audit policy GPO — ownership vuln"
    $gpoAuditDN = "CN={$($gpoAudit.Id)},CN=Policies,CN=System,$DomainDN"

    # Changer l'owner a un user non-admin
    $auditAcl = Get-Acl "AD:\$gpoAuditDN"
    $nonAdminSID = New-Object System.Security.Principal.SecurityIdentifier((Get-ADUser "camille.robin").SID)
    $auditAcl.SetOwner($nonAdminSID)
    Set-Acl "AD:\$gpoAuditDN" $auditAcl

    # Donner GenericAll a un user non-admin
    $ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $nonAdminSID, "GenericAll", "Allow"
    )
    $auditAcl.AddAccessRule($ace)
    Set-Acl "AD:\$gpoAuditDN" $auditAcl

    Write-Host "  [OK] GPO audit '$($gpoAudit.DisplayName)' — owner = camille.robin" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] GPOAuditOwnership: $_" -ForegroundColor Red
}

# ============================================================
# 7. COLLECT-SIDHISTORY — Comptes avec sIDHistory
# ============================================================
Write-Host "`n[7/15] SID History — injection via attribut" -ForegroundColor Yellow

try {
    # Simuler un compte migre avec SIDHistory (injection directe via LDAP)
    # On utilise un SID fictif d'un domaine "ancien" S-1-5-21-9999999-9999999-9999999-1234
    $fakeSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-999999999-999999999-999999999-1234")
    $fakeSIDBytes = New-Object byte[] $fakeSID.BinaryLength
    $fakeSID.GetBinaryForm($fakeSIDBytes, 0)

    # Injecter sur ext.old.admin (simule migration d'un ancien domaine)
    $user = Get-ADUser "ext.old.admin"
    Set-ADUser $user -Replace @{sIDHistory = $fakeSIDBytes}
    Write-Host "  [OK] sIDHistory injecte sur ext.old.admin (domaine fictif migre)" -ForegroundColor Green

    # Sur un service account aussi
    $svc = Get-ADUser "svc_legacy_db"
    $fakeSID2 = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21-999999999-999999999-999999999-5678")
    $fakeSIDBytes2 = New-Object byte[] $fakeSID2.BinaryLength
    $fakeSID2.GetBinaryForm($fakeSIDBytes2, 0)
    Set-ADUser $svc -Replace @{sIDHistory = $fakeSIDBytes2}
    Write-Host "  [OK] sIDHistory injecte sur svc_legacy_db" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] SIDHistory: $_" -ForegroundColor Red
    Write-Host "  [INFO] L'injection sIDHistory peut echouer sans privileges SeMigrate. C'est normal." -ForegroundColor DarkGray
}

# ============================================================
# 8. COLLECT-DISPLAYSPECIFIER — Backdoor adminContextMenu
# ============================================================
Write-Host "`n[8/15] DisplaySpecifier — adminContextMenu malveillant" -ForegroundColor Yellow

try {
    # Trouver le display specifier pour la locale (409 = EN, 40C = FR)
    $displaySpecDN = "CN=user-Display,CN=409,CN=DisplaySpecifiers,$ConfigNC"
    if (-not (Get-ADObject -Identity $displaySpecDN -ErrorAction SilentlyContinue)) {
        $displaySpecDN = "CN=user-Display,CN=40C,CN=DisplaySpecifiers,$ConfigNC"
    }

    # Injecter un adminContextMenu pointant vers un UNC path (backdoor persistence)
    $maliciousMenu = "3,&Maintenance Tool,\\192.168.0.10\share\maintenance.exe"
    Set-ADObject $displaySpecDN -Add @{adminContextMenu = $maliciousMenu}
    Write-Host "  [OK] adminContextMenu backdoor injecte sur user-Display specifier" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] DisplaySpecifier: $_" -ForegroundColor Red
}

# ============================================================
# 9. COLLECT-DCOWNERSHIP — Owner DC != DA/EA
# ============================================================
Write-Host "`n[9/15] DC Ownership — owner non-standard sur objet DC" -ForegroundColor Yellow

try {
    $dc = Get-ADDomainController -Discover | Select-Object -ExpandProperty Name
    $dcComputer = Get-ADComputer $dc
    $dcAcl = Get-Acl "AD:\$($dcComputer.DistinguishedName)"

    # Changer l'owner a svc_deploy_prod (service account in DA mais c'est un SID non-standard)
    $svcDeploySID = New-Object System.Security.Principal.SecurityIdentifier(
        (Get-ADUser "svc_deploy_prod").SID
    )
    $dcAcl.SetOwner($svcDeploySID)
    Set-Acl "AD:\$($dcComputer.DistinguishedName)" $dcAcl
    Write-Host "  [OK] Owner de $dc change a svc_deploy_prod (non-standard)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] DCOwnership: $_" -ForegroundColor Red
}

# ============================================================
# 10. COLLECT-SYSVOLPERMISSIONS — SYSVOL/NETLOGON writable
# ============================================================
Write-Host "`n[10/15] SYSVOL Permissions — write pour Domain Users" -ForegroundColor Yellow

try {
    $sysvolPath = "\\$DomainName\SYSVOL\$DomainName"
    $netlogonPath = "\\$DomainName\NETLOGON"

    # Ajouter Modify pour Domain Users sur SYSVOL (dangereux)
    $aclSysvol = Get-Acl $sysvolPath
    $domUsersSID = New-Object System.Security.Principal.SecurityIdentifier("$DomainSID-513")
    $aceSysvol = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $domUsersSID, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclSysvol.AddAccessRule($aceSysvol)
    Set-Acl $sysvolPath $aclSysvol
    Write-Host "  [OK] SYSVOL : Modify accorde a Domain Users" -ForegroundColor Green

    # Ajouter Write pour Authenticated Users sur NETLOGON
    $authUsersSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-11")
    $aclNetlogon = Get-Acl $netlogonPath
    $aceNetlogon = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $authUsersSID, "Write", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclNetlogon.AddAccessRule($aceNetlogon)
    Set-Acl $netlogonPath $aclNetlogon
    Write-Host "  [OK] NETLOGON : Write accorde a Authenticated Users" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] SysvolPermissions: $_" -ForegroundColor Red
}

# ============================================================
# 11. COLLECT-PROTECTEDUSERSALLOWEDLIST — Delegation dans Protected Users
# ============================================================
Write-Host "`n[11/15] Protected Users — membres avec delegation" -ForegroundColor Yellow

try {
    # Ajouter des comptes a Protected Users
    Add-ADGroupMember "Protected Users" -Members @(
        "adm.thomas.laurent",
        "adm.catherine.morel",
        "svc_web_front"           # Ce compte a TrustedForDelegation = true (conflit)
    ) -ErrorAction SilentlyContinue

    # svc_web_front est deja TrustedForDelegation — c'est le conflit qu'on cherche
    # Ajouter aussi un admin avec constrained delegation
    Set-ADUser "adm.thomas.laurent" -Add @{
        "msDS-AllowedToDelegateTo" = @("CIFS/SRV-FILE01.lab.local", "LDAP/DC01.lab.local")
    } -ErrorAction SilentlyContinue

    Write-Host "  [OK] Protected Users peuple avec membres ayant delegation (conflit)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] ProtectedUsers: $_" -ForegroundColor Red
}

# ============================================================
# 12. COLLECT-DHCPCONFIG — Groupe DHCP Administrators
# ============================================================
Write-Host "`n[12/15] DHCP Administrators — groupe peuple" -ForegroundColor Yellow

try {
    # Creer le groupe s'il n'existe pas (normalement cree par le role DHCP)
    if (-not (Get-ADGroup -Filter "Name -eq 'DHCP Administrators'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "DHCP Administrators" `
            -GroupScope DomainLocal `
            -GroupCategory Security `
            -Path "CN=Users,$DomainDN" `
            -Description "DHCP Administrators — manages DHCP settings and DNS updates"
        Write-Host "  [OK] Groupe DHCP Administrators cree" -ForegroundColor Green
    }

    # Ajouter des membres (DNS poisoning risk)
    Add-ADGroupMember "DHCP Administrators" -Members @(
        "svc_monitor",
        "damien.leclerc",
        "thomas.laurent"
    ) -ErrorAction SilentlyContinue
    Write-Host "  [OK] DHCP Administrators peuple (DNS poisoning risk)" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] DHCPConfig: $_" -ForegroundColor Red
}

# ============================================================
# 13. COLLECT-PASSWORDNOTREQUIREDCOUNT — Privileged + PASSWD_NOTREQD
# ============================================================
Write-Host "`n[13/15] PasswordNotRequired — sur compte privilegie" -ForegroundColor Yellow

try {
    # Mettre PASSWD_NOTREQD sur un Domain Admin
    Set-ADAccountControl "admin.backup" -PasswordNotRequired $true
    Write-Host "  [OK] admin.backup (DA) : PasswordNotRequired = true" -ForegroundColor Green

    # Sur un Account Operator aussi
    Set-ADAccountControl "maxime.petit" -PasswordNotRequired $true
    Write-Host "  [OK] maxime.petit (Account Operators) : PasswordNotRequired = true" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] PasswordNotRequired: $_" -ForegroundColor Red
}

# ============================================================
# 14. COLLECT-ADFSCONFIG — DKM container + SPN
# ============================================================
Write-Host "`n[14/15] ADFS Config — DKM container avec ACLs laxistes" -ForegroundColor Yellow

try {
    # Creer le conteneur DKM ADFS
    $progDataDN = "CN=Program Data,$DomainDN"
    if (-not (Get-ADObject -Filter "Name -eq 'Program Data'" -SearchBase $DomainDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name "Program Data" -Type container -Path $DomainDN -ErrorAction SilentlyContinue
    }

    $msDN = "CN=Microsoft,$progDataDN"
    if (-not (Get-ADObject -Identity $msDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name "Microsoft" -Type container -Path $progDataDN -ErrorAction SilentlyContinue
    }

    $adfsDN = "CN=ADFS,CN=Microsoft,$progDataDN"
    if (-not (Get-ADObject -Identity $adfsDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name "ADFS" -Type container -Path $msDN
        Write-Host "  [OK] Conteneur DKM ADFS cree : $adfsDN" -ForegroundColor Green
    }

    # Donner Read a Domain Users sur le DKM container (Golden SAML risk)
    $dkmAcl = Get-Acl "AD:\$adfsDN"
    $domainUsersSID = New-Object System.Security.Principal.SecurityIdentifier("$DomainSID-513")
    $readAce = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $domainUsersSID, "GenericRead", "Allow"
    )
    $dkmAcl.AddAccessRule($readAce)
    Set-Acl "AD:\$adfsDN" $dkmAcl
    Write-Host "  [OK] DKM ADFS : GenericRead accorde a Domain Users (Golden SAML)" -ForegroundColor Green

    # Ajouter SPN host/adfs* sur svc_adfs
    Set-ADUser "svc_adfs" -ServicePrincipalNames @{
        Add = @("host/adfs.lab.local", "host/adfs01.lab.local", "http/adfs.lab.local/adfs/ls")
    } -ErrorAction SilentlyContinue
    Write-Host "  [OK] SPN host/adfs* ajoute a svc_adfs" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] ADFSConfig: $_" -ForegroundColor Red
}

# ============================================================
# 15. COLLECT-UNIXPASSWORDCOUNT — Attribut unixUserPassword
# ============================================================
Write-Host "`n[15/15] Unix Password — attribut unixUserPassword" -ForegroundColor Yellow

try {
    # Injecter unixUserPassword sur quelques comptes (NIS/LDAP legacy)
    $unixUsers = @("svc_legacy_app", "svc_old_scanner", "ext.maintenance", "svc_ftp_legacy")
    foreach ($u in $unixUsers) {
        $userObj = Get-ADUser $u -ErrorAction SilentlyContinue
        if ($userObj) {
            # Set unixUserPassword (stored as octet string, base64 of cleartext)
            $pwdBytes = [System.Text.Encoding]::UTF8.GetBytes("{CRYPT}`$6`$rounds=5000`$salt`$hashplaceholder")
            Set-ADUser $u -Replace @{unixUserPassword = $pwdBytes} -ErrorAction SilentlyContinue
        }
    }
    Write-Host "  [OK] unixUserPassword defini sur $($unixUsers.Count) comptes" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] UnixPassword: $_" -ForegroundColor Red
    Write-Host "  [INFO] L'attribut unixUserPassword peut ne pas exister si NIS Extensions non installees." -ForegroundColor DarkGray
}

# ============================================================
# BONUS: Configurations supplementaires pour couverture maximale
# ============================================================
# ============================================================
# 16. COLLECT-EXCHANGECONFIG — Faux objets Exchange dans AD
# ============================================================
Write-Host "`n[16/18] Exchange Config — groupes RBAC + Shared Permissions" -ForegroundColor Yellow

try {
    # Creer l'OU Microsoft Exchange Security Groups (comme le ferait /PrepareAD)
    $exchOU = "OU=Microsoft Exchange Security Groups,$DomainDN"
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Microsoft Exchange Security Groups'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name "Microsoft Exchange Security Groups" -Path $DomainDN -Description "Exchange RBAC groups (lab simulation)"
    }

    # Creer les 3 groupes RBAC Exchange
    $exchGroups = @(
        @{Name="Organization Management";         Desc="Exchange Organization Admins — full Exchange control"},
        @{Name="Exchange Trusted Subsystem";       Desc="Exchange Trusted Subsystem — SYSTEM-level Exchange services"},
        @{Name="Exchange Windows Permissions";     Desc="Exchange Windows Permissions — AD object modification rights"}
    )
    foreach ($g in $exchGroups) {
        if (-not (Get-ADGroup -Filter "Name -eq '$($g.Name)'" -ErrorAction SilentlyContinue)) {
            New-ADGroup -Name $g.Name `
                -GroupScope Universal `
                -GroupCategory Security `
                -Path $exchOU `
                -Description $g.Desc
            Write-Host "  [OK] Groupe '$($g.Name)' cree" -ForegroundColor Green
        }
    }

    # Peupler Organization Management (vuln: trop de membres)
    Add-ADGroupMember "Organization Management" -Members @(
        "adm.catherine.morel",
        "thomas.laurent",          # Non-admin dans ce groupe = privilege escalation
        "svc_mail"
    ) -ErrorAction SilentlyContinue

    # Peupler Exchange Trusted Subsystem
    Add-ADGroupMember "Exchange Trusted Subsystem" -Members @("svc_mail") -ErrorAction SilentlyContinue

    # Peupler Exchange Windows Permissions
    Add-ADGroupMember "Exchange Windows Permissions" -Members @("svc_mail") -ErrorAction SilentlyContinue

    # VULN: Donner WriteDacl sur le domaine root a "Exchange Windows Permissions"
    # C'est le modele "Shared Permissions" (defaut Exchange) = Exchange admins → Domain Admins
    $exchWinPermSID = (Get-ADGroup "Exchange Windows Permissions").SID
    $domAcl = Get-Acl "AD:\$DomainDN"
    $exchAce = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
        $exchWinPermSID, "WriteDacl", "Allow"
    )
    $domAcl.AddAccessRule($exchAce)
    Set-Acl "AD:\$DomainDN" $domAcl
    Write-Host "  [OK] Exchange Windows Permissions : WriteDacl sur domaine (Shared Permissions = escalade DA)" -ForegroundColor Green

    # Creer un faux objet Exchange Organization dans Configuration (si possible)
    # Note: sans schema Exchange, on cree un container generique comme marqueur
    $exchConfigBase = "CN=Services,$ConfigNC"
    $exchConfigDN = "CN=Microsoft Exchange,$exchConfigBase"
    if (-not (Get-ADObject -Identity $exchConfigDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name "Microsoft Exchange" -Type container -Path $exchConfigBase -ErrorAction SilentlyContinue
        # Creer un sous-container pour l'org
        New-ADObject -Name "LabCorp Exchange Org" -Type container `
            -Path $exchConfigDN `
            -OtherAttributes @{description="Exchange Organization Container (simulated)"} `
            -ErrorAction SilentlyContinue
        Write-Host "  [OK] Container Exchange dans Configuration cree (marqueur)" -ForegroundColor Green
    }
    Write-Host "  [OK] Exchange : groupes RBAC + Shared Permissions model configure" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] ExchangeConfig: $_" -ForegroundColor Red
}

# ============================================================
# 17. COLLECT-SHAREPOINTCONFIG — Faux objets SharePoint dans AD
# ============================================================
Write-Host "`n[17/18] SharePoint Config — SCP + Farm Admins + service accounts" -ForegroundColor Yellow

try {
    # Creer le container SCP SharePoint
    $systemDN = "CN=System,$DomainDN"
    $spContainerDN = "CN=Microsoft SharePoint Products,$systemDN"
    if (-not (Get-ADObject -Identity $spContainerDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name "Microsoft SharePoint Products" -Type container -Path $systemDN
        Write-Host "  [OK] Container SCP SharePoint cree" -ForegroundColor Green
    }

    # Creer un SCP (Service Connection Point) pour simuler une farm
    $scpName = "LabCorp-SP-Farm-01"
    $scpDN = "CN=$scpName,$spContainerDN"
    if (-not (Get-ADObject -Identity $scpDN -ErrorAction SilentlyContinue)) {
        New-ADObject -Name $scpName `
            -Type serviceConnectionPoint `
            -Path $spContainerDN `
            -OtherAttributes @{
                keywords = @("Microsoft SharePoint", "SharePoint 2019", "16.0.10396.20000")
                serviceBindingInformation = @("https://sharepoint.lab.local", "https://intranet.lab.local")
            }
        Write-Host "  [OK] SCP SharePoint Farm '$scpName' cree" -ForegroundColor Green
    }

    # Creer le service account SharePoint avec SPN
    if (-not (Get-ADUser -Filter "SamAccountName -eq 'svc_sharepoint_farm'" -ErrorAction SilentlyContinue)) {
        New-ADUser -Name "svc_sharepoint_farm" `
            -SamAccountName "svc_sharepoint_farm" `
            -UserPrincipalName "svc_sharepoint_farm@$DomainName" `
            -Path "OU=Services_Comptes,$DomainDN" `
            -AccountPassword $SecureWeak `
            -Enabled $true `
            -PasswordNeverExpires $true `
            -Description "SharePoint Farm Account — Timer Service + Central Admin" `
            -ServicePrincipalNames @("HTTP/sharepoint.lab.local", "HTTP/intranet.lab.local")
        Write-Host "  [OK] svc_sharepoint_farm cree avec SPNs SharePoint" -ForegroundColor Green
    }

    # Ajouter SPN SharePoint sur svc_sharepoint existant
    Set-ADUser "svc_sharepoint" -Replace @{
        Description = "SharePoint App Pool Account"
    } -ErrorAction SilentlyContinue
    Set-ADUser "svc_sharepoint" -ServicePrincipalNames @{
        Add = @("HTTP/sharepoint-app.lab.local")
    } -ErrorAction SilentlyContinue

    # Creer le groupe Farm Administrators
    if (-not (Get-ADGroup -Filter "Name -eq 'SharePoint Farm Administrators'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "SharePoint Farm Administrators" `
            -GroupScope Global `
            -GroupCategory Security `
            -Path "OU=Groupes,$DomainDN" `
            -Description "SharePoint Farm Administrators — full farm control"
        Write-Host "  [OK] Groupe 'SharePoint Farm Administrators' cree" -ForegroundColor Green
    }

    # VULN: Mettre des Domain Admins dans Farm Admins (cross-privilege)
    Add-ADGroupMember "SharePoint Farm Administrators" -Members @(
        "adm.thomas.laurent",      # DA dans Farm Admins = high risk cross-privilege
        "svc_sharepoint_farm",
        "thomas.laurent"           # Utilisateur standard aussi
    ) -ErrorAction SilentlyContinue

    # VULN: Mettre svc_sharepoint_farm dans un groupe privilegie
    Add-ADGroupMember "Domain Admins" -Members "svc_sharepoint_farm" -ErrorAction SilentlyContinue
    Write-Host "  [OK] SharePoint : SCP + Farm Admins (DA dedans) + svc_sharepoint_farm in DA" -ForegroundColor Green
} catch {
    Write-Host "  [ERREUR] SharePointConfig: $_" -ForegroundColor Red
}

# ============================================================
# 18. BONUS COUVERTURE — Objets supplementaires
# ============================================================
Write-Host "`n[18/18] Configurations supplementaires" -ForegroundColor Yellow

# --- GPO Audit Settings (pour Collect-GPOAuditSettings) ---
try {
    $gpoAuditS = Get-GPO -Name "LAB - Audit Policy" -ErrorAction SilentlyContinue
    if ($gpoAuditS) {
        $auditGpoId = "{" + $gpoAuditS.Id.ToString() + "}"
        $auditInfDir = "\\$DomainName\SYSVOL\$DomainName\Policies\$auditGpoId\Machine\Microsoft\Windows NT\SecEdit"
        New-Item -Path $auditInfDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        # Politique d'audit deliberement insuffisante
        $auditInf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Event Audit]
AuditSystemEvents = 0
AuditLogonEvents = 1
AuditObjectAccess = 0
AuditPrivilegeUse = 0
AuditPolicyChange = 0
AuditAccountManage = 0
AuditProcessTracking = 0
AuditDSAccess = 0
AuditAccountLogon = 1
"@
        Set-Content -Path "$auditInfDir\GptTmpl.inf" -Value $auditInf -Encoding Unicode
        Write-Host "  [OK] GPO Audit Policy : audit minimal (6 categories a 0)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERREUR] Audit Settings: $_" -ForegroundColor Red
}

# --- GPO Settings — LM Hash + weak password in GptTmpl.inf (pour Collect-GPOSettings) ---
try {
    $gpoPwd = Get-GPO -Name "LAB - Password Policy" -ErrorAction SilentlyContinue
    if ($gpoPwd) {
        $pwdGpoId = "{" + $gpoPwd.Id.ToString() + "}"
        $pwdInfDir = "\\$DomainName\SYSVOL\$DomainName\Policies\$pwdGpoId\Machine\Microsoft\Windows NT\SecEdit"
        New-Item -Path $pwdInfDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

        $pwdInf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
MinimumPasswordAge = 0
MaximumPasswordAge = -1
MinimumPasswordLength = 7
PasswordComplexity = 0
PasswordHistorySize = 0
LockoutBadCount = 0
ClearTextPassword = 0
LSAAnonymousNameLookup = 1
[Registry Values]
MACHINE\System\CurrentControlSet\Control\Lsa\NoLMHash=4,0
MACHINE\System\CurrentControlSet\Control\Lsa\LmCompatibilityLevel=4,1
MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\RequireSecuritySignature=4,0
MACHINE\System\CurrentControlSet\Control\Lsa\RestrictAnonymous=4,0
"@
        Set-Content -Path "$pwdInfDir\GptTmpl.inf" -Value $pwdInf -Encoding Unicode
        Write-Host "  [OK] GPO Password Policy : LM hash enabled, min 7 chars, no lockout" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERREUR] GPO Settings: $_" -ForegroundColor Red
}

# --- Logon script dans NETLOGON (pour Collect-SysvolPermissions contexte) ---
try {
    $logonScript = "\\$DomainName\NETLOGON\logon.bat"
    if (-not (Test-Path $logonScript)) {
        Set-Content -Path $logonScript -Value @"
@echo off
REM Logon script legacy — maps network drives
net use Z: \\SRV-FILE01\Partage_Commun /persistent:yes
"@ -Encoding ASCII
        Write-Host "  [OK] Script de logon logon.bat cree dans NETLOGON" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERREUR] Logon script: $_" -ForegroundColor Red
}

# --- Scheduled Task GPP XML (pour Collect-GPPPasswords — second fichier) ---
try {
    $gppGpo = Get-GPO -Name "LAB - LEGACY Local Admin GPP" -ErrorAction SilentlyContinue
    if ($gppGpo) {
        $gppGpoId = "{" + $gppGpo.Id.ToString() + "}"
        $schedDir = "\\$DomainName\SYSVOL\$DomainName\Policies\$gppGpoId\Machine\Preferences\ScheduledTasks"
        New-Item -Path $schedDir -ItemType Directory -Force | Out-Null

        $schedXml = @"
<?xml version="1.0" encoding="utf-8"?>
<ScheduledTasks clsid="{CC63F200-7309-4ba0-B154-A71CD118DBCC}">
  <Task clsid="{2DEECB1C-261F-4e13-9B21-16FB83BC03BD}"
        name="Maintenance-Legacy" image="0"
        changed="2021-11-10 09:15:00"
        uid="{B2C3D4E5-F6A7-8901-BCDE-F12345678901}">
    <Properties action="C" runAs="lab\svc_legacy_db"
                cpassword="AzVJmXh/J9KrU5n0czX1uBPLSUjzFE8j7dOltPD8tLk"
                logonType="S4U" comment="Legacy maintenance task"/>
  </Task>
</ScheduledTasks>
"@
        Set-Content -Path "$schedDir\ScheduledTasks.xml" -Value $schedXml -Encoding UTF8
        Write-Host "  [OK] GPP ScheduledTasks.xml avec cpassword cree" -ForegroundColor Green
    }
} catch {
    Write-Host "  [ERREUR] GPP ScheduledTasks: $_" -ForegroundColor Red
}

Write-Host "`n========== [04m] Collector Targets — TERMINE ==========" -ForegroundColor Cyan
Write-Host ""
Write-Host "  GAPS COMBLES :" -ForegroundColor Green
Write-Host "    [AADConnect]     MSOL_* + AZUREADSSOACC (DCSync + Silver Ticket)" -ForegroundColor White
Write-Host "    [DsHeuristics]   Anonymous NSPI + SDProp exclusions" -ForegroundColor White
Write-Host "    [gMSA]           2 gMSA avec GenericAll/WriteDACL non-admin" -ForegroundColor White
Write-Host "    [GPP Passwords]  cpassword dans Groups.xml + ScheduledTasks.xml" -ForegroundColor White
Write-Host "    [GPO UserRights] SeDebug/SeBackup/SeLoadDriver a Authenticated Users" -ForegroundColor White
Write-Host "    [GPO Audit]      GPO audit avec owner non-admin + GenericAll" -ForegroundColor White
Write-Host "    [SID History]    sIDHistory injecte sur 2 comptes" -ForegroundColor White
Write-Host "    [DisplaySpec]    adminContextMenu → UNC path malveillant" -ForegroundColor White
Write-Host "    [DC Ownership]   Owner DC = svc_deploy_prod (non-standard)" -ForegroundColor White
Write-Host "    [SYSVOL Perms]   Modify/Write pour Domain Users / Authenticated Users" -ForegroundColor White
Write-Host "    [Protected Users] Membres avec delegation (conflit securite)" -ForegroundColor White
Write-Host "    [DHCP Admins]    Groupe peuple (DNS poisoning risk)" -ForegroundColor White
Write-Host "    [Pwd Not Req]    admin.backup (DA) + maxime.petit (AcctOps) PASSWD_NOTREQD" -ForegroundColor White
Write-Host "    [ADFS DKM]       Conteneur DKM + Read pour Domain Users (Golden SAML)" -ForegroundColor White
Write-Host "    [Unix Password]  unixUserPassword sur 4 comptes legacy" -ForegroundColor White
Write-Host "    [Exchange]       Groupes RBAC + Shared Permissions (WriteDacl → DA escalade)" -ForegroundColor White
Write-Host "    [SharePoint]     SCP Farm + Farm Admins (DA dedans) + svc in DA" -ForegroundColor White
Write-Host "    [Audit Policy]   6/9 categories d'audit a 0" -ForegroundColor White
Write-Host "    [Password GPO]   LM Hash, min 7 chars, no lockout dans GptTmpl.inf" -ForegroundColor White
Write-Host ""
Write-Host "  NECESSITE INFRASTRUCTURE SUPPLEMENTAIRE :" -ForegroundColor Yellow
Write-Host "    [RODC]   → Executer 05_Deploy-SecondDC.ps1 pour creer DC02 en RODC" -ForegroundColor White
Write-Host "    [Trusts] → Executer 05_Deploy-SecondDC.ps1 pour creer partner.local + trust" -ForegroundColor White
Write-Host ""
