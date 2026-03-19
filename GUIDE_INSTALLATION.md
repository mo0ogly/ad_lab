# Lab Active Directory — Guide d'installation complet

## Apercu

Lab AD volontairement vulnerable pour tester les outils d'audit de securite
(PingCastle, ANSSI ADS, BloodHound, LIA-Scan). Deploiement automatise sur Hyper-V.

| Element | Valeur |
|---------|--------|
| **Domaine principal** | `lab.local` (NetBIOS: `LAB`) |
| **DC principal** | `DC01` (`DC01-LAB` dans Hyper-V) — `192.168.0.10/24` |
| **RODC** | `DC02` (`DC02-LAB`) — `192.168.0.11/24` |
| **Foret partenaire** | `partner.local` (`DC-PARTNER`) — `192.168.0.12/24` |
| **Passerelle** | `192.168.0.1` |
| **DHCP Scope** | `192.168.0.100` - `192.168.0.200` |
| **OS** | Windows Server 2022 Evaluation |
| **Anomalies** | 90+ vulnerabilites couvrant 42 collecteurs |

---

## Pre-requis

- Windows 10/11 Pro ou Enterprise (Hyper-V requis)
- **12 Go RAM minimum** (4+2+2 Go pour les 3 VMs + hote)
- **200 Go espace disque** (80+60+60 Go)
- ISO Windows Server 2022 ([Microsoft Eval Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022))
- PowerShell 5.1+ en mode Administrateur

---

## Architecture

```
Internet
    |
[Box/Routeur 192.168.0.1]
    |
[LabSwitch — External vSwitch]
    |
    +--- Hote Windows 11
    |
    +--- DC01-LAB    (192.168.0.10)  lab.local       — DC + CA + 15 services
    +--- DC02-LAB    (192.168.0.11)  lab.local       — RODC (Read-Only DC)
    +--- DC-PARTNER  (192.168.0.12)  partner.local   — 2e foret + trust
```

> **Le LabSwitch est External** (lie a la carte physique). Les VMs NIC en mode **Untagged**.

---

## Deploiement rapide (automatise)

```powershell
# 1. Sur l'HOTE — creer la VM DC01
.\01_Create-VM.ps1 -ISOPath "C:\chemin\vers\server2022.iso"

# 2. Installer Windows Server dans la VM (console Hyper-V)
#    Mot de passe Administrator : Cim22091956!!??

# 3. Sur l'HOTE — deployer automatiquement AD + services + population
.\run_in_vm.ps1

# 4. (Optionnel) Sur l'HOTE — RODC + partner forest + trust
.\05_Deploy-SecondDC.ps1 -ISOPath "C:\chemin\vers\server2022.iso"
```

---

## Deploiement detaille

### Etape 1 — Creer la VM (sur l'hote)

```powershell
.\01_Create-VM.ps1 -ISOPath "C:\chemin\vers\server2022.iso"
```

- Active Hyper-V si necessaire (reboot requis)
- Cree le vSwitch `LabSwitch` (External)
- Cree la VM `DC01-LAB` : 4 vCPU, 4 Go RAM, 80 Go disque, Gen 2
- Monte l'ISO et configure le boot DVD

**Apres execution :**
1. Console VM → appuyer sur une touche pour booter sur le DVD
2. Installer Windows Server 2022 **Desktop Experience**
3. Mot de passe Administrator : `Cim22091956!!??`

---

### Etape 2 — Installer Active Directory (dans la VM)

```powershell
.\02_Install-ADDS.ps1
```

- Configure IP statique : `192.168.0.10/24`, GW `192.168.0.1`
- Renomme en `DC01` → **reboot** → relancer le script
- Installe AD DS + DNS → promeut DC → **reboot** → relancer
- Configure DNS inverse + forwarders (8.8.8.8, 1.1.1.1)
- Installe DHCP (scope 192.168.0.100-200)

> **Note** : 2-3 executions necessaires (redemarrages intermediaires).

---

### Transfert des scripts dans la VM

**Option A — PowerShell Direct** (automatique) :
```powershell
# Sur l'HOTE — copie et execute tout
.\run_in_vm.ps1
```

**Option B — Serveur HTTP** (manuel) :
```powershell
# Sur l'HOTE
python -m http.server 8888 --bind 192.168.0.98 --directory C:\chemin\vers\ad_lab
```
```powershell
# Dans la VM — telecharger scripts + populate/
New-Item C:\LabScripts\populate -ItemType Directory -Force
@("03_Install-Services.ps1","04_Populate-AD.ps1") | ForEach-Object {
    Invoke-WebRequest "http://192.168.0.98:8888/$_" -OutFile "C:\LabScripts\$_"
}
# Telecharger chaque sous-script populate/04a-04m
"04a_Create-OUs","04b_Create-Groups","04c_Create-Users","04d_Create-Services",
"04e_Create-Admins","04f_Create-Partners","04g_Create-Computers","04h_Set-ACLs",
"04i_Set-GPOs","04j_Set-DomainConfig","04k_Set-PasswordPolicies",
"04l_Set-ADCS-Vulns","04m_Set-CollectorTargets" | ForEach-Object {
    Invoke-WebRequest "http://192.168.0.98:8888/populate/$_.ps1" -OutFile "C:\LabScripts\populate\$_.ps1"
}
```

---

### Etape 3 — Installer les services (dans la VM)

```powershell
C:\LabScripts\03_Install-Services.ps1
```

**Duree** : 15-30 minutes

| Service | Details |
|---------|---------|
| ADCS (PKI) | CA Enterprise Root `LAB-ROOT-CA` (4096 bits, SHA256, 10 ans) + Web Enrollment |
| IIS | Web Server + ASP.NET + FTP + site `LabIntranet` (port 8080) |
| File Server | DFS + Resource Manager + 5 partages |
| NPS/RADIUS | Network Policy Server |
| AD FS | Federation Services (SSO) |
| AD LDS | Lightweight Directory Services |
| RDS | Remote Desktop + Licensing + Web Access + Gateway |
| Print, Backup, SNMP, IPAM, WDS, BitLocker, SMTP, Telnet, RSAT | ... |

---

### Etape 4 — Peupler l'AD (dans la VM)

```powershell
C:\LabScripts\04_Populate-AD.ps1
```

L'orchestrateur appelle **13 sous-scripts** dans `populate/` :

| Script | Contenu | Anomalies |
|--------|---------|-----------|
| `04a_Create-OUs` | 20+ OUs hierarchiques | OUs sans protection, OUs vides/stale |
| `04b_Create-Groups` | 40+ groupes (securite/distribution) | Groupes stale, creds dans descriptions |
| `04c_Create-Users` | 80+ utilisateurs par departement | AS-REP Roast, pwd in desc, wrong OU, PasswordNotRequired |
| `04d_Create-Services` | 15 services normaux + 20 vulns | Kerberoasting (8 SPNs), delegation, DCSync, pwd=username |
| `04e_Create-Admins` | 3 admins legit + 10 vulns | 12+ DA, ex-employes, DA kerberoastable, pwd in desc |
| `04f_Create-Partners` | 8 partenaires + 10 generiques | Ext in DA, no expiration, shared accounts |
| `04g_Create-Computers` | 15 serveurs + 20 postes + 9 legacy | Unconstrained delegation, legacy OS, RBCD, stale |
| `04h_Set-ACLs` | ACLs + nested groups | 7 attack paths BloodHound, DCSync, AdminSDHolder |
| `04i_Set-GPOs` | 11 GPOs normales + 20 vulns | LLMNR, WDigest, SMB signing off, AlwaysInstallElevated |
| `04j_Set-DomainConfig` | Config domaine | Null sessions, SMBv1, PrintNightmare, RODC PRP |
| `04k_Set-PasswordPolicies` | 2 PSOs normales + 5 vulns | 1 char min, reversible, no lockout |
| `04l_Set-ADCS-Vulns` | Templates PKI vulns | ESC1 (x2), ESC2, ESC3, ESC4, ESC6, ESC8 |
| `04m_Set-CollectorTargets` | Objets pour collecteurs | AADConnect, gMSA, GPP, Exchange, SharePoint, ADFS... |

---

### Etape 5 — RODC + Trust (sur l'hote)

```powershell
.\05_Deploy-SecondDC.ps1 -ISOPath "C:\chemin\vers\server2022.iso"
```

Ce script cree 2 VMs et genere 4 scripts dans `C:\HyperV\setup-scripts\` :

| Etape | Script | Ou l'executer |
|-------|--------|---------------|
| 5a | `A2_Install-RODC.ps1` | Dans DC02-LAB |
| 5b | `B2_Install-PartnerForest.ps1` | Dans DC-PARTNER |
| 5c | `B3_PostConfig-Partner.ps1` | Dans DC-PARTNER |
| 5d | `B4_Setup-Trust-Vulns.ps1` | Sur DC01 |

**Anomalies RODC** : Domain Admins dans Allowed PRP (hash exposes si RODC compromis)

**Anomalies Trust** : SID Filtering OFF, TGT Delegation ON, chiffrement RC4 only (pas AES)

---

## Credentials

| Compte | Mot de passe | Usage |
|--------|-------------|-------|
| `Administrator` | `Cim22091956!!??` | Admin local / DSRM |
| `LAB\Administrator` | `Cim22091956!!??` | Admin domaine |
| Tous les users | `Cim22091956!!??` | Mot de passe par defaut |
| Comptes `adm.*` | `Adm1n!Cim22091956!!??` | Comptes admin |
| Comptes faibles | `Password1` | Services legacy, partenaires, admins vulns |

---

## Couverture des collecteurs (42/42)

| Collecteur | Anomalie | Script source |
|---|---|---|
| `Collect-AADConnect` | MSOL_* DCSync + AZUREADSSOACC Silver Ticket | 04m |
| `Collect-ADAttackSurface` | Kerberoasting, AS-REP, Unconstrained delegation | 04c/04d |
| `Collect-ADCS` | ESC1-ESC8, CA permissions | 04l |
| `Collect-ADCompleteTaxonomy` | Taxonomie complete (toujours des donnees) | 04a-04m |
| `Collect-ADFSConfig` | DKM container + SPN host/adfs* + Read Domain Users | 04m |
| `Collect-ADHygieneMetrics` | Stale users/computers (90+ days) | 04c/04g |
| `Collect-ADObjectsSecurityAttributes` | UAC flags (PwdNotReq, DES, delegation) | 04c/04d/04e |
| `Collect-DCHardening` | Print Spooler running + RDP sans NLA | 04j |
| `Collect-DCLogonRights` | User rights sur DCs | 04m (GPO) |
| `Collect-DCOwnership` | Owner DC != DA/EA | 04m |
| `Collect-DCRegistry` | Registry ACLs sur DCs | 04j |
| `Collect-DCRegistryKey` | LDAP signing OFF, LM hash, SMB signing | 04j |
| `Collect-Delegations` | ACLs dangereuses sur OUs | 04h |
| `Collect-DHCPConfig` | DHCP Administrators peuple | 04m |
| `Collect-DisplaySpecifier` | adminContextMenu UNC backdoor | 04m |
| `Collect-DnsAdminsMembers` | DnsAdmins avec membres | 04j |
| `Collect-DNSConfig` | Zone transfer Any, WPAD, GQBL vide | 04j |
| `Collect-DsHeuristics` | Anonymous NSPI + SDProp exclusion | 04m |
| `Collect-ExchangeConfig` | Groupes RBAC + Shared Permissions WriteDacl | 04m |
| `Collect-GMSADelegation` | gMSA avec GenericAll/WriteDACL non-admin | 04m |
| `Collect-GPOAuditOwnership` | GPO audit avec owner non-standard | 04m |
| `Collect-GPOAuditSettings` | 6/9 categories audit a 0 | 04m |
| `Collect-GPOSettings` | LM Hash, min 7 chars, no lockout | 04m |
| `Collect-GPOUserRights` | SeDebug/SeLoadDriver a Authenticated Users | 04m |
| `Collect-GPPPasswords` | cpassword dans Groups.xml + ScheduledTasks.xml | 04m |
| `Collect-KerberosPreAuth` | AS-REP Roastable (8+ comptes) | 04c/04d/04e |
| `Collect-KrbtgtPasswordAge` | krbtgt jamais change | 04j |
| `Collect-LAPSStatus` | LAPS non deploye | 04g |
| `Collect-PasswordNeverExpiresCount` | DA avec PasswordNeverExpires | 04e |
| `Collect-PasswordNotRequiredCount` | DA avec PASSWD_NOTREQD | 04m |
| `Collect-PreCreatedComputerCount` | Computers avec pwdLastSet=0 | 04g |
| `Collect-PrivilegedAdminCount` | 12+ Domain Admins | 04e |
| `Collect-ProtectedUsersAllowedList` | Membres avec delegation (conflit) | 04m |
| `Collect-RecycleBinStatus` | AD Recycle Bin OFF | 04j |
| `Collect-RODCConfig` | DA dans Allowed PRP | B4 (step 5d) |
| `Collect-SchemaAdminsMembers` | Schema Admins non-vide | 04h |
| `Collect-SharePointConfig` | SCP + Farm Admins (DA dedans) | 04m |
| `Collect-SIDHistory` | sIDHistory cross-domain sur 2 comptes | 04m |
| `Collect-SysvolPermissions` | SYSVOL writable par Domain Users | 04m |
| `Collect-Trusts` | SID Filtering OFF, TGT Delegation, RC4 only | B4 (step 5d) |
| `Collect-UnixPasswordCount` | unixUserPassword sur 4 comptes | 04m |

---

## Scripts utilitaires

| Script | Ou | Usage |
|--------|----|-------|
| `diag.ps1` | Hote | Diagnostic VM (ISO, DVD, boot, firmware, reseau) |
| `fix_boot.ps1` | Hote | Corrige l'ordre de boot (DVD en premier) |
| `rebuild.ps1` | Hote | Reconstruction complete de la VM DC01 |
| `05_Fix-Network.ps1` | Hote | Corrige le reseau (VLAN, switch, connectivite) |
| `06_Install-Claude-Code.ps1` | VM | Installe Node.js + Git + Claude Code CLI |

---

## Depannage

### La VM n'a pas internet
```powershell
# Sur l'hote
.\05_Fix-Network.ps1
# Ou manuellement :
Set-VMNetworkAdapterVlan -VMName DC01-LAB -Untagged
```

### La VM ne boote pas sur l'ISO
```powershell
.\fix_boot.ps1 -ISOPath "C:\chemin\vers\server2022.iso"
```

### Reconstruire from scratch
```powershell
.\rebuild.ps1 -ISOPath "C:\chemin\vers\server2022.iso"
```

### Le partage SMB hote → VM ne fonctionne pas
Utiliser un serveur HTTP Python :
```powershell
# Hote
python -m http.server 8888 --bind 192.168.0.98 --directory C:\chemin\vers\ad_lab
```

---

## Fichiers du kit

```
ad_lab/
├── README.md                       # Vue d'ensemble
├── GUIDE_INSTALLATION.md           # Ce fichier (guide detaille)
├── DEPLOY.bat                      # Menu de lancement
│
├── 01_Create-VM.ps1                # [HOTE] Creation VM Hyper-V
├── 02_Install-ADDS.ps1             # [VM]   AD DS + DNS + DHCP
├── 03_Install-Services.ps1         # [VM]   15+ services Windows
├── 04_Populate-AD.ps1              # [VM]   Orchestrateur population AD
├── 05_Deploy-SecondDC.ps1          # [HOTE] VMs RODC + partner.local
├── 05_Fix-Network.ps1              # [HOTE] Fix reseau / VLAN
├── 06_Install-Claude-Code.ps1      # [VM]   Claude Code CLI
│
├── populate/                       # Sous-scripts population AD
│   ├── 04a_Create-OUs.ps1         #   Structure OUs
│   ├── 04b_Create-Groups.ps1      #   Groupes securite/distribution
│   ├── 04c_Create-Users.ps1       #   80+ utilisateurs
│   ├── 04d_Create-Services.ps1    #   Comptes de service + vulns
│   ├── 04e_Create-Admins.ps1      #   Comptes admin + vulns
│   ├── 04f_Create-Partners.ps1    #   Partenaires + generiques
│   ├── 04g_Create-Computers.ps1   #   Objets ordinateur + legacy
│   ├── 04h_Set-ACLs.ps1           #   ACLs dangereuses + nested groups
│   ├── 04i_Set-GPOs.ps1           #   GPOs normales + vulnerables
│   ├── 04j_Set-DomainConfig.ps1   #   Config domaine dangereuses
│   ├── 04k_Set-PasswordPolicies.ps1 # Fine-Grained Password Policies
│   ├── 04l_Set-ADCS-Vulns.ps1     #   Vulnerabilites ADCS (ESC1-8)
│   └── 04m_Set-CollectorTargets.ps1 # Objets pour collecteurs LIA-Scan
│
├── run_in_vm.ps1                   # [HOTE] Deploiement auto (PowerShell Direct)
├── diag.ps1                        # [HOTE] Diagnostic VM
├── fix_boot.ps1                    # [HOTE] Fix boot DVD
└── rebuild.ps1                     # [HOTE] Rebuild complet VM
```

## Installation Claude Code dans la VM

```powershell
# Dans la VM, apres deploiement complet
.\06_Install-Claude-Code.ps1
# Ou manuellement :
# 1. Installer Node.js LTS + Git
# 2. npm install -g @anthropic-ai/claude-code
# 3. claude
```

> Necessite Git Bash. Si non detecte : `$env:CLAUDE_CODE_GIT_BASH_PATH = "C:\Program Files\Git\bin\bash.exe"`
