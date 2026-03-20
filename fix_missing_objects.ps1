#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Cree les objets AD manquants detectes par les collecteurs
.DESCRIPTION
    Corrige les objets que 04m_Set-CollectorTargets.ps1 n'a pas cree correctement
.NOTES
    Executer sur l'HOTE en admin
#>
param(
    [string]$VMName  = 'DC01-LAB',
    [string]$Password = ''
)

if (-not $Password) {
    $configPath = Join-Path $PSScriptRoot 'config.ps1'
    if (Test-Path $configPath) { . $configPath; $Password = $LabPassword }
    else { Write-Host '[ERREUR] Mot de passe requis' -ForegroundColor Red; exit 1 }
}

$secPass = ConvertTo-SecureString $Password -AsPlainText -Force
$cred    = New-Object PSCredential('LAB\Administrator', $secPass)

Write-Host '=== Creation des objets AD manquants ===' -ForegroundColor Cyan

Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
    Import-Module ActiveDirectory
    $domain = Get-ADDomain
    $dn = $domain.DistinguishedName
    $domName = $domain.DNSRoot
    $weakPwd = ConvertTo-SecureString 'P@ssw0rd123!' -AsPlainText -Force

    # 1. MSOL_ account (Azure AD Connect sync — DCSync risk)
    Write-Host '[1] MSOL_ account...' -ForegroundColor Yellow
    $msol = Get-ADUser -Filter "SamAccountName -like 'MSOL_*'" -ErrorAction SilentlyContinue
    if (-not $msol) {
        $msolUser = New-ADUser -Name 'MSOL_ab1234567890' `
            -SamAccountName 'MSOL_ab1234567890' `
            -UserPrincipalName "MSOL_ab1234567890@$domName" `
            -Path "CN=Users,$dn" `
            -AccountPassword $weakPwd `
            -Enabled $true `
            -Description 'Azure AD Connect sync account' `
            -PasswordNeverExpires $true `
            -PassThru

        # Donner les droits DCSync
        $domainObj = "AD:\$dn"
        $msolSID = $msolUser.SID
        $repl1 = [GUID]'1131f6aa-9c07-11d1-f79f-00c04fc2dcd2'
        $repl2 = [GUID]'1131f6ad-9c07-11d1-f79f-00c04fc2dcd2'
        $acl = Get-Acl $domainObj
        $ace1 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($msolSID,'ExtendedRight','Allow',$repl1)
        $ace2 = New-Object System.DirectoryServices.ActiveDirectoryAccessRule($msolSID,'ExtendedRight','Allow',$repl2)
        $acl.AddAccessRule($ace1)
        $acl.AddAccessRule($ace2)
        Set-Acl $domainObj $acl
        Write-Host '  [OK] MSOL_ab1234567890 cree avec droits DCSync' -ForegroundColor Green
    } else {
        Write-Host '  [SKIP] MSOL_ existe deja' -ForegroundColor DarkGray
    }

    # 2. AZUREADSSOACC computer (Seamless SSO — Silver Ticket risk)
    Write-Host '[2] AZUREADSSOACC...' -ForegroundColor Yellow
    $sso = Get-ADComputer -Filter "Name -eq 'AZUREADSSOACC'" -ErrorAction SilentlyContinue
    if (-not $sso) {
        New-ADComputer -Name 'AZUREADSSOACC' `
            -SamAccountName 'AZUREADSSOACC$' `
            -Path "CN=Computers,$dn" `
            -Description 'Azure AD Seamless SSO - DO NOT DELETE' `
            -Enabled $true
        Write-Host '  [OK] AZUREADSSOACC cree (Silver Ticket risk)' -ForegroundColor Green
    } else {
        Write-Host '  [SKIP] AZUREADSSOACC existe deja' -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '[OK] Objets manquants crees' -ForegroundColor Green
}

pause
