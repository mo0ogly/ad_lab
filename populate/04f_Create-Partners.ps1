<#
.SYNOPSIS
    Cree les comptes partenaires, externes et generiques
    Anomalies: prestataire DA, comptes partages, mdp faibles, comptes jamais expires,
    comptes sans expiration, comptes dans mauvaise OU
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$WeakPassword = "Password1"
)

Write-Host "`n[PARTENAIRES] Comptes partenaires et generiques..." -ForegroundColor Yellow

$weakPass = ConvertTo-SecureString $WeakPassword -AsPlainText -Force
$partnerPath = "OU=Partenaires,$DomainDN"

# --- Partenaires normaux ---
foreach ($p in @(
    @{Name="ext.cabinet.audit"; Desc="Auditeur PwC - mission annuelle"; Groups=@("GRP_VPN_Users","ACL_Partage_Finance_RW")},
    @{Name="ext.presta.dev"; Desc="Dev Capgemini - projet CRM"; Groups=@("GRP_IT_Dev","GRP_VPN_Users","GRP_RDP_Users")},
    @{Name="ext.support.sap"; Desc="Support SAP - contrat cadre"; Groups=@("GRP_VPN_Users","GRP_RDP_Users")},
    @{Name="ext.maintenance"; Desc="Maintenance Orange Business"; Groups=@("GRP_VPN_Users")},
    @{Name="ext.avocat.dupond"; Desc="Avocat conseil - cabinet Dupond"; Groups=@("GRP_VPN_Users")},
    @{Name="ext.audit.anssi"; Desc="Auditeur ANSSI - controle ponctuel"; Groups=@("GRP_VPN_Users")},
    @{Name="ext.soc.thales"; Desc="Analyste SOC Thales MDR"; Groups=@("GRP_SOC","GRP_VPN_Users","GRP_RDP_Users")},
    @{Name="ext.infra.atos"; Desc="Admin infra Atos - TMA"; Groups=@("GRP_IT_Infra","GRP_VPN_Users","GRP_RDP_Users")}
)) {
    try {
        New-ADUser -Name $p.Name -SamAccountName $p.Name -UserPrincipalName "$($p.Name)@$DomainName" `
            -Description $p.Desc -Path $partnerPath -AccountPassword $weakPass `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        foreach ($grp in $p.Groups) { Add-ADGroupMember -Identity $grp -Members $p.Name -ErrorAction SilentlyContinue }
        Add-ADGroupMember -Identity "DL_Partenaires" -Members $p.Name -ErrorAction SilentlyContinue
        Write-Host "  -> $($p.Name)" -ForegroundColor Green
    } catch { Write-Host "  -> $($p.Name) existe deja." -ForegroundColor Gray }
}

# ================================================================
# PARTENAIRES VULNERABLES
# ================================================================
Write-Host "`n  --- Partenaires VULNERABLES ---" -ForegroundColor Red

# [PRESTA DANS DOMAIN ADMINS]
try {
    New-ADUser -Name "ext.old.admin" -SamAccountName "ext.old.admin" -UserPrincipalName "ext.old.admin@$DomainName" `
        -Description "Ex presta Sopra - mission terminee 2022 - acces non revoque" -Path $partnerPath -AccountPassword $weakPass `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "ext.old.admin"
    Add-ADGroupMember -Identity "DL_Partenaires" -Members "ext.old.admin" -ErrorAction SilentlyContinue
    Write-Host "  -> [EXT IN DA] ext.old.admin prestataire dans Domain Admins!" -ForegroundColor Red
} catch { Write-Host "  -> ext.old.admin existe deja." -ForegroundColor Gray }

# [PRESTA AVEC SPN - kerberoastable]
try {
    New-ADUser -Name "ext.dba.oracle" -SamAccountName "ext.dba.oracle" -UserPrincipalName "ext.dba.oracle@$DomainName" `
        -Description "DBA Oracle externe - contrat 2021" -Path $partnerPath -AccountPassword $weakPass `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Set-ADUser -Identity "ext.dba.oracle" -ServicePrincipalNames @{Add="oracle/oradb-legacy.lab.local:1521"}
    Add-ADGroupMember -Identity "DL_Partenaires" -Members "ext.dba.oracle" -ErrorAction SilentlyContinue
    Write-Host "  -> [EXT KERBEROAST] ext.dba.oracle avec SPN Oracle" -ForegroundColor Red
} catch { Write-Host "  -> ext.dba.oracle existe deja." -ForegroundColor Gray }

# [PRESTA AVEC AS-REP ROASTING]
try {
    Set-ADAccountControl -Identity "ext.maintenance" -DoesNotRequirePreAuth $true -ErrorAction Stop
    Write-Host "  -> [EXT AS-REP] ext.maintenance sans pre-auth Kerberos" -ForegroundColor Red
} catch {}

# [PRESTA AVEC PASSWORD DANS DESCRIPTION]
try {
    New-ADUser -Name "ext.vpn.generic" -SamAccountName "ext.vpn.generic" -UserPrincipalName "ext.vpn.generic@$DomainName" `
        -Description "Compte VPN generique prestas - pwd: VpnExt2024! - ne pas changer" -Path $partnerPath `
        -AccountPassword (ConvertTo-SecureString "VpnExt2024!" -AsPlainText -Force) `
        -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "GRP_VPN_Users" -Members "ext.vpn.generic" -ErrorAction SilentlyContinue
    Write-Host "  -> [EXT PWD IN DESC] ext.vpn.generic mot de passe dans description" -ForegroundColor Red
} catch { Write-Host "  -> ext.vpn.generic existe deja." -ForegroundColor Gray }

# [PRESTA SANS DATE D'EXPIRATION - mission terminee]
foreach ($name in @("ext.old.admin","ext.dba.oracle","ext.maintenance")) {
    try {
        Set-ADUser -Identity $name -AccountExpirationDate $null -ErrorAction SilentlyContinue
        Write-Host "  -> [NO EXPIRY] $name sans date d'expiration" -ForegroundColor Yellow
    } catch {}
}

# ================================================================
# COMPTES GENERIQUES / PARTAGES
# ================================================================
Write-Host "`n  --- Comptes generiques ---" -ForegroundColor Red

foreach ($generic in @(
    @{Name="accueil"; Desc="PC Accueil - compte partage"},
    @{Name="salle.reunion"; Desc="Salle de reunion - compte partage"},
    @{Name="demo"; Desc="Compte demo client"},
    @{Name="formation"; Desc="Compte formation - mdp: Formation2024!"; Pwd="Formation2024!"},
    @{Name="stagiaire"; Desc="Compte stagiaire generique"},
    @{Name="kiosk.rdc"; Desc="Borne kiosque RDC"},
    @{Name="kiosk.etage1"; Desc="Borne kiosque Etage 1"},
    @{Name="shared.compta"; Desc="Compte partage comptabilite - pwd=Compta2024"},
    @{Name="shared.rh"; Desc="Compte partage RH recrutement"},
    @{Name="test.prod"; Desc="Compte de test en PRODUCTION - ne pas supprimer"}
)) {
    try {
        $pwd = if ($generic.Pwd) { ConvertTo-SecureString $generic.Pwd -AsPlainText -Force } else { $weakPass }
        New-ADUser -Name $generic.Name -SamAccountName $generic.Name -UserPrincipalName "$($generic.Name)@$DomainName" `
            -Description $generic.Desc -Path "OU=Staging,$DomainDN" `
            -AccountPassword $pwd -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Write-Host "  -> [GENERIC] $($generic.Name)" -ForegroundColor Red
    } catch { Write-Host "  -> $($generic.Name) existe deja." -ForegroundColor Gray }
}

# [GENERIC avec trop de droits]
try {
    Add-ADGroupMember -Identity "GRP_RDP_Users" -Members @("formation","demo") -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "GRP_VPN_Users" -Members @("formation","test.prod") -ErrorAction SilentlyContinue
    Add-ADGroupMember -Identity "ACL_Partage_Commun_RW" -Members @("accueil","kiosk.rdc","kiosk.etage1") -ErrorAction SilentlyContinue
    Write-Host "  -> [GENERIC OVERPERM] Comptes generiques avec VPN/RDP/Partages" -ForegroundColor Red
} catch {}

Write-Host "`n  -> Comptes partenaires et generiques configures." -ForegroundColor Cyan
