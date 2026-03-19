#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Peuple l'AD avec structure entreprise + 40+ anomalies de securite
.DESCRIPTION
    Script orchestrateur qui appelle les sous-scripts dans populate/
    Chaque sous-script peut aussi etre lance independamment.

    Anomalies detectables par: PingCastle, ANSSI, BloodHound, LiaScan
    Ce lab est VOLONTAIREMENT VULNERABLE - NE PAS utiliser en production
.NOTES
    Executer apres 02_Install-ADDS.ps1 et 03_Install-Services.ps1
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$DefaultPassword = "",
    [string]$WeakPassword = "Password1"
)

# Charger config si pas de mot de passe fourni
if (-not $DefaultPassword) {
    $configPath = Join-Path $PSScriptRoot "config.ps1"
    if (Test-Path $configPath) { . $configPath; $DefaultPassword = $LabPassword }
    else { Write-Host "[ERREUR] Mot de passe requis. Copiez config.example.ps1 en config.ps1" -ForegroundColor Red; exit 1 }
}

$ErrorActionPreference = "Continue"
Import-Module ActiveDirectory
Import-Module GroupPolicy -ErrorAction SilentlyContinue

Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  LAB AD - Population AD + Anomalies Securite" -ForegroundColor Cyan
Write-Host "  PingCastle / ANSSI / BloodHound / LiaScan" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

# Determiner le chemin des sous-scripts
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$populateDir = Join-Path $scriptDir "populate"

if (-not (Test-Path $populateDir)) {
    Write-Host "ERREUR: Dossier 'populate/' introuvable dans $scriptDir" -ForegroundColor Red
    Write-Host "Les sous-scripts doivent etre dans: $populateDir" -ForegroundColor Yellow
    exit 1
}

# Parametres communs
$params = @{
    DomainDN = $DomainDN
    DomainName = $DomainName
    DefaultPassword = $DefaultPassword
    WeakPassword = $WeakPassword
}

$steps = @(
    @{File="04a_Create-OUs.ps1";             Desc="Structure OUs";                    Params=@{DomainDN=$DomainDN}},
    @{File="04b_Create-Groups.ps1";          Desc="Groupes securite/distribution";    Params=@{DomainDN=$DomainDN}},
    @{File="04c_Create-Users.ps1";           Desc="Utilisateurs (80+)";               Params=$params},
    @{File="04d_Create-Services.ps1";        Desc="Comptes de service + vulns";       Params=$params},
    @{File="04e_Create-Admins.ps1";          Desc="Comptes admin + vulns";            Params=$params},
    @{File="04f_Create-Partners.ps1";        Desc="Partenaires + generiques";         Params=@{DomainDN=$DomainDN; DomainName=$DomainName; WeakPassword=$WeakPassword}},
    @{File="04g_Create-Computers.ps1";       Desc="Objets ordinateur";                Params=@{DomainDN=$DomainDN}},
    @{File="04h_Set-ACLs.ps1";              Desc="ACLs dangereuses + nested groups";  Params=@{DomainDN=$DomainDN}},
    @{File="04i_Set-GPOs.ps1";              Desc="GPOs normales + vulnerables";       Params=@{DomainDN=$DomainDN; DomainName=$DomainName}},
    @{File="04j_Set-DomainConfig.ps1";      Desc="Config domaine dangereuses";        Params=@{DomainDN=$DomainDN; DomainName=$DomainName; WeakPassword=$WeakPassword}},
    @{File="04k_Set-PasswordPolicies.ps1";  Desc="Fine-Grained Password Policies";   Params=@{DomainDN=$DomainDN}},
    @{File="04l_Set-ADCS-Vulns.ps1";        Desc="Vulnerabilites ADCS";              Params=@{DomainDN=$DomainDN}},
    @{File="04m_Set-CollectorTargets.ps1";   Desc="Objets pour collecteurs LIA-Scan"; Params=@{DomainDN=$DomainDN; DomainName=$DomainName; WeakPassword=$WeakPassword}}
)

$total = $steps.Count
$current = 0

foreach ($step in $steps) {
    $current++
    $scriptPath = Join-Path $populateDir $step.File

    if (Test-Path $scriptPath) {
        Write-Host "`n========== [$current/$total] $($step.Desc) ==========" -ForegroundColor Cyan
        try {
            $splatParams = $step.Params
            & $scriptPath @splatParams
        } catch {
            Write-Host "  ERREUR dans $($step.File): $_" -ForegroundColor Red
        }
    } else {
        Write-Host "`n[$current/$total] SKIP: $($step.File) introuvable" -ForegroundColor Red
    }
}

# --- RESUME ---
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Active Directory peuple avec succes!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  85+ ANOMALIES INJECTEES:" -ForegroundColor Red
Write-Host "  [Kerberos/Auth]" -ForegroundColor Magenta
Write-Host "    Kerberoasting (8 SPNs), AS-REP Roast, DES/RC4 only" -ForegroundColor Yellow
Write-Host "    NTLMv1, WDigest, LM Hash storage, Credential caching" -ForegroundColor Yellow
Write-Host "  [ACLs/Delegation]" -ForegroundColor Magenta
Write-Host "    DCSync, WriteDACL, GenericAll, GenericWrite, WriteOwner" -ForegroundColor Yellow
Write-Host "    ResetPwd, AddMember, WriteSPN, AdminSDHolder" -ForegroundColor Yellow
Write-Host "    Unconstrained/Constrained/RBCD Delegation" -ForegroundColor Yellow
Write-Host "  [Groupes/Cascade]" -ForegroundColor Magenta
Write-Host "    7 chaines de propagation via nested groups (BloodHound)" -ForegroundColor Yellow
Write-Host "    Circular groups, Distribution->Security, Stale groups" -ForegroundColor Yellow
Write-Host "  [Comptes]" -ForegroundColor Magenta
Write-Host "    12+ DA (trop), Ex-employes, Disabled in DA, Presta in DA" -ForegroundColor Yellow
Write-Host "    Admin kerberoastable, Pwd in description, No separation" -ForegroundColor Yellow
Write-Host "    Generic accounts, Inactive users, Wrong OU" -ForegroundColor Yellow
Write-Host "  [GPOs]" -ForegroundColor Magenta
Write-Host "    LLMNR, WPAD, Firewall OFF, AlwaysInstallElevated" -ForegroundColor Yellow
Write-Host "    LSA not PPL, Credential Guard OFF, RDP sans NLA" -ForegroundColor Yellow
Write-Host "    PS logging OFF, Defender OFF, UAC OFF, Autorun" -ForegroundColor Yellow
Write-Host "  [Reseau/DNS]" -ForegroundColor Magenta
Write-Host "    DNS zone transfer Any, DNS dynamic update nonsecure" -ForegroundColor Yellow
Write-Host "    WPAD DNS, DnsAdmins abuse, GQBL vide, SMBv1" -ForegroundColor Yellow
Write-Host "    Null sessions, SMB Signing OFF, NetBIOS ON" -ForegroundColor Yellow
Write-Host "  [PKI/ADCS]" -ForegroundColor Magenta
Write-Host "    ESC1 (x2), ESC2, ESC3, ESC4, ESC6, ESC8" -ForegroundColor Yellow
Write-Host "    Exportable keys, Long validity, CA permissions" -ForegroundColor Yellow
Write-Host "  [Chiffrement]" -ForegroundColor Magenta
Write-Host "    TLS 1.0/1.1, SSL 3.0, MD5, SHA1, RC4/3DES/NULL ciphers" -ForegroundColor Yellow
Write-Host "  [Config domaine]" -ForegroundColor Magenta
Write-Host "    LDAP signing OFF, PrintNightmare, Guest ON" -ForegroundColor Yellow
Write-Host "    MachineAccountQuota=10, RODC misconfig, Tombstone court" -ForegroundColor Yellow
Write-Host "    AD Recycle Bin OFF, Protected Users vide" -ForegroundColor Yellow
Write-Host "  [Password Policies]" -ForegroundColor Magenta
Write-Host "    7 PSOs dont 5 vulns (1 char min, reversible, no lockout)" -ForegroundColor Yellow
Write-Host "    LM Hash storage active" -ForegroundColor Yellow
Write-Host "  [Collector Targets (04m)]" -ForegroundColor Magenta
Write-Host "    AADConnect: MSOL_* DCSync + AZUREADSSOACC Silver Ticket" -ForegroundColor Yellow
Write-Host "    dSHeuristics: anonymous NSPI + SDProp exclusions" -ForegroundColor Yellow
Write-Host "    gMSA: 2 comptes avec GenericAll/WriteDACL non-admin" -ForegroundColor Yellow
Write-Host "    GPP Passwords: cpassword dans Groups.xml + ScheduledTasks.xml" -ForegroundColor Yellow
Write-Host "    GPO UserRights: SeDebug/SeLoadDriver a Authenticated Users" -ForegroundColor Yellow
Write-Host "    GPO Audit: owner non-standard + GenericAll" -ForegroundColor Yellow
Write-Host "    SID History: 2 comptes avec sIDHistory cross-domain" -ForegroundColor Yellow
Write-Host "    DisplaySpecifier: adminContextMenu UNC backdoor" -ForegroundColor Yellow
Write-Host "    DC Ownership: owner != DA/EA" -ForegroundColor Yellow
Write-Host "    SYSVOL: Modify pour Domain Users, Write pour Auth Users" -ForegroundColor Yellow
Write-Host "    Protected Users: membres avec delegation (conflit)" -ForegroundColor Yellow
Write-Host "    DHCP Admins: groupe peuple (DNS poisoning)" -ForegroundColor Yellow
Write-Host "    ADFS DKM: GenericRead pour Domain Users (Golden SAML)" -ForegroundColor Yellow
Write-Host "    Privileged PasswordNotRequired: admin.backup (DA)" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Credentials:" -ForegroundColor Yellow
Write-Host "    Users     : $DefaultPassword"
Write-Host "    Admins    : Adm1n!$DefaultPassword"
Write-Host "    Faibles   : $WeakPassword"
Write-Host ""
Write-Host "  Pret pour PingCastle / BloodHound / LiaScan!" -ForegroundColor Green

Read-Host "`nAppuyez sur Entree pour terminer"
