<#
.SYNOPSIS
    Cree les utilisateurs standards (80+)
    Anomalies: users inactifs, AS-REP sur users, password dans description,
    users dans CN=Users, users sans groupe, users avec PasswordNotRequired
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$DefaultPassword = "Cim22091956!!??",
    [string]$WeakPassword = "Password1"
)

Write-Host "`n[USERS] Creation des utilisateurs..." -ForegroundColor Yellow

$securePass = ConvertTo-SecureString $DefaultPassword -AsPlainText -Force
$weakPass = ConvertTo-SecureString $WeakPassword -AsPlainText -Force

$users = @(
    # Direction
    @{First="Jean-Pierre"; Last="Delacroix"; Title="PDG"; Dept="Direction"; OU="Direction"; Groups=@("GRP_Direction","GRP_VPN_Users","GRP_Managers","DL_Direction","DL_Tous","GRP_MFA_Exempt")},
    @{First="Marie"; Last="Fontaine"; Title="DRH"; Dept="Direction"; OU="Direction"; Groups=@("GRP_Direction","GRP_RH","GRP_Managers","DL_Direction","DL_Tous")},
    @{First="Philippe"; Last="Beaumont"; Title="DAF"; Dept="Direction"; OU="Direction"; Groups=@("GRP_Direction","GRP_Finance","GRP_Managers","DL_Direction","DL_Tous")},
    @{First="Catherine"; Last="Morel"; Title="DSI"; Dept="Direction"; OU="Direction"; Groups=@("GRP_Direction","GRP_IT","GRP_IT_Admins","GRP_Managers","DL_Direction","DL_Tous")},
    @{First="Bernard"; Last="Dupont"; Title="DGA"; Dept="Direction"; OU="Direction"; Groups=@("GRP_Direction","GRP_Managers","DL_Direction","DL_Tous","GRP_VPN_Users")},
    # IT Infra
    @{First="Thomas"; Last="Laurent"; Title="Responsable Infra"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_IT_Admins","GRP_VPN_Users","GRP_RDP_Users","GRP_Managers","GRP_LAPS_Read","DL_IT","DL_Tous")},
    @{First="Nicolas"; Last="Bernard"; Title="Admin Systeme Senior"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_VPN_Users","GRP_RDP_Users","GRP_LAPS_Read","DL_IT","DL_Tous")},
    @{First="Julien"; Last="Moreau"; Title="Admin Reseau"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_VPN_Users","GRP_RDP_Users","DL_IT","DL_Tous")},
    @{First="Sophie"; Last="Durand"; Title="Admin Cloud Azure"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_VPN_Users","GRP_Azure_Sync","DL_IT","DL_Tous")},
    @{First="Pierre-Antoine"; Last="Vasseur"; Title="Admin Systeme Junior"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_RDP_Users","DL_IT","DL_Tous")},
    @{First="Damien"; Last="Leclerc"; Title="Admin Virtualisation"; Dept="IT"; OU="Infrastructure"; Groups=@("GRP_IT","GRP_IT_Infra","GRP_VPN_Users","GRP_RDP_Users","DL_IT","DL_Tous")},
    # IT Helpdesk
    @{First="Maxime"; Last="Petit"; Title="Responsable Helpdesk"; Dept="IT"; OU="Helpdesk"; Groups=@("GRP_IT","GRP_IT_Helpdesk","GRP_Managers","GRP_Local_Admins","DL_IT","DL_Tous")},
    @{First="Camille"; Last="Robin"; Title="Technicien Support N1"; Dept="IT"; OU="Helpdesk"; Groups=@("GRP_IT","GRP_IT_Helpdesk","DL_IT","DL_Tous")},
    @{First="Hugo"; Last="Blanc"; Title="Technicien Support N2"; Dept="IT"; OU="Helpdesk"; Groups=@("GRP_IT","GRP_IT_Helpdesk","GRP_Local_Admins","DL_IT","DL_Tous")},
    @{First="Emma"; Last="Faure"; Title="Technicien Support N1"; Dept="IT"; OU="Helpdesk"; Groups=@("GRP_IT","GRP_IT_Helpdesk","DL_IT","DL_Tous")},
    @{First="Nathan"; Last="Giraud"; Title="Technicien Support N1"; Dept="IT"; OU="Helpdesk"; Groups=@("GRP_IT","GRP_IT_Helpdesk","DL_IT","DL_Tous")},
    # IT Dev
    @{First="Alexandre"; Last="Chevalier"; Title="Lead Dev"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","GRP_Managers","GRP_VPN_Users","DL_IT","DL_Tous")},
    @{First="Lea"; Last="Dubois"; Title="Dev Backend Senior"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","GRP_VPN_Users","DL_IT","DL_Tous")},
    @{First="Lucas"; Last="Roux"; Title="Dev Frontend"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","DL_IT","DL_Tous")},
    @{First="Chloe"; Last="Fournier"; Title="DevOps"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","GRP_IT_Infra","GRP_VPN_Users","GRP_RDP_Users","DL_IT","DL_Tous")},
    @{First="Theo"; Last="Lemaire"; Title="Dev Mobile"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","DL_IT","DL_Tous")},
    @{First="Ines"; Last="Roussel"; Title="QA Engineer"; Dept="IT"; OU="Developpement"; Groups=@("GRP_IT","GRP_IT_Dev","DL_IT","DL_Tous")},
    # IT DBA
    @{First="Yannick"; Last="Picard"; Title="DBA Senior"; Dept="IT"; OU="DBA"; Groups=@("GRP_IT","GRP_IT_DBA","GRP_VPN_Users","GRP_RDP_Users","DL_IT","DL_Tous")},
    @{First="Aurelie"; Last="Marchand"; Title="DBA Junior"; Dept="IT"; OU="DBA"; Groups=@("GRP_IT","GRP_IT_DBA","DL_IT","DL_Tous")},
    # Securite
    @{First="Antoine"; Last="Mercier"; Title="RSSI"; Dept="Securite"; OU="SOC"; Groups=@("GRP_Securite","GRP_SOC","GRP_IT_Admins","GRP_VPN_Users","GRP_RDP_Users","GRP_Managers","DL_IT","DL_Tous")},
    @{First="Clara"; Last="Lefevre"; Title="Analyste SOC N2"; Dept="Securite"; OU="SOC"; Groups=@("GRP_Securite","GRP_SOC","GRP_VPN_Users","DL_IT","DL_Tous")},
    @{First="Mathieu"; Last="Garnier"; Title="Analyste SOC N1"; Dept="Securite"; OU="SOC"; Groups=@("GRP_Securite","GRP_SOC","GRP_VPN_Users","DL_IT","DL_Tous")},
    @{First="Julie"; Last="Perrin"; Title="Pentester Senior"; Dept="Securite"; OU="Pentest"; Groups=@("GRP_Securite","GRP_Pentest","GRP_VPN_Users","GRP_RDP_Users","DL_IT","DL_Tous")},
    @{First="Remi"; Last="Collet"; Title="Pentester Junior"; Dept="Securite"; OU="Pentest"; Groups=@("GRP_Securite","GRP_Pentest","GRP_VPN_Users","DL_IT","DL_Tous")},
    @{First="Sarah"; Last="Benali"; Title="GRC Analyst"; Dept="Securite"; OU="GRC"; Groups=@("GRP_Securite","GRP_GRC","DL_IT","DL_Tous")},
    @{First="Vincent"; Last="Masson"; Title="GRC Manager"; Dept="Securite"; OU="GRC"; Groups=@("GRP_Securite","GRP_GRC","GRP_Managers","DL_IT","DL_Tous")},
    # RH
    @{First="Isabelle"; Last="Rousseau"; Title="Responsable RH"; Dept="RH"; OU="RH"; Groups=@("GRP_RH","GRP_Managers","ACL_Partage_RH_RW","DL_Tous")},
    @{First="Stephanie"; Last="Clement"; Title="Chargee recrutement"; Dept="RH"; OU="RH"; Groups=@("GRP_RH","ACL_Partage_RH_RW","DL_Tous")},
    @{First="Pauline"; Last="Guillaume"; Title="Gestionnaire paie"; Dept="RH"; OU="RH"; Groups=@("GRP_RH","ACL_Partage_RH_RW","DL_Tous")},
    @{First="David"; Last="Henry"; Title="Responsable Formation"; Dept="RH"; OU="RH"; Groups=@("GRP_RH","ACL_Partage_RH_RW","DL_Tous")},
    @{First="Lucie"; Last="Fabre"; Title="Assistante RH"; Dept="RH"; OU="RH"; Groups=@("GRP_RH","ACL_Partage_RH_RW","DL_Tous")},
    # Finance
    @{First="Pierre"; Last="Bonnet"; Title="Directeur Financier"; Dept="Finance"; OU="Finance"; Groups=@("GRP_Finance","GRP_Managers","ACL_Partage_Finance_RW","DL_Tous")},
    @{First="Nathalie"; Last="Lambert"; Title="Comptable Senior"; Dept="Finance"; OU="Finance"; Groups=@("GRP_Finance","ACL_Partage_Finance_RW","DL_Tous")},
    @{First="Laurent"; Last="Martinez"; Title="Controleur gestion"; Dept="Finance"; OU="Finance"; Groups=@("GRP_Finance","ACL_Partage_Finance_RW","DL_Tous")},
    @{First="Valerie"; Last="Girard"; Title="Tresoriere"; Dept="Finance"; OU="Finance"; Groups=@("GRP_Finance","ACL_Partage_Finance_RW","DL_Tous")},
    @{First="Christophe"; Last="Morin"; Title="Comptable Junior"; Dept="Finance"; OU="Finance"; Groups=@("GRP_Finance","ACL_Partage_Finance_RW","DL_Tous")},
    # Commercial
    @{First="Olivier"; Last="Andre"; Title="Directeur Commercial"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_Managers","GRP_VPN_Users","DL_Tous")},
    @{First="Sandrine"; Last="Lefebvre"; Title="Resp Grands Comptes"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_VPN_Users","GRP_Managers","DL_Tous")},
    @{First="Franck"; Last="Leroy"; Title="Commercial Terrain Nord"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_VPN_Users","DL_Tous")},
    @{First="Aurelie"; Last="Simon"; Title="Commerciale Terrain Sud"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_VPN_Users","DL_Tous")},
    @{First="Sebastien"; Last="Michel"; Title="Commercial Sedentaire"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","DL_Tous")},
    @{First="Caroline"; Last="Garcia"; Title="Assistante Commerciale"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","DL_Tous")},
    @{First="Guillaume"; Last="Perez"; Title="Business Developer"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_VPN_Users","DL_Tous")},
    @{First="Melanie"; Last="Lopez"; Title="Account Manager"; Dept="Commercial"; OU="Commercial"; Groups=@("GRP_Commercial","GRP_VPN_Users","DL_Tous")},
    # R&D
    @{First="Marc"; Last="David"; Title="Directeur R&D"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_Managers","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    @{First="Elodie"; Last="Bertrand"; Title="Ingenieur Recherche Senior"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    @{First="Romain"; Last="Thomas"; Title="Ingenieur Recherche"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    @{First="Marine"; Last="Robert"; Title="Data Scientist"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    @{First="Adrien"; Last="Noel"; Title="Ingenieur IA"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    @{First="Camille"; Last="Renard"; Title="Bio-informaticien"; Dept="R_et_D"; OU="R_et_D"; Groups=@("GRP_R_D","GRP_VPN_Users","ACL_Partage_R_D_RW","DL_Tous")},
    # Juridique
    @{First="Francois"; Last="Richard"; Title="Directeur Juridique"; Dept="Juridique"; OU="Juridique"; Groups=@("GRP_Juridique","GRP_Managers","DL_Tous")},
    @{First="Emilie"; Last="Duval"; Title="Juriste Senior"; Dept="Juridique"; OU="Juridique"; Groups=@("GRP_Juridique","DL_Tous")},
    @{First="Arnaud"; Last="Caron"; Title="Juriste RGPD/DPO"; Dept="Juridique"; OU="Juridique"; Groups=@("GRP_Juridique","DL_Tous")},
    # Support
    @{First="Kevin"; Last="Muller"; Title="Resp Support Client"; Dept="Support"; OU="Support"; Groups=@("GRP_Support","GRP_Managers","DL_Tous")},
    @{First="Manon"; Last="Legrand"; Title="Charge Support N2"; Dept="Support"; OU="Support"; Groups=@("GRP_Support","DL_Tous")},
    @{First="Florian"; Last="Colin"; Title="Charge Support N1"; Dept="Support"; OU="Support"; Groups=@("GRP_Support","DL_Tous")},
    @{First="Amandine"; Last="Dupuis"; Title="Charge Support N1"; Dept="Support"; OU="Support"; Groups=@("GRP_Support","DL_Tous")},
    @{First="Dylan"; Last="Lemoine"; Title="Charge Support N1"; Dept="Support"; OU="Support"; Groups=@("GRP_Support","DL_Tous")},
    # Communication
    @{First="Charlotte"; Last="Barbier"; Title="Dir Communication"; Dept="Communication"; OU="Communication"; Groups=@("GRP_Communication","GRP_Managers","DL_Tous")},
    @{First="Quentin"; Last="Rolland"; Title="Community Manager"; Dept="Communication"; OU="Communication"; Groups=@("GRP_Communication","DL_Tous")},
    @{First="Margaux"; Last="Prevost"; Title="Graphiste"; Dept="Communication"; OU="Communication"; Groups=@("GRP_Communication","DL_Tous")},
    # Logistique
    @{First="Pascal"; Last="Gauthier"; Title="Resp Logistique"; Dept="Logistique"; OU="Logistique"; Groups=@("GRP_Logistique","GRP_Managers","DL_Tous")},
    @{First="Sylvie"; Last="Leconte"; Title="Gestionnaire Stocks"; Dept="Logistique"; OU="Logistique"; Groups=@("GRP_Logistique","DL_Tous")},
    @{First="Mickael"; Last="Brun"; Title="Agent Logistique"; Dept="Logistique"; OU="Logistique"; Groups=@("GRP_Logistique","DL_Tous")},
    # Medical
    @{First="Claire"; Last="Dumas"; Title="Medecin du travail"; Dept="Medical"; OU="Medical"; Groups=@("DL_Tous")},
    @{First="Patrick"; Last="Vidal"; Title="Infirmier"; Dept="Medical"; OU="Medical"; Groups=@("DL_Tous")}
)

$created = 0
foreach ($u in $users) {
    $sam = "$($u.First).$($u.Last)".ToLower() -replace " ","-" -replace "'",""
    $upn = "$sam@$DomainName"
    $displayName = "$($u.First) $($u.Last)"

    if ($u.OU -in @("Infrastructure","Helpdesk","Developpement","DBA")) {
        $ouPath = "OU=$($u.OU),OU=IT,OU=Entreprise,$DomainDN"
    } elseif ($u.OU -in @("SOC","GRC","Pentest")) {
        $ouPath = "OU=$($u.OU),OU=Securite,OU=Entreprise,$DomainDN"
    } else {
        $ouPath = "OU=$($u.OU),OU=Entreprise,$DomainDN"
    }

    try {
        New-ADUser -Name $displayName -GivenName $u.First -Surname $u.Last `
            -SamAccountName $sam -UserPrincipalName $upn -DisplayName $displayName `
            -Title $u.Title -Department $u.Dept -Company "LabCorp Medical" -Office "Siege - Paris" `
            -EmailAddress "$sam@labcorp.local" -Path $ouPath -AccountPassword $securePass `
            -ChangePasswordAtLogon $false -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        foreach ($grp in $u.Groups) { Add-ADGroupMember -Identity $grp -Members $sam -ErrorAction SilentlyContinue }
        $created++
        Write-Host "  -> $displayName ($sam)" -ForegroundColor Green
    } catch { Write-Host "  -> $displayName existe deja." -ForegroundColor Gray }
}
Write-Host "  -> $created utilisateurs standards crees." -ForegroundColor Cyan

# ================================================================
# UTILISATEURS VULNERABLES
# ================================================================
Write-Host "`n  --- Utilisateurs VULNERABLES ---" -ForegroundColor Red

# [AS-REP ROASTING sur users standards]
foreach ($sam in @("jean-pierre.delacroix","philippe.beaumont","olivier.andre")) {
    try {
        Set-ADAccountControl -Identity $sam -DoesNotRequirePreAuth $true -ErrorAction Stop
        Write-Host "  -> [AS-REP ROAST] $sam (user VIP sans pre-auth!)" -ForegroundColor Red
    } catch { Write-Host "  -> Erreur AS-REP $sam : $_" -ForegroundColor Gray }
}

# [PASSWORD DANS DESCRIPTION - users]
try {
    Set-ADUser -Identity "franck.leroy" -Description "Commercial terrain - VPN: franck/Comercial2024! - voir wiki" -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] franck.leroy mot de passe VPN dans description" -ForegroundColor Red
} catch {}
try {
    Set-ADUser -Identity "sebastien.michel" -Description "Acces CRM: login=smichel pwd=Crm2024Pass" -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] sebastien.michel credentials CRM dans description" -ForegroundColor Red
} catch {}
try {
    Set-ADUser -Identity "pascal.gauthier" -Description "Wifi: SSID=LabCorp-IoT Key=WifiIoT2023!" -ErrorAction Stop
    Write-Host "  -> [PWD IN DESC] pascal.gauthier cle WiFi dans description" -ForegroundColor Red
} catch {}

# [USER DANS CN=Users - pas dans la bonne OU]
foreach ($misplaced in @(
    @{Name="Stagiaire Ete 2024"; Sam="stagiaire.ete2024"; Title="Stagiaire IT"},
    @{Name="Consultant Externe"; Sam="consultant.externe"; Title="Consultant"},
    @{Name="Test Application"; Sam="test.application"; Title="Compte de test"}
)) {
    try {
        New-ADUser -Name $misplaced.Name -SamAccountName $misplaced.Sam -UserPrincipalName "$($misplaced.Sam)@$DomainName" `
            -Title $misplaced.Title -Path "CN=Users,$DomainDN" -AccountPassword $weakPass `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Write-Host "  -> [WRONG OU] $($misplaced.Sam) dans CN=Users" -ForegroundColor Red
    } catch { Write-Host "  -> $($misplaced.Sam) existe deja." -ForegroundColor Gray }
}

# [USERS INACTIFS - comptes jamais utilises ou tres vieux]
foreach ($inactive in @(
    @{Name="Ex Employe Dupuis"; Sam="ex.employe.dupuis"; Desc="Parti en 2021 - compte non desactive"},
    @{Name="Ex Employe Moreau"; Sam="ex.employe.moreau"; Desc="Licencie 03/2022 - oublie"},
    @{Name="Migration User Test"; Sam="migration.test"; Desc="Cree pendant migration 2020"}
)) {
    try {
        New-ADUser -Name $inactive.Name -SamAccountName $inactive.Sam -UserPrincipalName "$($inactive.Sam)@$DomainName" `
            -Description $inactive.Desc -Path "OU=Entreprise,$DomainDN" -AccountPassword $weakPass `
            -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        # Forcer un pwdLastSet ancien
        Set-ADUser -Identity $inactive.Sam -Replace @{"pwdLastSet"=0}
        Write-Host "  -> [INACTIVE] $($inactive.Sam) - $($inactive.Desc)" -ForegroundColor Red
    } catch { Write-Host "  -> $($inactive.Sam) existe deja." -ForegroundColor Gray }
}

# [USER avec PasswordNotRequired]
try {
    Set-ADAccountControl -Identity "stagiaire.ete2024" -PasswordNotRequired $true -ErrorAction Stop
    Write-Host "  -> [NO PWD REQ] stagiaire.ete2024 PasswordNotRequired" -ForegroundColor Red
} catch {}

# [USER avec SPN (targeted kerberoasting sur un user normal)]
try {
    Set-ADUser -Identity "yannick.picard" -ServicePrincipalNames @{Add="MSSQLSvc/reporting.lab.local:1433"} -ErrorAction Stop
    Write-Host "  -> [USER SPN] yannick.picard a un SPN (kerberoastable DBA)" -ForegroundColor Red
} catch {}

# [USER avec reversible encryption]
try {
    Set-ADUser -Identity "sophie.durand" -AllowReversiblePasswordEncryption $true -ErrorAction Stop
    Write-Host "  -> [REVERSIBLE] sophie.durand chiffrement reversible" -ForegroundColor Red
} catch {}

# [USER avec trop de groupes (token bloat)]
try {
    $overGrouped = "thomas.laurent"
    foreach ($grp in @("GRP_Wifi_Corp","GRP_Wifi_Guest","GRP_PrintOperators","GRP_Backup_Operators","ACL_Partage_Commun_RW","ACL_Partage_IT_RW","ACL_Partage_Direction_RW","GRP_Azure_Sync","GRP_MFA_Exempt")) {
        Add-ADGroupMember -Identity $grp -Members $overGrouped -ErrorAction SilentlyContinue
    }
    Write-Host "  -> [TOKEN BLOAT] thomas.laurent dans 15+ groupes" -ForegroundColor Red
} catch {}

Write-Host "`n  -> Utilisateurs configures." -ForegroundColor Cyan
