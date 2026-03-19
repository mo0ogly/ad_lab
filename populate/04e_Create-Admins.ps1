<#
.SYNOPSIS
    Cree les comptes admin (legit + vulnerables)
    Anomalies: trop de DA, ex-employes, comptes desactives dans DA,
    admin kerberoastable, password dans description, SPN sur admin,
    admin sans separation, password faible, admin inactif
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$DefaultPassword = "",
    [string]$WeakPassword = "Password1"
)

# Charger config si pas de mot de passe fourni
if (-not $DefaultPassword) {
    $configPath = Join-Path $PSScriptRoot "..\config.ps1"
    if (Test-Path $configPath) { . $configPath; $DefaultPassword = $LabPassword }
    else { Write-Host "[ERREUR] Mot de passe requis. Copiez config.example.ps1 en config.ps1" -ForegroundColor Red; exit 1 }
}

Write-Host "`n[ADMINS] Comptes admin..." -ForegroundColor Yellow

$adminPass = ConvertTo-SecureString "Adm1n!$DefaultPassword" -AsPlainText -Force
$weakPass = ConvertTo-SecureString $WeakPassword -AsPlainText -Force

# --- Admins legit ---
foreach ($adm in @(
    @{Name="adm.thomas.laurent"; Display="ADM - Thomas Laurent"; Groups=@("Domain Admins","GRP_IT_Admins")},
    @{Name="adm.catherine.morel"; Display="ADM - Catherine Morel"; Groups=@("Domain Admins","Enterprise Admins","Schema Admins","GRP_IT_Admins")},
    @{Name="adm.antoine.mercier"; Display="ADM - Antoine Mercier"; Groups=@("Domain Admins","GRP_IT_Admins","GRP_SOC")}
)) {
    try {
        New-ADUser -Name $adm.Display -SamAccountName $adm.Name -UserPrincipalName "$($adm.Name)@$DomainName" `
            -Description "Compte administrateur" -Path "OU=Admin_Tier0,$DomainDN" `
            -AccountPassword $adminPass -PasswordNeverExpires $false -Enabled $true -ErrorAction Stop
        foreach ($grp in $adm.Groups) { Add-ADGroupMember -Identity $grp -Members $adm.Name -ErrorAction SilentlyContinue }
        Write-Host "  -> $($adm.Name)" -ForegroundColor Green
    } catch { Write-Host "  -> $($adm.Name) existe deja." -ForegroundColor Gray }
}

# ================================================================
# COMPTES ADMIN VULNERABLES
# ================================================================
Write-Host "`n  --- Comptes admin VULNERABLES ---" -ForegroundColor Red

# [TROP DE DA avec mdp faible]
foreach ($name in @("adm.nicolas.bernard","adm.julien.moreau","admin.backup","admin.test","admin.dev")) {
    try {
        New-ADUser -Name "ADM $name" -SamAccountName $name -UserPrincipalName "$name@$DomainName" `
            -Description "Admin supplementaire" -Path "OU=Admin_Tier0,$DomainDN" `
            -AccountPassword $weakPass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
        Add-ADGroupMember -Identity "Domain Admins" -Members $name
        Write-Host "  -> [TOO MANY DA] $name (mdp faible)" -ForegroundColor Red
    } catch { Write-Host "  -> $name existe deja." -ForegroundColor Gray }
}

# [PAS DE SEPARATION user/admin - user standard dans DA]
try {
    Add-ADGroupMember -Identity "Domain Admins" -Members "thomas.laurent" -ErrorAction Stop
    Write-Host "  -> [NO SEPARATION] thomas.laurent (user std) dans DA!" -ForegroundColor Red
} catch { Write-Host "  -> thomas.laurent deja dans DA." -ForegroundColor Gray }

# [ADMIN KERBEROASTABLE - SPN sur un compte DA]
try {
    New-ADUser -Name "ADM - Legacy SysAdmin" -SamAccountName "adm.legacy.sysadmin" -UserPrincipalName "adm.legacy.sysadmin@$DomainName" `
        -Description "Ancien admin systeme - SPN configure" -Path "OU=Admin_Tier0,$DomainDN" `
        -AccountPassword $weakPass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.legacy.sysadmin"
    Set-ADUser -Identity "adm.legacy.sysadmin" -ServicePrincipalNames @{Add="HTTP/admin-portal.lab.local"}
    Write-Host "  -> [ADMIN KERBEROAST] adm.legacy.sysadmin dans DA avec SPN! (kerberoastable DA)" -ForegroundColor Red
} catch { Write-Host "  -> adm.legacy.sysadmin existe deja." -ForegroundColor Gray }

# [PASSWORD DANS DESCRIPTION - admin]
try {
    New-ADUser -Name "ADM - Ancien DBA" -SamAccountName "adm.old.dba" -UserPrincipalName "adm.old.dba@$DomainName" `
        -Description "Admin DBA - mdp temporaire: DbaAdm1n!2023 - voir ticket INC-2845" -Path "OU=Admin_Tier0,$DomainDN" `
        -AccountPassword (ConvertTo-SecureString "DbaAdm1n!2023" -AsPlainText -Force) -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.old.dba"
    Write-Host "  -> [PWD IN DESC] adm.old.dba DA avec mot de passe dans la description!" -ForegroundColor Red
} catch { Write-Host "  -> adm.old.dba existe deja." -ForegroundColor Gray }

# [EX-EMPLOYE ADMIN ACTIF]
try {
    New-ADUser -Name "ADM - Ex-DSI Martin" -SamAccountName "adm.ex.dsi.martin" -UserPrincipalName "adm.ex.dsi.martin@$DomainName" `
        -Description "Ancien DSI - parti mars 2023 - COMPTE TOUJOURS ACTIF" -Path "OU=Admin_Tier0,$DomainDN" `
        -AccountPassword (ConvertTo-SecureString $DefaultPassword -AsPlainText -Force) -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.ex.dsi.martin"
    Add-ADGroupMember -Identity "Enterprise Admins" -Members "adm.ex.dsi.martin"
    Write-Host "  -> [INACTIVE ADMIN] adm.ex.dsi.martin ex-DSI dans DA + EA!" -ForegroundColor Red
} catch { Write-Host "  -> adm.ex.dsi.martin existe deja." -ForegroundColor Gray }

# [EX-PRESTA ADMIN]
try {
    New-ADUser -Name "ADM - Ex Presta Sopra" -SamAccountName "adm.presta.sopra" -UserPrincipalName "adm.presta.sopra@$DomainName" `
        -Description "Prestataire Sopra - mission terminee 06/2022" -Path "OU=Admin_Tier0,$DomainDN" `
        -AccountPassword $weakPass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.presta.sopra"
    Write-Host "  -> [EX-PRESTA DA] adm.presta.sopra prestataire dans DA (mission terminee)" -ForegroundColor Red
} catch { Write-Host "  -> adm.presta.sopra existe deja." -ForegroundColor Gray }

# [DESACTIVE MAIS DANS DA]
try {
    New-ADUser -Name "ADM - Ancien Admin Reseau" -SamAccountName "adm.old.network" -UserPrincipalName "adm.old.network@$DomainName" `
        -Description "Ancien admin" -Path "OU=Quarantaine,$DomainDN" `
        -AccountPassword (ConvertTo-SecureString $DefaultPassword -AsPlainText -Force) -Enabled $false -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.old.network"
    Write-Host "  -> [DISABLED IN DA] adm.old.network desactive mais dans DA" -ForegroundColor Red
} catch { Write-Host "  -> adm.old.network existe deja." -ForegroundColor Gray }

# [ADMIN DANS MAUVAISE OU - pas dans Tier0]
try {
    New-ADUser -Name "ADM - Quick Fix Admin" -SamAccountName "adm.quickfix" -UserPrincipalName "adm.quickfix@$DomainName" `
        -Description "Cree en urgence pour incident" -Path "CN=Users,$DomainDN" `
        -AccountPassword $weakPass -PasswordNeverExpires $true -Enabled $true -ErrorAction Stop
    Add-ADGroupMember -Identity "Domain Admins" -Members "adm.quickfix"
    Write-Host "  -> [WRONG OU] adm.quickfix DA dans CN=Users (pas dans OU admin!)" -ForegroundColor Red
} catch { Write-Host "  -> adm.quickfix existe deja." -ForegroundColor Gray }

# [ADMIN AVEC AS-REP ROASTING]
try {
    Set-ADAccountControl -Identity "adm.nicolas.bernard" -DoesNotRequirePreAuth $true -ErrorAction Stop
    Write-Host "  -> [ADMIN AS-REP] adm.nicolas.bernard DA sans pre-auth!" -ForegroundColor Red
} catch {}

# [ADMIN AVEC REVERSIBLE ENCRYPTION]
try {
    Set-ADUser -Identity "admin.test" -AllowReversiblePasswordEncryption $true -ErrorAction Stop
    Write-Host "  -> [ADMIN REVERSIBLE] admin.test chiffrement reversible" -ForegroundColor Red
} catch {}

# [ADMIN AVEC DES ENCRYPTION seulement]
try {
    Set-ADUser -Identity "admin.backup" -KerberosEncryptionType DES -ErrorAction Stop
    Write-Host "  -> [ADMIN DES] admin.backup Kerberos DES uniquement" -ForegroundColor Red
} catch {}

# [Protected Users VIDE - aucun admin protege]
try {
    $protectedMembers = Get-ADGroupMember "Protected Users" -ErrorAction SilentlyContinue
    if (-not $protectedMembers -or $protectedMembers.Count -eq 0) {
        Write-Host "  -> [PROTECTED USERS] VIDE - aucun admin dans Protected Users!" -ForegroundColor Red
    }
} catch {}

# [ADMIN count report]
try {
    $daCount = (Get-ADGroupMember "Domain Admins" | Measure-Object).Count
    Write-Host "  -> [AUDIT] $daCount comptes dans Domain Admins (recommande: < 5)" -ForegroundColor Yellow
    $eaCount = (Get-ADGroupMember "Enterprise Admins" | Measure-Object).Count
    Write-Host "  -> [AUDIT] $eaCount comptes dans Enterprise Admins (recommande: 0-1)" -ForegroundColor Yellow
    $saCount = (Get-ADGroupMember "Schema Admins" | Measure-Object).Count
    Write-Host "  -> [AUDIT] $saCount comptes dans Schema Admins (recommande: 0)" -ForegroundColor Yellow
} catch {}

Write-Host "`n  -> Comptes admin configures." -ForegroundColor Cyan
