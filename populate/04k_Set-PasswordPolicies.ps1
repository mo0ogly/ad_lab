<#
.SYNOPSIS
    Fine-Grained Password Policies
    Anomalies: politique faible pour services/legacy, reversible encryption,
    PSO VPN tres faible, PSO partenaires sans lockout, PSO avec MD4/LM hash
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[PSO] Politiques Fine-Grained Password..." -ForegroundColor Yellow

# ================================================================
# PSO NORMALES (bonnes pratiques)
# ================================================================

# Admin stricte (Tier0)
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_Admin_Strict" -Precedence 10 -MinPasswordLength 16 `
        -PasswordHistoryCount 48 -MaxPasswordAge (New-TimeSpan -Days 60) -MinPasswordAge (New-TimeSpan -Days 1) `
        -ComplexityEnabled $true -LockoutThreshold 3 -LockoutDuration (New-TimeSpan -Minutes 60) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 60) -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_Admin_Strict" -Subjects "GRP_IT_Admins"
    Write-Host "  -> PSO_Admin_Strict: 16 chars, lockout 3, rotation 60j" -ForegroundColor Green
} catch { Write-Host "  -> PSO_Admin_Strict existe deja." -ForegroundColor Gray }

# Standard utilisateurs
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_Users_Standard" -Precedence 20 -MinPasswordLength 12 `
        -PasswordHistoryCount 24 -MaxPasswordAge (New-TimeSpan -Days 90) -MinPasswordAge (New-TimeSpan -Days 1) `
        -ComplexityEnabled $true -LockoutThreshold 5 -LockoutDuration (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 30) -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_Users_Standard" -Subjects "Domain Users"
    Write-Host "  -> PSO_Users_Standard: 12 chars, lockout 5, rotation 90j" -ForegroundColor Green
} catch { Write-Host "  -> PSO_Users_Standard existe deja." -ForegroundColor Gray }

# ================================================================
# PSO VULNERABLES
# ================================================================
Write-Host "`n  --- PSO VULNERABLES ---" -ForegroundColor Red

# [WEAK PSO pour services legacy - 4 chars, pas de complexite, pas de lockout]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_Service_Legacy_WEAK" -Precedence 50 -MinPasswordLength 4 `
        -PasswordHistoryCount 0 -MaxPasswordAge (New-TimeSpan -Days 0) -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $false -LockoutThreshold 0 -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_Service_Legacy_WEAK" -Subjects "GRP_Legacy_Services"
    Write-Host "  -> [WEAK PSO] Legacy: 4 chars, no complexity, no lockout, no expiry" -ForegroundColor Red
} catch { Write-Host "  -> PSO_Service_Legacy_WEAK existe deja." -ForegroundColor Gray }

# [REVERSIBLE PSO - chiffrement reversible pour RADIUS/WiFi]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_Reversible_Enc" -Precedence 30 -MinPasswordLength 8 `
        -PasswordHistoryCount 12 -MaxPasswordAge (New-TimeSpan -Days 365) -ComplexityEnabled $true `
        -LockoutThreshold 10 -LockoutDuration (New-TimeSpan -Minutes 15) `
        -LockoutObservationWindow (New-TimeSpan -Minutes 15) -ReversibleEncryptionEnabled $true -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_Reversible_Enc" -Subjects "GRP_Wifi_Corp"
    Write-Host "  -> [REVERSIBLE PSO] Wifi_Corp: chiffrement reversible + 365j expiry" -ForegroundColor Red
} catch { Write-Host "  -> PSO_Reversible_Enc existe deja." -ForegroundColor Gray }

# [PSO VPN ultra faible - pour acces VPN legacy]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_VPN_Legacy_WEAK" -Precedence 40 -MinPasswordLength 6 `
        -PasswordHistoryCount 3 -MaxPasswordAge (New-TimeSpan -Days 0) -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $false -LockoutThreshold 0 -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_VPN_Legacy_WEAK" -Subjects "GRP_VPN_Users"
    Write-Host "  -> [WEAK PSO] VPN: 6 chars, no complexity, no lockout, no expiry" -ForegroundColor Red
    Write-Host "         -> Precedence 40 > 20 donc override la politique standard pour VPN users!" -ForegroundColor Red
} catch { Write-Host "  -> PSO_VPN_Legacy_WEAK existe deja." -ForegroundColor Gray }

# [PSO Partenaires sans lockout - brute-force possible]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_Partners_NoLockout" -Precedence 45 -MinPasswordLength 8 `
        -PasswordHistoryCount 6 -MaxPasswordAge (New-TimeSpan -Days 180) -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $true -LockoutThreshold 0 -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_Partners_NoLockout" -Subjects "DL_Partenaires"
    Write-Host "  -> [NO LOCKOUT PSO] Partenaires: complexite OK mais AUCUN lockout!" -ForegroundColor Red
} catch { Write-Host "  -> PSO_Partners_NoLockout existe deja." -ForegroundColor Gray }

# [PSO avec LM Hash stocke - Store LM hash (LM compat)]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_LM_Hash_Compat" -Precedence 55 -MinPasswordLength 1 `
        -PasswordHistoryCount 0 -MaxPasswordAge (New-TimeSpan -Days 0) -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $false -LockoutThreshold 0 -ReversibleEncryptionEnabled $true -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_LM_Hash_Compat" -Subjects "GRP_Legacy_App"
    Write-Host "  -> [LM HASH PSO] Legacy_App: 1 char min, reversible, no lockout, no expiry!" -ForegroundColor Red
    Write-Host "         -> C'est la pire politique possible." -ForegroundColor Red
} catch { Write-Host "  -> PSO_LM_Hash_Compat existe deja." -ForegroundColor Gray }

# [PSO MFA_Exempt trop permissive]
try {
    New-ADFineGrainedPasswordPolicy -Name "PSO_MFA_Exempt" -Precedence 35 -MinPasswordLength 8 `
        -PasswordHistoryCount 6 -MaxPasswordAge (New-TimeSpan -Days 0) -MinPasswordAge (New-TimeSpan -Days 0) `
        -ComplexityEnabled $false -LockoutThreshold 50 `
        -LockoutDuration (New-TimeSpan -Minutes 1) -LockoutObservationWindow (New-TimeSpan -Minutes 1) `
        -ReversibleEncryptionEnabled $false -ErrorAction Stop
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO_MFA_Exempt" -Subjects "GRP_MFA_Exempt"
    Write-Host "  -> [WEAK PSO] MFA_Exempt: 8 chars, no complexity, lockout 50 (1min), no expiry" -ForegroundColor Red
    Write-Host "         -> Exempts MFA ET politique mdp faible = double risque" -ForegroundColor Red
} catch { Write-Host "  -> PSO_MFA_Exempt existe deja." -ForegroundColor Gray }

# ================================================================
# LM HASH STORAGE au niveau domaine
# ================================================================
try {
    # Autoriser le stockage de LM hash (NoLMHash=0 = LM hash stores)
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "NoLMHash" -Value 0
    Write-Host "  -> [LM HASH STORAGE] LM hash stockes pour les nouveaux mots de passe!" -ForegroundColor Red
} catch {}

Write-Host "`n  -> Politiques de mot de passe configurees." -ForegroundColor Cyan
