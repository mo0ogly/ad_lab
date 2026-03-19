<#
.SYNOPSIS
    Cree les objets ordinateur (serveurs + postes)
    Anomalies: delegation non contrainte, RBCD, vieux OS (2003/2008/Win7),
    machines stale, LAPS non deploye, machines dans mauvaise OU
#>

param(
    [string]$DomainDN = "DC=lab,DC=local"
)

Write-Host "`n[MACHINES] Objets ordinateur..." -ForegroundColor Yellow

# --- Serveurs modernes ---
$servers = @(
    @{Name="SRV-FILE01"; Desc="File Server principal"},
    @{Name="SRV-SQL01"; Desc="SQL Server Production"},
    @{Name="SRV-SQL02"; Desc="SQL Server Dev/Staging"},
    @{Name="SRV-WEB01"; Desc="Serveur Web IIS"},
    @{Name="SRV-WEB02"; Desc="Serveur Web Apache"},
    @{Name="SRV-EXCH01"; Desc="Exchange Server"},
    @{Name="SRV-SCCM01"; Desc="SCCM/MECM Server"},
    @{Name="SRV-BACKUP01"; Desc="Serveur Backup"},
    @{Name="SRV-PRINT01"; Desc="Print Server"},
    @{Name="SRV-APP01"; Desc="Application Server"},
    @{Name="SRV-MONITOR01"; Desc="Monitoring (Zabbix/PRTG)"},
    @{Name="SRV-ADFS01"; Desc="ADFS Server"},
    @{Name="SRV-WSUS01"; Desc="WSUS Server"},
    @{Name="SRV-NPS01"; Desc="NPS/RADIUS Server"},
    @{Name="SRV-RELAY01"; Desc="SMTP Relay"}
)

foreach ($s in $servers) {
    try {
        New-ADComputer -Name $s.Name -Path "OU=Serveurs,$DomainDN" -Description $s.Desc -Enabled $true -ErrorAction Stop
        Write-Host "  -> $($s.Name)" -ForegroundColor Green
    } catch { Write-Host "  -> $($s.Name) existe deja." -ForegroundColor Gray }
}

# --- Postes de travail ---
$workstations = @(
    "PC-DIR-001","PC-DIR-002",
    "PC-IT-001","PC-IT-002","PC-IT-003","PC-IT-004",
    "PC-RH-001","PC-RH-002",
    "PC-FIN-001","PC-FIN-002",
    "PC-COM-001","PC-COM-002","PC-COM-003",
    "PC-DEV-001","PC-DEV-002","PC-DEV-003",
    "PC-ACC-001","PC-SOC-001","PC-JUR-001",
    "LAPTOP-COM-001","LAPTOP-COM-002","LAPTOP-DIR-001"
)

foreach ($pc in $workstations) {
    try {
        New-ADComputer -Name $pc -Path "OU=Postes,$DomainDN" -Enabled $true -ErrorAction Stop
        Write-Host "  -> $pc" -ForegroundColor Green
    } catch { Write-Host "  -> $pc existe deja." -ForegroundColor Gray }
}

# ================================================================
# MACHINES VULNERABLES
# ================================================================
Write-Host "`n  --- Machines VULNERABLES ---" -ForegroundColor Red

# [DELEGATION NON CONTRAINTE sur serveurs]
foreach ($srv in @("SRV-WEB01","SRV-PRINT01","SRV-FILE01")) {
    try { Set-ADComputer -Identity $srv -TrustedForDelegation $true; Write-Host "  -> [UNCONSTR DELEG] $srv" -ForegroundColor Red } catch {}
}

# [VIEUX OS - Windows Server 2003/2008/2012]
$oldServers = @(
    @{Name="SRV-LEGACY-2003"; OS="Windows Server 2003"; SP="Service Pack 2"; Desc="Ancien serveur metier - NE PAS ETEINDRE"},
    @{Name="SRV-LEGACY-2008"; OS="Windows Server 2008 R2"; SP="Service Pack 1"; Desc="Serveur applicatif legacy"},
    @{Name="SRV-LEGACY-2012"; OS="Windows Server 2012"; SP=""; Desc="Serveur fichiers ancien site"},
    @{Name="SRV-SQL-2008"; OS="Windows Server 2008"; SP="Service Pack 2"; Desc="SQL Server 2008 - app metier critique"}
)
foreach ($old in $oldServers) {
    try {
        New-ADComputer -Name $old.Name -Path "OU=Serveurs,$DomainDN" -Description $old.Desc -Enabled $true -ErrorAction Stop
        Set-ADComputer -Identity $old.Name -Replace @{
            "operatingSystem"=$old.OS
            "operatingSystemServicePack"=$old.SP
            "operatingSystemVersion"="6.1 (7601)"
        }
        Write-Host "  -> [OLD OS] $($old.Name) = $($old.OS)" -ForegroundColor Red
    } catch { Write-Host "  -> $($old.Name) existe deja." -ForegroundColor Gray }
}

# [VIEUX OS - Windows 7 / Windows XP postes]
$oldPCs = @(
    @{Name="PC-ACCUEIL-XP"; OS="Windows XP Professional"; Desc="PC accueil - app ancienne"},
    @{Name="PC-LABO-W7-001"; OS="Windows 7 Professional"; Desc="Poste labo - logiciel certifie W7 only"},
    @{Name="PC-LABO-W7-002"; OS="Windows 7 Professional"; Desc="Poste labo - microscope"},
    @{Name="PC-ATELIER-W7"; OS="Windows 7 Enterprise"; Desc="Poste atelier production"},
    @{Name="PC-KIOSK-W8"; OS="Windows 8.1 Pro"; Desc="Borne kiosque"}
)
foreach ($old in $oldPCs) {
    try {
        New-ADComputer -Name $old.Name -Path "OU=Postes,$DomainDN" -Description $old.Desc -Enabled $true -ErrorAction Stop
        Set-ADComputer -Identity $old.Name -Replace @{
            "operatingSystem"=$old.OS
            "operatingSystemVersion"="6.1 (7601)"
        }
        Write-Host "  -> [OLD OS] $($old.Name) = $($old.OS)" -ForegroundColor Red
    } catch { Write-Host "  -> $($old.Name) existe deja." -ForegroundColor Gray }
}

# [MACHINES STALE - pas de logon depuis longtemps]
$staleMachines = @("PC-ANCIEN-001","PC-ANCIEN-002","PC-DEPART-MARTIN","SRV-OLD-INTRANET","SRV-TEST-2021")
foreach ($stale in $staleMachines) {
    try {
        New-ADComputer -Name $stale -Path "OU=Postes,$DomainDN" -Description "Machine non vue depuis 2022" -Enabled $true -ErrorAction Stop
        # Forcer une date de password ancienne pour simuler l'inactivite
        Set-ADComputer -Identity $stale -Replace @{"pwdLastSet"=0}
        Write-Host "  -> [STALE] $stale (password jamais set)" -ForegroundColor Red
    } catch { Write-Host "  -> $stale existe deja." -ForegroundColor Gray }
}

# [MACHINE DANS CN=Computers (mauvaise OU)]
try {
    New-ADComputer -Name "PC-TEMP-STAGIAIRE" -Path "CN=Computers,$DomainDN" -Description "PC stagiaire non deplace" -Enabled $true -ErrorAction Stop
    Write-Host "  -> [WRONG OU] PC-TEMP-STAGIAIRE dans CN=Computers (pas dans OU)" -ForegroundColor Red
} catch { Write-Host "  -> PC-TEMP-STAGIAIRE existe deja." -ForegroundColor Gray }
try {
    New-ADComputer -Name "PC-URGENCE-IT" -Path "CN=Computers,$DomainDN" -Description "Ajoute en urgence" -Enabled $true -ErrorAction Stop
    Write-Host "  -> [WRONG OU] PC-URGENCE-IT dans CN=Computers" -ForegroundColor Red
} catch { Write-Host "  -> PC-URGENCE-IT existe deja." -ForegroundColor Gray }

# [RBCD sur machine - Resource-Based Constrained Delegation]
try {
    $attackerSid = (Get-ADComputer "SRV-WEB01").SID
    $target = Get-ADComputer "SRV-SQL01"
    $sd = New-Object Security.AccessControl.RawSecurityDescriptor("O:BAD:(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;$attackerSid)")
    $sdBytes = New-Object byte[] ($sd.BinaryLength)
    $sd.GetBinaryForm($sdBytes, 0)
    Set-ADComputer -Identity $target -Replace @{"msDS-AllowedToActOnBehalfOfOtherIdentity"=$sdBytes}
    Write-Host "  -> [RBCD] SRV-WEB01 peut impersonner vers SRV-SQL01 via RBCD!" -ForegroundColor Red
} catch { Write-Host "  -> Erreur RBCD SRV-WEB01->SQL01: $_" -ForegroundColor Gray }

# [CONSTRAINED DELEGATION sur machine]
try {
    Set-ADComputer -Identity "SRV-SCCM01" -Add @{
        "msDS-AllowedToDelegateTo"=@("CIFS/SRV-FILE01.lab.local","HTTP/SRV-WEB01.lab.local")
    } -ErrorAction Stop
    Write-Host "  -> [CONSTR DELEG] SRV-SCCM01 -> CIFS/FILE01 + HTTP/WEB01" -ForegroundColor Red
} catch {}

# [LAPS non deploye - aucun attribut ms-Mcs-AdmPwd]
Write-Host "  -> [LAPS] LAPS non deploye sur aucun poste (ms-Mcs-AdmPwd absent)" -ForegroundColor Red
Write-Host "         -> Tous les postes ont le meme mdp admin local" -ForegroundColor Red

# [SPN duplices sur machines]
try {
    Set-ADComputer -Identity "SRV-WEB02" -ServicePrincipalNames @{Add="HTTP/intranet.lab.local"} -ErrorAction SilentlyContinue
    Write-Host "  -> [DUP SPN] SRV-WEB02 a SPN HTTP/intranet (deja sur svc_http_intra)" -ForegroundColor Red
} catch {}

$total = $servers.Count + $workstations.Count + $oldServers.Count + $oldPCs.Count + $staleMachines.Count + 2
Write-Host "  -> $total machines creees." -ForegroundColor Cyan
