<#
.SYNOPSIS
    Cree les groupes de securite et distribution
    Anomalies: groupes vides/obsoletes, noms generiques, groupes stale
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[GROUPES] Creation des groupes..." -ForegroundColor Yellow

$groupsPath = "OU=Groupes,$DomainDN"

$groups = @(
    # Departements
    @{Name="GRP_Direction"; Scope="Global"; Cat="Security"; Desc="Membres de la direction"},
    @{Name="GRP_IT"; Scope="Global"; Cat="Security"; Desc="Equipe IT"},
    @{Name="GRP_IT_Admins"; Scope="Global"; Cat="Security"; Desc="Administrateurs IT"},
    @{Name="GRP_IT_Helpdesk"; Scope="Global"; Cat="Security"; Desc="Equipe Helpdesk"},
    @{Name="GRP_IT_Infra"; Scope="Global"; Cat="Security"; Desc="Equipe Infrastructure"},
    @{Name="GRP_IT_Dev"; Scope="Global"; Cat="Security"; Desc="Equipe Developpement"},
    @{Name="GRP_IT_DBA"; Scope="Global"; Cat="Security"; Desc="Administrateurs BDD"},
    @{Name="GRP_Securite"; Scope="Global"; Cat="Security"; Desc="Equipe Securite"},
    @{Name="GRP_SOC"; Scope="Global"; Cat="Security"; Desc="Security Operations Center"},
    @{Name="GRP_GRC"; Scope="Global"; Cat="Security"; Desc="Gouvernance Risque Conformite"},
    @{Name="GRP_Pentest"; Scope="Global"; Cat="Security"; Desc="Equipe Pentest"},
    @{Name="GRP_RH"; Scope="Global"; Cat="Security"; Desc="Equipe RH"},
    @{Name="GRP_Finance"; Scope="Global"; Cat="Security"; Desc="Equipe Finance"},
    @{Name="GRP_Commercial"; Scope="Global"; Cat="Security"; Desc="Equipe Commerciale"},
    @{Name="GRP_R_D"; Scope="Global"; Cat="Security"; Desc="Equipe R&D"},
    @{Name="GRP_Juridique"; Scope="Global"; Cat="Security"; Desc="Equipe Juridique"},
    @{Name="GRP_Support"; Scope="Global"; Cat="Security"; Desc="Equipe Support"},
    @{Name="GRP_Communication"; Scope="Global"; Cat="Security"; Desc="Equipe Communication"},
    @{Name="GRP_Logistique"; Scope="Global"; Cat="Security"; Desc="Equipe Logistique"},
    @{Name="GRP_Medical"; Scope="Global"; Cat="Security"; Desc="Service Medical"},
    # ACL partages
    @{Name="ACL_Partage_Commun_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage commun"},
    @{Name="ACL_Partage_Commun_RO"; Scope="DomainLocal"; Cat="Security"; Desc="RO partage commun"},
    @{Name="ACL_Partage_IT_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage IT"},
    @{Name="ACL_Partage_RH_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage RH"},
    @{Name="ACL_Partage_Finance_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage Finance"},
    @{Name="ACL_Partage_Direction_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage Direction"},
    @{Name="ACL_Partage_R_D_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage R&D"},
    @{Name="ACL_Partage_Medical_RW"; Scope="DomainLocal"; Cat="Security"; Desc="RW partage Medical (DPI)"},
    # Fonctionnels
    @{Name="GRP_VPN_Users"; Scope="Global"; Cat="Security"; Desc="Utilisateurs VPN"},
    @{Name="GRP_RDP_Users"; Scope="Global"; Cat="Security"; Desc="Bureau a distance"},
    @{Name="GRP_PrintOperators"; Scope="Global"; Cat="Security"; Desc="Operateurs impression"},
    @{Name="GRP_Managers"; Scope="Global"; Cat="Security"; Desc="Managers tous departements"},
    @{Name="GRP_Wifi_Corp"; Scope="Global"; Cat="Security"; Desc="Wifi Entreprise"},
    @{Name="GRP_Wifi_Guest"; Scope="Global"; Cat="Security"; Desc="Wifi Invite"},
    @{Name="GRP_Azure_Sync"; Scope="Global"; Cat="Security"; Desc="Sync Azure AD"},
    @{Name="GRP_MFA_Exempt"; Scope="Global"; Cat="Security"; Desc="Exemption MFA"},
    @{Name="GRP_Local_Admins"; Scope="Global"; Cat="Security"; Desc="Admin locaux postes"},
    @{Name="GRP_LAPS_Read"; Scope="Global"; Cat="Security"; Desc="Lecture LAPS"},
    @{Name="GRP_Backup_Operators"; Scope="Global"; Cat="Security"; Desc="Operateurs sauvegarde"},
    @{Name="GRP_SCCM_Admins"; Scope="Global"; Cat="Security"; Desc="Admin SCCM/MECM"},
    @{Name="GRP_SQL_Admins"; Scope="Global"; Cat="Security"; Desc="Admin SQL Server"},
    @{Name="GRP_PKI_Admins"; Scope="Global"; Cat="Security"; Desc="Admin PKI/ADCS"},
    # Distribution
    @{Name="DL_Tous"; Scope="Global"; Cat="Distribution"; Desc="Diffusion globale"},
    @{Name="DL_IT"; Scope="Global"; Cat="Distribution"; Desc="Diffusion IT"},
    @{Name="DL_Direction"; Scope="Global"; Cat="Distribution"; Desc="Diffusion Direction"},
    @{Name="DL_Managers"; Scope="Global"; Cat="Distribution"; Desc="Diffusion Managers"},
    @{Name="DL_Partenaires"; Scope="Global"; Cat="Distribution"; Desc="Diffusion Partenaires"},
    @{Name="DL_Medical"; Scope="Global"; Cat="Distribution"; Desc="Diffusion equipe medicale"},
    # ================================================================
    # [ANOMALIE] Groupes vides / obsoletes / stale
    # ================================================================
    @{Name="GRP_Legacy_App"; Scope="Global"; Cat="Security"; Desc="Ancienne app - A SUPPRIMER"},
    @{Name="GRP_Projet_2019"; Scope="Global"; Cat="Security"; Desc="Projet termine 2019"},
    @{Name="GRP_Migration_Temp"; Scope="Global"; Cat="Security"; Desc="Migration temporaire 2020"},
    @{Name="GRP_Test_Prod"; Scope="Global"; Cat="Security"; Desc="Tests en production"},
    @{Name="GRP_Old_VPN"; Scope="Global"; Cat="Security"; Desc="Ancien VPN Cisco - remplace"},
    @{Name="GRP_Projet_Alpha"; Scope="Global"; Cat="Security"; Desc="Projet Alpha 2021 - termine"},
    @{Name="GRP_Projet_Beta"; Scope="Global"; Cat="Security"; Desc="Projet Beta 2022 - abandonne"},
    @{Name="GRP_Covid_Remote"; Scope="Global"; Cat="Security"; Desc="Acces COVID teletravail - A SUPPRIMER"},
    @{Name="GRP_Temp_Audit_2023"; Scope="Global"; Cat="Security"; Desc="Audit PwC 2023 - termine"},
    # [ANOMALIE] Noms generiques / ambigus
    @{Name="Admins"; Scope="Global"; Cat="Security"; Desc="Admins"},
    @{Name="Users2"; Scope="Global"; Cat="Security"; Desc="Users 2"},
    @{Name="temp"; Scope="Global"; Cat="Security"; Desc="temporaire"},
    @{Name="test"; Scope="Global"; Cat="Security"; Desc="test"},
    @{Name="ALL_ACCESS"; Scope="Global"; Cat="Security"; Desc="Acces total"},
    @{Name="GRP_Legacy_Services"; Scope="Global"; Cat="Security"; Desc="Services legacy politique faible"},
    # [ANOMALIE] Groupe avec description contenant des credentials
    @{Name="GRP_Wifi_IoT"; Scope="Global"; Cat="Security"; Desc="Wifi IoT - SSID: LabCorp-IoT / Key: W1f1-I0T-2024!"},
    @{Name="GRP_VPN_Emergency"; Scope="Global"; Cat="Security"; Desc="VPN urgence - shared secret: VpnEmergency#2024"}
)

foreach ($g in $groups) {
    try {
        New-ADGroup -Name $g.Name -Path $groupsPath -GroupScope $g.Scope -GroupCategory $g.Cat -Description $g.Desc -ErrorAction Stop
        Write-Host "  -> $($g.Name)" -ForegroundColor Green
    } catch { Write-Host "  -> $($g.Name) existe deja." -ForegroundColor Gray }
}

Write-Host "  -> $($groups.Count) groupes crees." -ForegroundColor Cyan
