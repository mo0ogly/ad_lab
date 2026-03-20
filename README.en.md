# AD Lab

**Deliberately vulnerable Active Directory lab**, automatically deployable on Hyper-V.

Built to test and validate AD security audit tools:
[PingCastle](https://www.pingcastle.com/) · [ANSSI ADS](https://www.cert.ssi.gouv.fr/actualite/CERTFR-2020-ACT-011/) · [BloodHound](https://bloodhound.specterops.io/) · [LIA-Scan](https://github.com/)

> **WARNING** — This lab is **intentionally vulnerable**. It contains weak passwords,
> dangerous ACLs, backdoors, and insecure configurations.
> **Never deploy in production or on a non-isolated network.**

---

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Quick Start](#quick-start)
- [Detailed Installation](#detailed-installation)
- [Architecture](#architecture)
- [Injected Vulnerabilities](#injected-vulnerabilities)
- [Collector Coverage](#collector-coverage)
- [Project Structure](#project-structure)
- [Credentials](#credentials)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Features

| Component | Detail |
|-----------|--------|
| **Domains** | `lab.local` + `partner.local` (bidirectional trust) |
| **3 Hyper-V VMs** | DC01 (DC + CA), DC02 (RODC), DC-PARTNER (2nd forest) |
| **80+ users** | 12 departments, admin accounts, service accounts, partners |
| **40+ groups** | Security, distribution, ACL, nested BloodHound cascades |
| **30+ GPOs** | 11 legitimate + 20 vulnerable |
| **90+ misconfigurations** | Covering **60 security collectors** |
| **15+ services** | ADCS (PKI), IIS, DFS, NPS, ADFS, RDS, DHCP, DNS, SMTP... |
| **Deployment** | Automated via PowerShell Direct — ~45 min |

---

## Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| **Host OS** | Windows 10/11 Pro | Windows 11 Pro for Workstations |
| **Hyper-V** | Enabled | Enabled |
| **RAM** | 8 GB (DC01 only) | 12 GB (3 VMs) |
| **Disk** | 100 GB | 200 GB |
| **CPU** | 4 cores | 8 cores |
| **ISO** | Windows Server 2022 Eval | [Download](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) |
| **PowerShell** | 5.1+ | 5.1+ |
| **LAPS** | Optional | [Download](https://www.microsoft.com/en-us/download/details.aspx?id=46899) |
| **Collectors** | `E:\ad.zip` | 60 LIA-Scan scripts |

---

## Quick Start

### Core Infrastructure (DC01 — 1 VM)

```powershell
# 1. Open PowerShell as Administrator on the Windows host

# 2. Create the Hyper-V VM
.\01_Create-VM.ps1 -ISOPath "D:\ISOs\server2022.iso"

# 3. In the Hyper-V console:
#    - Install Windows Server 2022 Desktop Experience
#    - Administrator password: (see config.ps1)

# 4. Deploy the lab automatically (copies + runs scripts inside the VM)
.\run_in_vm.ps1
```

The lab is ready. DC01 contains a fully populated AD with 90+ misconfigurations.

### Deploy and Run Collectors

```powershell
# Copies the 60 collectors from E:\ad.zip to C:\Share\collectors\ on the VM
# Automatically applies fixes (duplicate keys, filters, etc.)
.\deploy_collectors.ps1

# Interactive menu — choose execution mode:
#   1. FULL     — all 60 collectors (production, needs joined machines)
#   2. AD ONLY  — excludes remote scans (recommended for lab)
#   3. QUICK    — AD only + excludes heavy collectors (test)
.\run_collectors.ps1
```

The `deploy_collectors.ps1` script extracts the zip, applies fixes
(`fix_collectors.ps1`), then sends each `.ps1` into the VM via PowerShell Direct.

The `run_collectors.ps1` script displays a menu with 3 modes:
- **Mode 1 — FULL**: all 60 collectors. Requires domain-joined machines
  reachable via WMI/RPC (production use).
- **Mode 2 — AD ONLY** (recommended for lab): excludes the 9 collectors
  that scan remote machines (Antivirus, LocalAdmins, Spooler, Registry...).
- **Mode 3 — QUICK**: mode 2 + excludes heavy collectors (ADCompleteTaxonomy, ADAcls).

Results are exported to `C:\Share\collectors_results.csv`.

> **Note**: LAPS must be installed on the DC for `Collect-ADLapsBitLocker`
> to work. Without LAPS, the AD schema lacks the `ms-Mcs-AdmPwdExpirationTime` attribute.

### Extended Infrastructure (RODC + Trust — 3 VMs)

```powershell
# 5. Create additional VMs (on the host)
.\05_Deploy-SecondDC.ps1 -ISOPath "D:\ISOs\server2022.iso"

# 6. Install Windows Server in each VM, then run:
#    - In DC02-LAB  : C:\HyperV\setup-scripts\A2_Install-RODC.ps1
#    - In DC-PARTNER: C:\HyperV\setup-scripts\B2_Install-PartnerForest.ps1
#    - In DC-PARTNER: C:\HyperV\setup-scripts\B3_PostConfig-Partner.ps1

# 7. On DC01, establish the trust + inject vulnerabilities
#    C:\HyperV\setup-scripts\B4_Setup-Trust-Vulns.ps1
```

---

## Detailed Installation

### Step 1 — Create the VM (on the host)

```powershell
.\01_Create-VM.ps1 -ISOPath "D:\ISOs\server2022.iso"
```

The script:
- Enables Hyper-V if needed (host reboot required on first run)
- Creates an **External** vSwitch `LabSwitch` bound to your physical NIC
- Creates VM `DC01-LAB`: Generation 2, 4 vCPU, 4 GB dynamic RAM, 80 GB VHDX
- Mounts the ISO and sets DVD as first boot device

**After execution**: the Hyper-V console opens. Quickly press a key to boot from the DVD,
then install Windows Server 2022 **Desktop Experience**.
Administrator password: `(see config.ps1)`

### Step 2 — Automated Deployment (on the host)

```powershell
.\run_in_vm.ps1
```

This script uses PowerShell Direct to copy and execute everything inside the VM:

| Phase | Script | Duration | Detail |
|-------|--------|----------|--------|
| Copy | — | ~1 min | 3 main scripts + 13 `populate/` sub-scripts |
| AD DS | `02_Install-ADDS.ps1` | ~10 min | Static IP, rename to DC01, DC promotion, DNS, DHCP |
| Services | `03_Install-Services.ps1` | ~20 min | ADCS, IIS, DFS, NPS, ADFS, RDS, SMTP, etc. |
| Population | `04_Populate-AD.ps1` | ~5 min | 13 sub-scripts: OUs, users, groups, GPOs, ACLs, vulns |

> **Note**: The script will prompt you to press Enter after the intermediate DC reboot
> (AD DS promotion).

### Step 2 Alternative — Manual Installation (inside the VM)

If PowerShell Direct doesn't work, transfer scripts manually.

**Method 1 — SMB Share** (recommended):

```powershell
# On the host (PowerShell Admin) — creates the share and copies files into the VM
.\setup_share2.ps1
```

The script:
- Disables the VM firewall
- Creates a `\\192.168.0.10\Share` share (Everyone FullAccess)
- Copies all scripts to `C:\Share\ad_lab\` via PowerShell Direct

Scripts are then accessible:
- From the VM: `C:\Share\ad_lab\`
- From the host: `\\192.168.0.10\Share\ad_lab\`

```powershell
# Inside the VM — run scripts from the share
C:\Share\ad_lab\02_Install-ADDS.ps1        # re-run after each reboot
C:\Share\ad_lab\03_Install-Services.ps1
C:\Share\ad_lab\04_Populate-AD.ps1
```

**Method 2 — HTTP Server**:
```powershell
# On the host — start a temporary HTTP server
python -m http.server 8888 --bind 192.168.0.98 --directory C:\path\to\ad_lab
```

```powershell
# Inside the VM — download all scripts
New-Item C:\LabScripts\populate -ItemType Directory -Force

@("02_Install-ADDS","03_Install-Services","04_Populate-AD") | ForEach-Object {
    Invoke-WebRequest "http://192.168.0.98:8888/$_.ps1" -OutFile "C:\LabScripts\$_.ps1"
}

"04a_Create-OUs","04b_Create-Groups","04c_Create-Users","04d_Create-Services",
"04e_Create-Admins","04f_Create-Partners","04g_Create-Computers","04h_Set-ACLs",
"04i_Set-GPOs","04j_Set-DomainConfig","04k_Set-PasswordPolicies",
"04l_Set-ADCS-Vulns","04m_Set-CollectorTargets" | ForEach-Object {
    Invoke-WebRequest "http://192.168.0.98:8888/populate/$_.ps1" -OutFile "C:\LabScripts\populate\$_.ps1"
}
```

Then run in order:
```powershell
C:\LabScripts\02_Install-ADDS.ps1        # re-run after each reboot
C:\LabScripts\03_Install-Services.ps1
C:\LabScripts\04_Populate-AD.ps1
```

### Step 3 — RODC + Trust (optional, on the host)

```powershell
.\05_Deploy-SecondDC.ps1 -ISOPath "D:\ISOs\server2022.iso"
```

Creates 2 additional VMs and generates setup scripts in `C:\HyperV\setup-scripts\`:

| Order | Script | Run on | Purpose |
|-------|--------|--------|---------|
| 1 | `A2_Install-RODC.ps1` | DC02-LAB | Static IP, RODC promotion in lab.local |
| 2 | `B2_Install-PartnerForest.ps1` | DC-PARTNER | Create the partner.local forest |
| 3 | `B3_PostConfig-Partner.ps1` | DC-PARTNER | Conditional DNS forwarder + partner users |
| 4 | `B4_Setup-Trust-Vulns.ps1` | DC01 | Bidirectional trust + 4 vulnerabilities |

---

## Architecture

```
Internet
    |
[Router / Gateway — 192.168.0.1]
    |
[LabSwitch — External Hyper-V vSwitch]
    |
    +--- DC01-LAB    192.168.0.10    lab.local        DC + CA + 15 services
    |    4 vCPU / 4 GB RAM / 80 GB
    |
    +--- DC02-LAB    192.168.0.11    lab.local        RODC (Read-Only DC)
    |    2 vCPU / 2 GB RAM / 60 GB
    |
    +--- DC-PARTNER  192.168.0.12    partner.local    2nd forest + trust
         2 vCPU / 2 GB RAM / 60 GB
```

**Trust**: bidirectional between `lab.local` and `partner.local` (External Trust,
intentionally misconfigured: SID Filtering OFF, TGT Delegation ON, RC4 only).

---

## Injected Vulnerabilities

### Overview (90+)

| Category | Count | Examples |
|----------|-------|----------|
| **Kerberos / Auth** | 15+ | Kerberoasting (8 SPNs), AS-REP Roast (8 accounts), DES/RC4 only, NTLMv1, WDigest |
| **ACLs / Delegation** | 15+ | DCSync (2), WriteDACL, GenericAll, WriteOwner, AdminSDHolder, Unconstrained/Constrained/RBCD |
| **Groups / Cascades** | 10+ | 7 BloodHound paths to DA, circular groups, distribution→security |
| **Accounts** | 15+ | 12+ DA, former employees, pwd in description, PASSWD_NOTREQD, shadow admins |
| **GPOs** | 20 | LLMNR, WPAD, WDigest, AlwaysInstallElevated, UAC OFF, PS logging OFF, Defender OFF |
| **PKI / ADCS** | 8 | ESC1 (x2), ESC2, ESC3, ESC4, ESC6, ESC8, exportable keys |
| **Network / DNS** | 10+ | Null sessions, SMBv1, PrintNightmare, WPAD DNS, zone transfer, empty GQBL |
| **Domain config** | 10+ | LDAP signing OFF, MachineAccountQuota=10, Guest ON, Recycle Bin OFF |
| **Password policies** | 7 | 5 vulnerable PSOs (1 char min, reversible, no lockout), LM hash storage |
| **Trust** | 3 | SID Filtering OFF, TGT Delegation, RC4 only (no AES) |
| **RODC** | 1 | Domain Admins in Allowed Password Replication |

### Detail by Script

| Script | Vulnerabilities |
|--------|-----------------|
| `04c_Create-Users` | AS-REP Roast (3), pwd in description (3), wrong OU, PasswordNotRequired, Kerberoastable user |
| `04d_Create-Services` | Kerberoasting (8), AS-REP (5), pwd=username (3), service in DA, DCSync, delegation (5 types) |
| `04e_Create-Admins` | 12+ DA, former employees, DA kerberoastable, disabled in DA, pwd in description, DES only |
| `04f_Create-Partners` | External contractor in DA, no expiration, shared/generic accounts |
| `04g_Create-Computers` | Unconstrained delegation (3), legacy OS (9), stale machines, RBCD, duplicate SPN |
| `04h_Set-ACLs` | 7 nested group paths, DCSync, AdminSDHolder backdoor, GenericWrite on DA group |
| `04i_Set-GPOs` | 20 vulnerable GPOs + 2 backdoor scheduled tasks |
| `04j_Set-DomainConfig` | SMBv1, PrintNightmare, null sessions, SNMP public/private, weak crypto |
| `04k_Set-PasswordPolicies` | 5 vulnerable PSOs + LM hash storage |
| `04l_Set-ADCS-Vulns` | ESC1-ESC8, exportable keys, 10-year certs |
| `04m_Set-CollectorTargets` | AADConnect, gMSA, GPP passwords, Exchange, SharePoint, ADFS, dSHeuristics, DisplaySpecifier |

---

## Collector Coverage

**60 collectors** — every AD collector will find at least one misconfiguration.
The 9 remote scan collectors (WMI/Registry) require domain-joined machines.

<details>
<summary>Full table: collector → vulnerability → source script</summary>

| Collector | Detected Vulnerability | Script |
|---|---|---|
| `Collect-AADConnect` | MSOL_* DCSync + AZUREADSSOACC Silver Ticket | 04m |
| `Collect-ADAttackSurface` | Kerberoasting, AS-REP, Unconstrained delegation | 04c/04d |
| `Collect-ADCS` | ESC1-ESC8, CA permissions | 04l |
| `Collect-ADCompleteTaxonomy` | Full taxonomy coverage | 04a-04m |
| `Collect-ADFSConfig` | DKM container + GenericRead for Domain Users | 04m |
| `Collect-ADHygieneMetrics` | Stale users/computers (90+ days) | 04c/04g |
| `Collect-ADObjectsSecurityAttributes` | Dangerous UAC flags | 04c/04d/04e |
| `Collect-DCHardening` | Print Spooler running + RDP without NLA | 04j |
| `Collect-DCLogonRights` | Dangerous privileges on DCs | 04m |
| `Collect-DCOwnership` | DC owner != DA/EA | 04m |
| `Collect-DCRegistry` | Registry ACLs on DCs | 04j |
| `Collect-DCRegistryKey` | LDAP signing OFF, LM hash, SMB signing | 04j |
| `Collect-Delegations` | Dangerous ACLs on OUs | 04h |
| `Collect-DHCPConfig` | DHCP Administrators group populated | 04m |
| `Collect-DisplaySpecifier` | adminContextMenu UNC backdoor | 04m |
| `Collect-DnsAdminsMembers` | DnsAdmins with members | 04j |
| `Collect-DNSConfig` | Zone transfer to Any, WPAD, empty GQBL | 04j |
| `Collect-DsHeuristics` | Anonymous NSPI + SDProp exclusion | 04m |
| `Collect-ExchangeConfig` | RBAC groups + Shared Permissions WriteDacl | 04m |
| `Collect-GMSADelegation` | gMSA with GenericAll/WriteDACL | 04m |
| `Collect-GPOAuditOwnership` | Audit GPO with non-standard owner | 04m |
| `Collect-GPOAuditSettings` | 6/9 audit categories disabled | 04m |
| `Collect-GPOSettings` | LM Hash, min 7 chars, no lockout | 04m |
| `Collect-GPOUserRights` | SeDebug/SeLoadDriver to Authenticated Users | 04m |
| `Collect-GPPPasswords` | cpassword in Groups.xml + ScheduledTasks.xml | 04m |
| `Collect-KerberosPreAuth` | AS-REP Roastable (8+ accounts) | 04c/04d/04e |
| `Collect-KrbtgtPasswordAge` | krbtgt password never changed | 04j |
| `Collect-LAPSStatus` | LAPS not deployed | 04g |
| `Collect-PasswordNeverExpiresCount` | DA with PasswordNeverExpires | 04e |
| `Collect-PasswordNotRequiredCount` | DA with PASSWD_NOTREQD | 04m |
| `Collect-PreCreatedComputerCount` | Computers with pwdLastSet=0 | 04g |
| `Collect-PrivilegedAdminCount` | 12+ Domain Admins | 04e |
| `Collect-ProtectedUsersAllowedList` | Members with delegation conflict | 04m |
| `Collect-RecycleBinStatus` | AD Recycle Bin OFF | 04j |
| `Collect-RODCConfig` | DA in Allowed PRP | B4 |
| `Collect-SchemaAdminsMembers` | Schema Admins not empty | 04h |
| `Collect-SharePointConfig` | SCP + Farm Admins with DA members | 04m |
| `Collect-SIDHistory` | Cross-domain sIDHistory | 04m |
| `Collect-SysvolPermissions` | SYSVOL writable by Domain Users | 04m |
| `Collect-Trusts` | SID Filtering OFF, TGT Delegation, RC4 | B4 |
| `Collect-UnixPasswordCount` | unixUserPassword on 4 accounts | 04m |

</details>

---

## Project Structure

```
ad_lab/
│
├── README.md                          # This file (French)
├── README.en.md                       # English version
├── GUIDE_INSTALLATION.md              # Detailed technical guide (French)
├── DEPLOY.bat                         # Quick-launch menu
├── LICENSE                            # MIT License
├── VERSION                            # Current version
│
│   --- Main scripts ---
│
├── 01_Create-VM.ps1                   # [HOST] Create Hyper-V VM
├── 02_Install-ADDS.ps1                # [VM]   AD DS + DNS + DHCP + DC promotion
├── 03_Install-Services.ps1            # [VM]   15+ Windows services
├── 04_Populate-AD.ps1                 # [VM]   Orchestrator → populate/04a-04m
├── 05_Deploy-SecondDC.ps1             # [HOST] RODC + partner.local + trust VMs
├── 05_Fix-Network.ps1                 # [HOST] Network / VLAN fix
├── 06_Install-Claude-Code.ps1         # [VM]   Claude Code CLI (optional)
│
│   --- Population sub-scripts ---
│
├── populate/
│   ├── 04a_Create-OUs.ps1            # Organizational structure (20+ OUs)
│   ├── 04b_Create-Groups.ps1         # Security/distribution groups (40+)
│   ├── 04c_Create-Users.ps1          # Users by department (80+)
│   ├── 04d_Create-Services.ps1       # Service accounts + Kerberos vulns
│   ├── 04e_Create-Admins.ps1         # Admin accounts + privilege vulns
│   ├── 04f_Create-Partners.ps1       # Partners + generic accounts
│   ├── 04g_Create-Computers.ps1      # Servers + workstations + legacy OS
│   ├── 04h_Set-ACLs.ps1              # Dangerous ACLs + nested groups
│   ├── 04i_Set-GPOs.ps1              # Normal + 20 vulnerable GPOs
│   ├── 04j_Set-DomainConfig.ps1      # Dangerous domain configuration
│   ├── 04k_Set-PasswordPolicies.ps1  # Fine-Grained Password Policies
│   ├── 04l_Set-ADCS-Vulns.ps1        # ADCS certificates (ESC1-ESC8)
│   └── 04m_Set-CollectorTargets.ps1  # Objects for LIA-Scan collectors
│
│   --- Utilities ---
│
├── run_in_vm.ps1                      # [HOST] Automated deployment via PS Direct
├── deploy_collectors.ps1              # [HOST] Copy + fix collectors into the VM
├── run_collectors.ps1                 # [HOST] Run all collectors + summary
├── fix_collectors.ps1                 # [HOST] Collector bug fixes
├── setup_share2.ps1                   # [HOST] Create SMB share + copy scripts to VM
├── config.ps1                         # [LOCAL] Password (gitignored)
├── config.example.ps1                 # Template for config.ps1
├── .gitignore                         # Excludes config.ps1
├── diag.ps1                           # [HOST] VM diagnostics
├── fix_boot.ps1                       # [HOST] DVD boot fix
├── fix_missing_objects.ps1            # [HOST] Create missing AD objects
└── rebuild.ps1                        # [HOST] Full VM rebuild
```

---

## Credentials

| Account | Password | Usage |
|---------|----------|-------|
| `Administrator` | `(see config.ps1)` | Local admin / DSRM |
| `LAB\Administrator` | `(see config.ps1)` | Domain admin |
| All standard users | `(see config.ps1)` | Default password |
| `adm.*` accounts | `Adm1n!(see config.ps1)` | Admin accounts |
| Weak accounts | `Password1` | Legacy services, partners |
| `PARTNER\Administrator` | `(see config.ps1)` | partner.local admin |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| VM has no internet | `.\05_Fix-Network.ps1` or `Set-VMNetworkAdapterVlan -VMName DC01-LAB -Untagged` |
| VM won't boot from ISO | `.\fix_boot.ps1 -ISOPath "D:\ISOs\server2022.iso"` |
| Full rebuild | `.\rebuild.ps1 -ISOPath "D:\ISOs\server2022.iso"` |
| PowerShell Direct doesn't work | Use HTTP transfer (see [Detailed Installation](#step-2-alternative--manual-installation-inside-the-vm)) |
| Script 02 requires multiple reboots | Normal — re-run after each reboot (2-3 times) |

---

## Contributing

Contributions are welcome. To add new vulnerabilities:

1. Identify the target collector
2. Add AD objects in the corresponding `populate/` sub-script
3. Document the vulnerability in this README (coverage table)
4. Test with the relevant collector

---

## License

This project is distributed under the **MIT License**. See [LICENSE](LICENSE).

---

## Version

See [VERSION](VERSION) — current version: **1.0.0**
