<#
.SYNOPSIS
    Configure les Nested Groups en cascade et ACLs dangereuses
    Anomalies: WriteDACL, GenericAll, DCSync, GenericWrite, WriteOwner, ResetPassword,
    AdminSDHolder, AllExtendedRights, AddMember, ReadLAPSPassword,
    CHAINES DE PROPAGATION (BloodHound attack paths) via nested groups
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[ACLs] Nested Groups en cascade + ACLs dangereuses..." -ForegroundColor Yellow

# ================================================================
# CHAINES DE PROPAGATION DE DROITS VIA NESTED GROUPS (BloodHound)
# ================================================================
Write-Host "`n  --- Chaines de propagation via groupes en cascade ---" -ForegroundColor Red

# CHAINE 1: User -> GRP_Wifi_Corp -> GRP_VPN_Users -> GRP_RDP_Users -> Admins -> Domain Admins
# Un simple user wifi arrive dans Domain Admins via 4 sauts de groupes !
try { Add-ADGroupMember -Identity "GRP_VPN_Users" -Members "GRP_Wifi_Corp" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Wifi_Corp -> GRP_VPN_Users" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_RDP_Users" -Members "GRP_VPN_Users" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_VPN_Users -> GRP_RDP_Users" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Admins" -Members "GRP_RDP_Users" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_RDP_Users -> Admins" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Domain Admins" -Members "Admins" -ErrorAction Stop; Write-Host "  -> [CASCADE] Admins -> Domain Admins" -ForegroundColor Red } catch {}
Write-Host "  -> [PATH 1] ANY Wifi_Corp user -> VPN -> RDP -> Admins -> DA !!!" -ForegroundColor Magenta

# CHAINE 2: User -> GRP_Support -> GRP_IT_Helpdesk -> GRP_IT -> GRP_IT_Admins -> Backup Operators
try { Add-ADGroupMember -Identity "GRP_IT_Helpdesk" -Members "GRP_Support" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Support -> GRP_IT_Helpdesk" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_IT" -Members "GRP_IT_Helpdesk" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_IT_Helpdesk -> GRP_IT" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_IT_Admins" -Members "GRP_IT" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_IT -> GRP_IT_Admins" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Backup Operators" -Members "GRP_IT_Admins" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_IT_Admins -> Backup Operators" -ForegroundColor Red } catch {}
Write-Host "  -> [PATH 2] ANY Support user -> Helpdesk -> IT -> IT_Admins -> Backup Ops" -ForegroundColor Magenta

# CHAINE 3: User -> GRP_Legacy_App -> GRP_Local_Admins -> Account Operators
try { Add-ADGroupMember -Identity "GRP_Local_Admins" -Members "GRP_Legacy_App" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Legacy_App -> GRP_Local_Admins" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Account Operators" -Members "GRP_Local_Admins" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Local_Admins -> Account Operators" -ForegroundColor Red } catch {}
Write-Host "  -> [PATH 3] ANY Legacy_App member -> Local_Admins -> Account Operators" -ForegroundColor Magenta

# CHAINE 4: GRP_Managers -> GRP_MFA_Exempt -> GRP_Azure_Sync -> Enterprise Admins (indirecte)
try { Add-ADGroupMember -Identity "GRP_MFA_Exempt" -Members "GRP_Managers" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Managers -> GRP_MFA_Exempt" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_Azure_Sync" -Members "GRP_MFA_Exempt" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_MFA_Exempt -> GRP_Azure_Sync" -ForegroundColor Red } catch {}
Write-Host "  -> [PATH 4] ALL Managers -> MFA_Exempt -> Azure_Sync (chemin vers cloud admin)" -ForegroundColor Magenta

# CHAINE 5: GRP_Projet_2019 -> GRP_Migration_Temp -> GRP_Backup_Operators -> Server Operators
try { Add-ADGroupMember -Identity "GRP_Migration_Temp" -Members "GRP_Projet_2019" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Projet_2019 -> GRP_Migration_Temp" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_Backup_Operators" -Members "GRP_Migration_Temp" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Migration_Temp -> GRP_Backup_Operators" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Server Operators" -Members "GRP_Backup_Operators" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Backup_Operators -> Server Operators" -ForegroundColor Red } catch {}
Write-Host "  -> [PATH 5] Projet_2019 (stale) -> Migration_Temp -> Backup_Ops -> Server Ops" -ForegroundColor Magenta

# CHAINE 6: Distribution -> Security (erreur classique)
try { Add-ADGroupMember -Identity "GRP_IT_Infra" -Members "DL_IT" -ErrorAction Stop; Write-Host "  -> [CASCADE] DL_IT (distrib) -> GRP_IT_Infra (securite!)" -ForegroundColor Red } catch {}

# CHAINE 7: Cycle circulaire (boucle)
try { Add-ADGroupMember -Identity "GRP_Test_Prod" -Members "GRP_Legacy_Services" -ErrorAction Stop; Write-Host "  -> [CASCADE] GRP_Legacy_Services -> GRP_Test_Prod" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "GRP_Legacy_Services" -Members "GRP_Test_Prod" -ErrorAction Stop; Write-Host "  -> [CIRCULAR] GRP_Test_Prod -> GRP_Legacy_Services (boucle!)" -ForegroundColor Red } catch {}

# ================================================================
# NESTED GROUPS PRIVILEGIES (classiques)
# ================================================================
Write-Host "`n  --- Nested groups dans groupes privilegies ---" -ForegroundColor Red

try { Add-ADGroupMember -Identity "Print Operators" -Members "GRP_IT" -ErrorAction Stop; Write-Host "  -> [PRINT OPS] GRP_IT dans Print Operators" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Account Operators" -Members "maxime.petit" -ErrorAction Stop; Write-Host "  -> [ACCOUNT OPS] maxime.petit" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Server Operators" -Members "damien.leclerc" -ErrorAction Stop; Write-Host "  -> [SERVER OPS] damien.leclerc" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Remote Desktop Users" -Members "GRP_Commercial" -ErrorAction Stop; Write-Host "  -> [RDP USERS] GRP_Commercial dans Remote Desktop Users" -ForegroundColor Red } catch {}
try { Add-ADGroupMember -Identity "Cert Publishers" -Members "sophie.durand" -ErrorAction Stop; Write-Host "  -> [CERT PUB] sophie.durand dans Cert Publishers" -ForegroundColor Red } catch {}

# [DNS Admins - deja dans 04j mais aussi ACL ici]
try { Add-ADGroupMember -Identity "DnsAdmins" -Members "GRP_IT_Infra" -ErrorAction Stop; Write-Host "  -> [DNS ADMINS] GRP_IT_Infra dans DnsAdmins!" -ForegroundColor Red } catch {}

# [Schema Admins trop peuple]
try { Add-ADGroupMember -Identity "Schema Admins" -Members "adm.thomas.laurent" -ErrorAction Stop; Write-Host "  -> [SCHEMA ADMINS] adm.thomas.laurent (devrait etre vide)" -ForegroundColor Red } catch {}

# [Group Policy Creator Owners]
try { Add-ADGroupMember -Identity "Group Policy Creator Owners" -Members "nicolas.bernard" -ErrorAction Stop; Write-Host "  -> [GPO CREATOR] nicolas.bernard dans Group Policy Creator Owners" -ForegroundColor Red } catch {}

# ================================================================
# ACLs DANGEREUSES SUR OBJETS AD
# ================================================================
Write-Host "`n  --- ACLs dangereuses sur objets ---" -ForegroundColor Red
$domainDNObj = (Get-ADDomain).DistinguishedName

# [WRITEDACL sur domaine]
try {
    $acl = Get-Acl "AD:\$domainDNObj"
    $sid = (Get-ADUser "svc_deploy_prod").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "WriteDacl", "Allow")))
    Set-Acl "AD:\$domainDNObj" $acl
    Write-Host "  -> [WRITEDACL] svc_deploy_prod sur domaine" -ForegroundColor Red
} catch { Write-Host "  -> Erreur WriteDACL: $_" -ForegroundColor Gray }

# [GENERICALL sur OU Entreprise]
try {
    $acl = Get-Acl "AD:\OU=Entreprise,$DomainDN"
    $sid = (Get-ADUser "hugo.blanc").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericAll", "Allow")))
    Set-Acl "AD:\OU=Entreprise,$DomainDN" $acl
    Write-Host "  -> [GENERICALL] hugo.blanc sur OU Entreprise (controle tous les users)" -ForegroundColor Red
} catch { Write-Host "  -> Erreur GenericAll: $_" -ForegroundColor Gray }

# [GENERICALL sur OU Admin_Tier0]
try {
    $acl = Get-Acl "AD:\OU=Admin_Tier0,$DomainDN"
    $sid = (Get-ADUser "svc_sccm").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericAll", "Allow")))
    Set-Acl "AD:\OU=Admin_Tier0,$DomainDN" $acl
    Write-Host "  -> [GENERICALL] svc_sccm sur OU Admin_Tier0!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur GenericAll Tier0: $_" -ForegroundColor Gray }

# [DCSYNC pour svc_monitor - Replicating Directory Changes + All]
try {
    $acl = Get-Acl "AD:\$domainDNObj"
    $sid = (Get-ADUser "svc_monitor").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2")))  # DS-Replication-Get-Changes
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2")))  # DS-Replication-Get-Changes-All
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"89e95b76-444d-4c62-991a-0facbeda640c")))  # DS-Replication-Get-Changes-In-Filtered-Set
    Set-Acl "AD:\$domainDNObj" $acl
    Write-Host "  -> [DCSYNC] svc_monitor a DCSync complet!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DCSync: $_" -ForegroundColor Gray }

# [DCSYNC pour ext.old.admin aussi - presta avec DCSync]
try {
    $acl = Get-Acl "AD:\$domainDNObj"
    $sid = (Get-ADUser "ext.old.admin").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"1131f6aa-9c07-11d1-f79f-00c04fc2dcd2")))
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"1131f6ad-9c07-11d1-f79f-00c04fc2dcd2")))
    Set-Acl "AD:\$domainDNObj" $acl
    Write-Host "  -> [DCSYNC] ext.old.admin (presta) a DCSync!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DCSync ext: $_" -ForegroundColor Gray }

# [GENERICWRITE sur Domain Admins]
try {
    $da = Get-ADGroup "Domain Admins"
    $acl = Get-Acl "AD:\$($da.DistinguishedName)"
    $sid = (Get-ADUser "chloe.fournier").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericWrite", "Allow")))
    Set-Acl "AD:\$($da.DistinguishedName)" $acl
    Write-Host "  -> [GENERICWRITE] chloe.fournier sur Domain Admins (peut ajouter des membres)" -ForegroundColor Red
} catch { Write-Host "  -> Erreur GenericWrite DA: $_" -ForegroundColor Gray }

# [GENERICWRITE sur Enterprise Admins]
try {
    $ea = Get-ADGroup "Enterprise Admins"
    $acl = Get-Acl "AD:\$($ea.DistinguishedName)"
    $sid = (Get-ADGroup "GRP_IT_Dev").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericWrite", "Allow")))
    Set-Acl "AD:\$($ea.DistinguishedName)" $acl
    Write-Host "  -> [GENERICWRITE] GRP_IT_Dev sur Enterprise Admins!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur GenericWrite EA: $_" -ForegroundColor Gray }

# [WRITEOWNER sur admin]
try {
    $target = Get-ADUser "adm.thomas.laurent"
    $acl = Get-Acl "AD:\$($target.DistinguishedName)"
    $sid = (Get-ADUser "lea.dubois").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "WriteOwner", "Allow")))
    Set-Acl "AD:\$($target.DistinguishedName)" $acl
    Write-Host "  -> [WRITEOWNER] lea.dubois sur adm.thomas.laurent" -ForegroundColor Red
} catch { Write-Host "  -> Erreur WriteOwner: $_" -ForegroundColor Gray }

# [WRITEOWNER sur le domaine entier]
try {
    $acl = Get-Acl "AD:\$domainDNObj"
    $sid = (Get-ADUser "svc_sharepoint").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "WriteOwner", "Allow")))
    Set-Acl "AD:\$domainDNObj" $acl
    Write-Host "  -> [WRITEOWNER] svc_sharepoint WriteOwner sur le domaine!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur WriteOwner domain: $_" -ForegroundColor Gray }

# [RESET PASSWORD sur admin]
try {
    $target = Get-ADUser "adm.antoine.mercier"
    $acl = Get-Acl "AD:\$($target.DistinguishedName)"
    $sid = (Get-ADUser "nathan.giraud").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"00299570-246d-11d0-a768-00aa006e0529")))
    Set-Acl "AD:\$($target.DistinguishedName)" $acl
    Write-Host "  -> [RESET PWD] nathan.giraud peut reset adm.antoine.mercier" -ForegroundColor Red
} catch { Write-Host "  -> Erreur ResetPwd: $_" -ForegroundColor Gray }

# [RESET PASSWORD sur tous les DA par un helpdesk]
try {
    $da = Get-ADGroup "Domain Admins"
    $acl = Get-Acl "AD:\$($da.DistinguishedName)"
    $sid = (Get-ADUser "camille.robin").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow", [GUID]"00299570-246d-11d0-a768-00aa006e0529")))
    Set-Acl "AD:\$($da.DistinguishedName)" $acl
    Write-Host "  -> [RESET PWD] camille.robin (helpdesk N1) peut reset pwd sur DA group!" -ForegroundColor Red
} catch {}

# [ALLEXTENDED RIGHTS sur OU Services]
try {
    $acl = Get-Acl "AD:\OU=Services_Comptes,$DomainDN"
    $sid = (Get-ADUser "maxime.petit").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "ExtendedRight", "Allow")))
    Set-Acl "AD:\OU=Services_Comptes,$DomainDN" $acl
    Write-Host "  -> [ALL EXTENDED] maxime.petit AllExtendedRights sur OU Services" -ForegroundColor Red
} catch { Write-Host "  -> Erreur AllExtended: $_" -ForegroundColor Gray }

# [ADDMEMBER droit explicite sur Domain Admins]
try {
    $da = Get-ADGroup "Domain Admins"
    $acl = Get-Acl "AD:\$($da.DistinguishedName)"
    $sid = (Get-ADUser "svc_web_front").SID
    $addMemberGuid = [GUID]"bf9679c0-0de6-11d0-a285-00aa003049e2"  # Member attribute
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "WriteProperty", "Allow", $addMemberGuid)))
    Set-Acl "AD:\$($da.DistinguishedName)" $acl
    Write-Host "  -> [ADDMEMBER] svc_web_front peut modifier les membres de Domain Admins!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur AddMember: $_" -ForegroundColor Gray }

# [WRITE SPN - Kerberoasting cible]
try {
    $target = Get-ADUser "adm.catherine.morel"
    $acl = Get-Acl "AD:\$($target.DistinguishedName)"
    $sid = (Get-ADUser "alexandre.chevalier").SID
    $spnGuid = [GUID]"f3a64788-5306-11d1-a9c5-0000f80367c1"  # servicePrincipalName
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "WriteProperty", "Allow", $spnGuid)))
    Set-Acl "AD:\$($target.DistinguishedName)" $acl
    Write-Host "  -> [WRITE SPN] alexandre.chevalier peut set SPN sur adm.catherine.morel (targeted kerberoast)" -ForegroundColor Red
} catch { Write-Host "  -> Erreur WriteSPN: $_" -ForegroundColor Gray }

# ================================================================
# ADMINSDHOLER TAMPERING
# ================================================================
Write-Host "`n  --- AdminSDHolder ---" -ForegroundColor Red

try {
    $adminSDHolder = Get-ADObject -Identity "CN=AdminSDHolder,CN=System,$DomainDN"
    $acl = Get-Acl "AD:\$($adminSDHolder.DistinguishedName)"

    # GenericAll pour svc_deploy_prod sur AdminSDHolder
    $sid = (Get-ADUser "svc_deploy_prod").SID
    $acl.AddAccessRule((New-Object System.DirectoryServices.ActiveDirectoryAccessRule($sid, "GenericAll", "Allow")))
    Set-Acl "AD:\$($adminSDHolder.DistinguishedName)" $acl
    Write-Host "  -> [ADMINSDHOLER] svc_deploy_prod GenericAll sur AdminSDHolder!" -ForegroundColor Red
    Write-Host "         SDProp propagera ce droit a TOUS les comptes proteges (DA, EA...)" -ForegroundColor Red
} catch { Write-Host "  -> Erreur AdminSDHolder: $_" -ForegroundColor Gray }

# [Owned relationships - user owns un objet admin]
try {
    $adminObj = Get-ADUser "adm.nicolas.bernard"
    $acl = Get-Acl "AD:\$($adminObj.DistinguishedName)"
    $owner = New-Object System.Security.Principal.NTAccount("LAB","hugo.blanc")
    $acl.SetOwner($owner)
    Set-Acl "AD:\$($adminObj.DistinguishedName)" $acl
    Write-Host "  -> [OWNS] hugo.blanc est OWNER de adm.nicolas.bernard" -ForegroundColor Red
} catch { Write-Host "  -> Erreur Owns: $_" -ForegroundColor Gray }

Write-Host "`n  -> ACLs et chaines de propagation configurees." -ForegroundColor Cyan
