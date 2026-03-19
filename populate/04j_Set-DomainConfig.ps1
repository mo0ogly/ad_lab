<#
.SYNOPSIS
    Configurations domaine dangereuses
    Anomalies: LDAP signing off, SMBv1, null sessions, PrintNightmare, Guest, MachineAccountQuota,
    DNS zone transfer, DNS Admins abuse, Kerberos faible (DES/RC4), recycle bin off,
    chiffrement MD5/SHA1, RODC misconfig, NetBIOS over TCP, WINS
#>

param(
    [string]$DomainDN = "DC=lab,DC=local",
    [string]$DomainName = "lab.local",
    [string]$WeakPassword = "Password1"
)

Write-Host "`n[DOMAIN CONFIG] Configurations domaine vulnerables..." -ForegroundColor Yellow

# ================================================================
# COMPTES & QUOTAS
# ================================================================

# [MachineAccountQuota = 10] - Permet a tout user de joindre 10 machines
try { Set-ADDomain -Identity $DomainName -Replace @{"ms-DS-MachineAccountQuota"=10}; Write-Host "  -> [MACHINE QUOTA] = 10 (devrait etre 0)" -ForegroundColor Red } catch {}

# [Guest actif avec mdp faible]
try { Enable-ADAccount -Identity "Guest"; Set-ADAccountPassword -Identity "Guest" -NewPassword (ConvertTo-SecureString $WeakPassword -AsPlainText -Force) -Reset; Write-Host "  -> [GUEST ON] Compte Guest active mdp=$WeakPassword" -ForegroundColor Red } catch {}

# [Protected Users vide] - Aucun admin dans Protected Users = pas de protection Kerberos avancee
try {
    $protectedCount = (Get-ADGroupMember "Protected Users" -ErrorAction SilentlyContinue | Measure-Object).Count
    if ($protectedCount -eq 0) { Write-Host "  -> [PROTECTED USERS VIDE] Aucun compte dans Protected Users!" -ForegroundColor Red }
} catch {}

# [AD Recycle Bin non active] - PingCastle check
try {
    $recycleBin = Get-ADOptionalFeature -Filter {Name -eq "Recycle Bin Feature"} -ErrorAction SilentlyContinue
    if ($recycleBin -and -not $recycleBin.EnabledScopes) {
        Write-Host "  -> [RECYCLE BIN OFF] AD Recycle Bin non active" -ForegroundColor Red
    }
} catch {}

# ================================================================
# LDAP
# ================================================================

# [LDAP signing OFF]
try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LDAPServerIntegrity" -Value 0; Write-Host "  -> [LDAP SIGNING OFF] Signing non requis" -ForegroundColor Red } catch {}

# [LDAP channel binding OFF]
try { Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\NTDS\Parameters" -Name "LdapEnforceChannelBinding" -Value 0; Write-Host "  -> [LDAP CHANNEL BINDING OFF]" -ForegroundColor Red } catch {}

# [LDAPS non configure / pas de certificat LDAPS]
Write-Host "  -> [LDAPS] LDAP sur port 389 sans TLS (636 non force)" -ForegroundColor Red

# ================================================================
# SMB
# ================================================================

# [SMBv1 active - EternalBlue/WannaCry]
try { Set-SmbServerConfiguration -EnableSMB1Protocol $true -Force; Write-Host "  -> [SMBv1 ON] EternalBlue/WannaCry" -ForegroundColor Red } catch {}

# ================================================================
# PRINT / SPOOLER
# ================================================================

# [Print Spooler sur DC - PrintNightmare CVE-2021-34527]
try { Set-Service -Name "Spooler" -StartupType Automatic; Start-Service -Name "Spooler"; Write-Host "  -> [PRINTNIGHTMARE] Spooler actif sur DC" -ForegroundColor Red } catch {}

# ================================================================
# NULL SESSIONS & ACCES ANONYME
# ================================================================
try {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymous" -Value 0
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa" -Name "RestrictAnonymousSAM" -Value 0
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "RestrictNullSessAccess" -Value 0
    Write-Host "  -> [NULL SESSION] Acces anonyme LDAP/SAM autorise" -ForegroundColor Red
} catch {}

# [Enum anonyme des partages]
try {
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters" -Name "NullSessionShares" -PropertyType MultiString -Value @("Partage_Commun","IPC$") -Force | Out-Null
    Write-Host "  -> [NULL SHARE] Partages accessibles anonymement" -ForegroundColor Red
} catch {}

# ================================================================
# KERBEROS - CHIFFREMENT FAIBLE
# ================================================================

# [DES active pour Kerberos] - ANSSI recommande de desactiver DES
try {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Name "SupportedEncryptionTypes" -Value 0x7FFFFFFF -Force -ErrorAction SilentlyContinue
    # Creer la cle si elle n'existe pas
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos" -Force -ErrorAction SilentlyContinue | Out-Null
    New-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Kerberos\Parameters" -Name "SupportedEncryptionTypes" -Value 0x7FFFFFFF
    Write-Host "  -> [KERBEROS DES+RC4] Tous les types de chiffrement acceptes (DES, RC4, AES)" -ForegroundColor Red
} catch {}

# [Comptes avec DES-only Kerberos]
try {
    Set-ADUser -Identity "svc_sql_legacy" -KerberosEncryptionType DES -ErrorAction Stop
    Write-Host "  -> [DES ONLY] svc_sql_legacy Kerberos DES uniquement" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DES svc_sql_legacy: $_" -ForegroundColor Gray }

try {
    Set-ADUser -Identity "svc_old_erp" -KerberosEncryptionType DES -ErrorAction Stop
    Write-Host "  -> [DES ONLY] svc_old_erp Kerberos DES uniquement" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DES svc_old_erp: $_" -ForegroundColor Gray }

# [RC4 seul pour certains comptes - pas AES]
try {
    Set-ADUser -Identity "svc_http_intra" -KerberosEncryptionType RC4 -ErrorAction Stop
    Write-Host "  -> [RC4 ONLY] svc_http_intra Kerberos RC4 uniquement (pas AES)" -ForegroundColor Red
} catch {}
try {
    Set-ADUser -Identity "svc_cifs_backup" -KerberosEncryptionType RC4 -ErrorAction Stop
    Write-Host "  -> [RC4 ONLY] svc_cifs_backup Kerberos RC4 uniquement" -ForegroundColor Red
} catch {}

# [krbtgt password age] - Le password krbtgt n'a probablement jamais ete change
Write-Host "  -> [KRBTGT] Password krbtgt non-rotate (date creation domaine)" -ForegroundColor Red

# ================================================================
# DNS VULNERABILITES
# ================================================================

# [DNS Zone Transfer vers Any] - Permet enum complete de la zone
try {
    $zoneName = $DomainName
    dnscmd /config $zoneName /allowtransfer 0 2>$null  # 0 = To any server
    Set-DnsServerZoneTransferPolicy -Name $zoneName -SecondaryServers "0.0.0.0/0" -ErrorAction SilentlyContinue
    # Alternative: via registre
    dnscmd /zoneresetsecondaries $zoneName /nonsecure 2>$null
    Write-Host "  -> [DNS ZONE TRANSFER] Transfert de zone autorise vers Any" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DNS zone transfer: $_" -ForegroundColor Gray }

# [DNS Dynamic Update non secure] - Permet injection d'enregistrements DNS
try {
    Set-DnsServerPrimaryZone -Name $DomainName -DynamicUpdate "NonsecureAndSecure" -ErrorAction SilentlyContinue
    Write-Host "  -> [DNS DYNAMIC UPDATE] Updates non-secure acceptees" -ForegroundColor Red
} catch { Write-Host "  -> Erreur DNS dynamic update: $_" -ForegroundColor Gray }

# [DNS Socket Pool petit] - Facilite DNS cache poisoning
try {
    Set-DnsServerSetting -SocketPoolSize 256 -ErrorAction SilentlyContinue
    Write-Host "  -> [DNS SOCKET POOL] = 256 (devrait etre 10000+)" -ForegroundColor Yellow
} catch {}

# [DNS Admin group abuse] - Ajouter un user IT dans DnsAdmins (path to DA)
try {
    Add-ADGroupMember -Identity "DnsAdmins" -Members "julien.moreau" -ErrorAction Stop
    Write-Host "  -> [DNS ADMINS] julien.moreau dans DnsAdmins (DLL injection -> DA)" -ForegroundColor Red
} catch { Write-Host "  -> julien.moreau deja dans DnsAdmins." -ForegroundColor Gray }

try {
    Add-ADGroupMember -Identity "DnsAdmins" -Members "svc_monitor" -ErrorAction Stop
    Write-Host "  -> [DNS ADMINS] svc_monitor dans DnsAdmins" -ForegroundColor Red
} catch { Write-Host "  -> svc_monitor deja dans DnsAdmins." -ForegroundColor Gray }

# [DNS Global Query Block List vide] - Permet WPAD/ISATAP poisoning
try {
    Set-DnsServerGlobalQueryBlockList -List @() -ErrorAction SilentlyContinue
    Write-Host "  -> [DNS GQBL VIDE] Global Query Block List videe (WPAD/ISATAP)" -ForegroundColor Red
} catch {}

# [Enregistrement WPAD dans DNS]
try {
    Add-DnsServerResourceRecordA -Name "wpad" -ZoneName $DomainName -IPv4Address "192.168.0.10" -ErrorAction SilentlyContinue
    Write-Host "  -> [WPAD DNS] Enregistrement wpad.$DomainName cree" -ForegroundColor Red
} catch {}

# ================================================================
# CHIFFREMENT FAIBLE - TLS/SSL/HASHING
# ================================================================

# [MD5 et SHA1 autorises dans Schannel]
try {
    $hashPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Hashes"
    # Activer MD5
    New-Item -Path "$hashPath\MD5" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "$hashPath\MD5" -Name "Enabled" -Value 0xFFFFFFFF -Type DWord
    Write-Host "  -> [MD5 ENABLED] Hashing MD5 actif dans Schannel" -ForegroundColor Red
    # Activer SHA (SHA1)
    New-Item -Path "$hashPath\SHA" -Force -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "$hashPath\SHA" -Name "Enabled" -Value 0xFFFFFFFF -Type DWord
    Write-Host "  -> [SHA1 ENABLED] Hashing SHA1 actif dans Schannel" -ForegroundColor Red
} catch {}

# [TLS 1.0 et TLS 1.1 actifs]
try {
    foreach ($ver in @("TLS 1.0","TLS 1.1")) {
        foreach ($side in @("Server","Client")) {
            $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$ver\$side"
            New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $path -Name "Enabled" -Value 1 -Type DWord
            Set-ItemProperty -Path $path -Name "DisabledByDefault" -Value 0 -Type DWord
        }
    }
    Write-Host "  -> [TLS 1.0 + 1.1 ON] Protocoles obsoletes actifs" -ForegroundColor Red
} catch {}

# [SSL 3.0 actif]
try {
    foreach ($side in @("Server","Client")) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\$side"
        New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $path -Name "Enabled" -Value 1 -Type DWord
    }
    Write-Host "  -> [SSL 3.0 ON] SSL 3.0 actif (POODLE)" -ForegroundColor Red
} catch {}

# [Cipher suites faibles - RC4, 3DES, NULL]
try {
    $weakCiphers = @("RC4 128/128","RC4 56/128","RC4 40/128","Triple DES 168","NULL")
    foreach ($cipher in $weakCiphers) {
        $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$cipher"
        New-Item -Path $path -Force -ErrorAction SilentlyContinue | Out-Null
        Set-ItemProperty -Path $path -Name "Enabled" -Value 0xFFFFFFFF -Type DWord
    }
    Write-Host "  -> [WEAK CIPHERS] RC4, 3DES, NULL ciphers actifs" -ForegroundColor Red
} catch {}

# ================================================================
# NETBIOS / WINS / LLMNR (couche reseau)
# ================================================================

# [NetBIOS over TCP actif]
try {
    $nic = Get-WmiObject Win32_NetworkAdapterConfiguration | Where-Object { $_.IPEnabled -eq $true } | Select-Object -First 1
    if ($nic) {
        $nic.SetTcpipNetbios(1)  # 1 = Enable NetBIOS over TCP/IP
        Write-Host "  -> [NETBIOS ON] NetBIOS over TCP/IP actif" -ForegroundColor Red
    }
} catch {}

# ================================================================
# TOMBSTONE & MAINTENANCE
# ================================================================

# [Tombstone court = 60j]
try {
    $configDN = (Get-ADRootDSE).configurationNamingContext
    Set-ADObject -Identity "CN=Directory Service,CN=Windows NT,CN=Services,$configDN" -Replace @{"tombstoneLifetime"=60}
    Write-Host "  -> [TOMBSTONE] = 60j (devrait etre 180)" -ForegroundColor Red
} catch {}

# ================================================================
# RODC (Read-Only Domain Controller) MISCONFIG
# ================================================================
Write-Host "`n  --- RODC Simulation ---" -ForegroundColor Yellow

# [RODC - Allowed RODC Password Replication Group trop permissive]
try {
    # Le groupe "Allowed RODC Password Replication Group" controle quels comptes sont caches sur un RODC
    # Y ajouter des groupes larges = fuite massive de hash si RODC compromis
    Add-ADGroupMember -Identity "Allowed RODC Password Replication Group" -Members "Domain Users" -ErrorAction Stop
    Write-Host "  -> [RODC REPL] 'Domain Users' dans Allowed RODC Password Replication Group!" -ForegroundColor Red
    Write-Host "         Si un RODC est compromis, TOUS les hash users sont exposes" -ForegroundColor Red
} catch { Write-Host "  -> Domain Users deja dans Allowed RODC Repl." -ForegroundColor Gray }

# Ajouter aussi des groupes privilegies (normalement interdit)
try {
    Add-ADGroupMember -Identity "Allowed RODC Password Replication Group" -Members "GRP_IT_Admins" -ErrorAction Stop
    Write-Host "  -> [RODC REPL] GRP_IT_Admins dans Allowed RODC Password Replication Group!" -ForegroundColor Red
} catch { Write-Host "  -> GRP_IT_Admins deja dans Allowed RODC Repl." -ForegroundColor Gray }

# [RODC - Denied list incomplete]
# Verifier que les comptes critiques sont dans Denied (normalement par defaut, mais vider partiellement)
try {
    # On ne retire pas les membres existants mais on log le warning
    $denied = Get-ADGroupMember "Denied RODC Password Replication Group" -ErrorAction SilentlyContinue
    Write-Host "  -> [INFO-RODC] $($denied.Count) membres dans Denied RODC Replication" -ForegroundColor Yellow
} catch {}

# [RODC - PRP (Password Replication Policy) computer objects]
try {
    # Ajouter des serveurs sensibles dans la liste autorisee
    Add-ADGroupMember -Identity "Allowed RODC Password Replication Group" -Members "DC01$" -ErrorAction SilentlyContinue
    Write-Host "  -> [RODC REPL] DC01$ dans Allowed RODC Replication (catastrophique)" -ForegroundColor Red
} catch {}

# ================================================================
# SERVICES DANGEREUX ACTIFS
# ================================================================

# [Remote Registry actif]
try { Set-Service -Name "RemoteRegistry" -StartupType Automatic; Start-Service -Name "RemoteRegistry" -ErrorAction SilentlyContinue; Write-Host "  -> [REMOTE REGISTRY] Service Remote Registry actif" -ForegroundColor Red } catch {}

# [WinRM HTTP (pas HTTPS)]
try {
    Enable-PSRemoting -Force -SkipNetworkProfileCheck -ErrorAction SilentlyContinue
    # S'assurer que le listener HTTP existe
    Write-Host "  -> [WINRM HTTP] WinRM en HTTP (pas HTTPS/TLS)" -ForegroundColor Red
} catch {}

# [SNMP community string par defaut]
try {
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities" -Name "public" -Value 4 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\SNMP\Parameters\ValidCommunities" -Name "private" -Value 8 -PropertyType DWord -Force -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  -> [SNMP] Community strings: public(RO), private(RW)" -ForegroundColor Red
} catch {}

Write-Host "`n  -> Configurations domaine vulnerables appliquees." -ForegroundColor Cyan
