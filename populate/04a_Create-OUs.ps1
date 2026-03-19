<#
.SYNOPSIS
    Cree la structure d'Unites Organisationnelles
    Anomalies: OU sans protection, objets dans le container Users par defaut
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[OUs] Creation des Unites Organisationnelles..." -ForegroundColor Yellow

$topOUs = @(
    @{Name="Entreprise"; Desc="Racine organisation"},
    @{Name="Serveurs"; Desc="Comptes machine serveurs"},
    @{Name="Postes"; Desc="Postes de travail"},
    @{Name="Groupes"; Desc="Groupes de securite et distribution"},
    @{Name="Services_Comptes"; Desc="Comptes de service"},
    @{Name="Quarantaine"; Desc="Comptes desactives"},
    @{Name="Staging"; Desc="Comptes temporaires en attente"},
    @{Name="Partenaires"; Desc="Comptes externes / prestataires"},
    @{Name="Admin_Tier0"; Desc="Comptes admin Tier 0"},
    @{Name="Admin_Tier1"; Desc="Comptes admin Tier 1"},
    @{Name="Admin_Tier2"; Desc="Comptes admin Tier 2"},
    @{Name="PAW"; Desc="Privileged Access Workstations"},
    @{Name="Disabled_Objects"; Desc="Objets a supprimer"}
)

foreach ($ou in $topOUs) {
    try {
        New-ADOrganizationalUnit -Name $ou.Name -Path $DomainDN -Description $ou.Desc -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        Write-Host "  -> OU '$($ou.Name)'" -ForegroundColor Green
    } catch { Write-Host "  -> OU '$($ou.Name)' existe deja." -ForegroundColor Gray }
}

$departments = @(
    @{Name="Direction"; Parent="Entreprise"},
    @{Name="IT"; Parent="Entreprise"},
    @{Name="Securite"; Parent="Entreprise"},
    @{Name="RH"; Parent="Entreprise"},
    @{Name="Finance"; Parent="Entreprise"},
    @{Name="Commercial"; Parent="Entreprise"},
    @{Name="R_et_D"; Parent="Entreprise"},
    @{Name="Juridique"; Parent="Entreprise"},
    @{Name="Support"; Parent="Entreprise"},
    @{Name="Communication"; Parent="Entreprise"},
    @{Name="Logistique"; Parent="Entreprise"},
    @{Name="Medical"; Parent="Entreprise"},
    @{Name="Helpdesk"; Parent="IT"},
    @{Name="Infrastructure"; Parent="IT"},
    @{Name="Developpement"; Parent="IT"},
    @{Name="DBA"; Parent="IT"},
    @{Name="SOC"; Parent="Securite"},
    @{Name="GRC"; Parent="Securite"},
    @{Name="Pentest"; Parent="Securite"}
)

foreach ($dept in $departments) {
    $parentPath = "OU=$($dept.Parent),$DomainDN"
    if ($dept.Parent -ne "Entreprise") {
        $parentPath = "OU=$($dept.Parent),OU=Entreprise,$DomainDN"
    }
    try {
        New-ADOrganizationalUnit -Name $dept.Name -Path $parentPath -ProtectedFromAccidentalDeletion $true -ErrorAction Stop
        Write-Host "  -> OU '$($dept.Name)' dans '$($dept.Parent)'" -ForegroundColor Green
    } catch { Write-Host "  -> OU '$($dept.Name)' existe deja." -ForegroundColor Gray }
}

# [ANOMALIE] OU sans protection suppression
foreach ($ouName in @("Temp_Projects","Old_Staging","Migration_2023","Archive_Comptes")) {
    try {
        New-ADOrganizationalUnit -Name $ouName -Path $DomainDN -Description "OU temporaire" -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        Write-Host "  -> [VULN] OU '$ouName' SANS protection suppression" -ForegroundColor Red
    } catch { Write-Host "  -> OU '$ouName' existe deja." -ForegroundColor Gray }
}

# [ANOMALIE] OU vide (jamais utilisee = manque de nettoyage)
foreach ($ouName in @("Projet_Alpha_2021","Interns_Summer_2022","Temp_Migration")) {
    try {
        New-ADOrganizationalUnit -Name $ouName -Path "OU=Quarantaine,$DomainDN" -Description "Ancien projet" -ProtectedFromAccidentalDeletion $false -ErrorAction Stop
        Write-Host "  -> [STALE OU] '$ouName' vide dans Quarantaine" -ForegroundColor Red
    } catch { Write-Host "  -> OU '$ouName' existe deja." -ForegroundColor Gray }
}

# [ANOMALIE] Pas de redirection du container Users par defaut
# (Les nouveaux objets tombent dans CN=Users au lieu d'une OU - detectable par PingCastle)
Write-Host "  -> [INFO] Container 'CN=Users' par defaut NON redirige (anomalie PingCastle)" -ForegroundColor Yellow

$total = $topOUs.Count + $departments.Count + 7
Write-Host "  -> $total OUs creees." -ForegroundColor Cyan
