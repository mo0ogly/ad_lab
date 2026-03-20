# AD Lab

**Laboratoire Active Directory volontairement vulnerable**, deployable automatiquement sur Hyper-V.

Concu pour tester et valider les outils d'audit de securite AD :
[PingCastle](https://www.pingcastle.com/) · [ANSSI ADS](https://www.cert.ssi.gouv.fr/actualite/CERTFR-2020-ACT-011/) · [BloodHound](https://bloodhound.specterops.io/) · [LIA-Scan](https://github.com/)

> **AVERTISSEMENT** — Ce lab est **volontairement vulnerable**. Il contient des mots de passe
> faibles, des ACLs dangereuses, des backdoors et des configurations non securisees.
> **Ne jamais deployer en production ni sur un reseau non isole.**

---

## Sommaire

- [Fonctionnalites](#fonctionnalites)
- [Pre-requis](#pre-requis)
- [Installation rapide](#installation-rapide)
- [Installation detaillee](#installation-detaillee)
- [Architecture](#architecture)
- [Anomalies injectees](#anomalies-injectees)
- [Couverture des collecteurs](#couverture-des-collecteurs)
- [Structure du projet](#structure-du-projet)
- [Credentials](#credentials)
- [Depannage](#depannage)
- [Licence](#licence)

---

## Fonctionnalites

| Element | Detail |
|---------|--------|
| **Domaines** | `lab.local` + `partner.local` (trust bidirectionnel) |
| **3 VMs Hyper-V** | DC01 (DC + CA), DC02 (RODC), DC-PARTNER (2e foret) |
| **80+ utilisateurs** | 12 departements, comptes admin, service, partenaires |
| **40+ groupes** | Securite, distribution, ACL, nested cascades BloodHound |
| **30+ GPOs** | 11 normales + 20 vulnerables |
| **90+ anomalies** | Couvrant **60 collecteurs** de securite |
| **15+ services** | ADCS (PKI), IIS, DFS, NPS, ADFS, RDS, DHCP, DNS, SMTP... |
| **Deploiement** | Automatise via PowerShell Direct — ~45 min |

---

## Pre-requis

| Composant | Minimum | Recommande |
|-----------|---------|------------|
| **OS hote** | Windows 10/11 Pro | Windows 11 Pro for Workstations |
| **Hyper-V** | Active | Active |
| **RAM** | 8 Go (DC01 seul) | 12 Go (3 VMs) |
| **Disque** | 100 Go | 200 Go |
| **CPU** | 4 coeurs | 8 coeurs |
| **ISO** | Windows Server 2022 Eval | [Telecharger](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022) |
| **PowerShell** | 5.1+ | 5.1+ |
| **LAPS** | Optionnel | [Telecharger](https://www.microsoft.com/en-us/download/details.aspx?id=46899) |
| **Collecteurs** | `E:\ad.zip` | 60 scripts LIA-Scan |

---

## Installation rapide

### Infrastructure principale (DC01 — 1 VM)

```powershell
# 1. Ouvrir PowerShell en Administrateur sur l'hote Windows

# 2. Creer la VM Hyper-V
.\01_Create-VM.ps1 -ISOPath "D:\ISOs\server2022.iso"

# 3. Dans la console Hyper-V :
#    - Installer Windows Server 2022 Desktop Experience
#    - Mot de passe Administrator : (voir config.ps1)

# 4. Deployer le lab automatiquement (copie + execute les scripts dans la VM)
.\run_in_vm.ps1
```

Le lab est operationnel. DC01 contient un AD complet avec 90+ anomalies.

### Deployer et executer les collecteurs

```powershell
# Copie les 60 collecteurs de E:\ad.zip vers C:\Share\collectors\ sur la VM
# Applique automatiquement les correctifs (cles dupliquees, filtres, etc.)
.\deploy_collectors.ps1

# Menu interactif — choisir le mode d'execution :
#   1. COMPLET    — 60 collecteurs (production, necessite des machines jointes)
#   2. AD SEUL    — exclut scans remote (recommande pour le lab)
#   3. RAPIDE     — AD seul + exclut les collecteurs lourds (test)
.\run_collectors.ps1
```

Le script `deploy_collectors.ps1` extrait le zip, applique les corrections
(`fix_collectors.ps1`), puis envoie chaque `.ps1` dans la VM via PowerShell Direct.

Le script `run_collectors.ps1` affiche un menu avec 3 modes :
- **Mode 1 — COMPLET** : tous les 60 collecteurs. Necessite des machines jointes
  au domaine accessibles en WMI/RPC (production).
- **Mode 2 — AD UNIQUEMENT** (recommande pour le lab) : exclut les 9 collecteurs
  qui scannent des machines distantes (Antivirus, LocalAdmins, Spooler, Registry...).
- **Mode 3 — RAPIDE** : mode 2 + exclut les collecteurs lourds (ADCompleteTaxonomy, ADAcls).

Les resultats sont exportes dans `C:\Share\collectors_results.csv`.

> **Note** : LAPS doit etre installe sur le DC pour que `Collect-ADLapsBitLocker`
> fonctionne. Sans LAPS, le schema AD ne contient pas l'attribut `ms-Mcs-AdmPwdExpirationTime`.

### Infrastructure avancee (RODC + Trust — 3 VMs)

```powershell
# 5. Creer les VMs supplementaires (sur l'hote)
.\05_Deploy-SecondDC.ps1 -ISOPath "D:\ISOs\server2022.iso"

# 6. Installer Windows Server dans chaque VM, puis executer :
#    - Dans DC02-LAB   : C:\HyperV\setup-scripts\A2_Install-RODC.ps1
#    - Dans DC-PARTNER : C:\HyperV\setup-scripts\B2_Install-PartnerForest.ps1
#    - Dans DC-PARTNER : C:\HyperV\setup-scripts\B3_PostConfig-Partner.ps1

# 7. Sur DC01, etablir le trust + injecter les anomalies
#    C:\HyperV\setup-scripts\B4_Setup-Trust-Vulns.ps1
```

---

## Installation detaillee

### Etape 1 — Creer la VM (sur l'hote)

```powershell
.\01_Create-VM.ps1 -ISOPath "D:\ISOs\server2022.iso"
```

Le script :
- Active Hyper-V si necessaire (reboot de l'hote requis la premiere fois)
- Cree un vSwitch **External** `LabSwitch` lie a votre carte reseau physique
- Cree la VM `DC01-LAB` : Generation 2, 4 vCPU, 4 Go RAM dynamique, 80 Go VHDX
- Monte l'ISO et configure le boot sur DVD

**Apres execution** : la console Hyper-V s'ouvre. Appuyez vite sur une touche pour booter
sur le DVD, puis installez Windows Server 2022 **Desktop Experience**.
Mot de passe Administrator : `(voir config.ps1)`

### Etape 2 — Deploiement automatique (sur l'hote)

```powershell
.\run_in_vm.ps1
```

Ce script utilise PowerShell Direct pour copier et executer tout dans la VM :

| Phase | Script | Duree | Detail |
|-------|--------|-------|--------|
| Copie | — | ~1 min | 3 scripts principaux + 13 sous-scripts `populate/` |
| AD DS | `02_Install-ADDS.ps1` | ~10 min | IP statique, renommage DC01, promotion DC, DNS, DHCP |
| Services | `03_Install-Services.ps1` | ~20 min | ADCS, IIS, DFS, NPS, ADFS, RDS, SMTP, etc. |
| Population | `04_Populate-AD.ps1` | ~5 min | 13 sous-scripts : OUs, users, groupes, GPOs, ACLs, vulns |

> **Note** : Le script vous demandera d'appuyer sur Entree apres le redemarrage
> intermediaire du DC (promotion AD DS).

### Etape 2 alternative — Installation manuelle (dans la VM)

Si PowerShell Direct ne fonctionne pas, transferez les scripts manuellement.

**Methode 1 — Partage SMB** (recommandee) :

```powershell
# Sur l'hote (PowerShell Admin) — cree le share et copie les fichiers dans la VM
.\setup_share2.ps1
```

Le script :
- Desactive le firewall de la VM
- Cree un partage `\\192.168.0.10\Share` (Everyone FullAccess)
- Copie tous les scripts dans `C:\Share\ad_lab\` via PowerShell Direct

Les scripts sont ensuite accessibles :
- Depuis la VM : `C:\Share\ad_lab\`
- Depuis l'hote : `\\192.168.0.10\Share\ad_lab\`

```powershell
# Dans la VM — executer les scripts depuis le share
C:\Share\ad_lab\02_Install-ADDS.ps1        # relancer apres chaque reboot
C:\Share\ad_lab\03_Install-Services.ps1
C:\Share\ad_lab\04_Populate-AD.ps1
```

**Methode 2 — Serveur HTTP** :
```powershell
# Sur l'hote — demarrer un serveur HTTP temporaire
python -m http.server 8888 --bind 192.168.0.98 --directory C:\chemin\vers\ad_lab
```

```powershell
# Dans la VM — telecharger tous les scripts
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

Puis executez dans l'ordre :
```powershell
C:\LabScripts\02_Install-ADDS.ps1        # relancer apres chaque reboot
C:\LabScripts\03_Install-Services.ps1
C:\LabScripts\04_Populate-AD.ps1
```

### Etape 3 — RODC + Trust (optionnel, sur l'hote)

```powershell
.\05_Deploy-SecondDC.ps1 -ISOPath "D:\ISOs\server2022.iso"
```

Cree 2 VMs supplementaires et genere les scripts d'installation dans `C:\HyperV\setup-scripts\` :

| Ordre | Script | Ou l'executer | Ce qu'il fait |
|-------|--------|---------------|---------------|
| 1 | `A2_Install-RODC.ps1` | DC02-LAB | IP statique, promotion RODC dans lab.local |
| 2 | `B2_Install-PartnerForest.ps1` | DC-PARTNER | Cree la foret partner.local |
| 3 | `B3_PostConfig-Partner.ps1` | DC-PARTNER | DNS conditionnel + utilisateurs |
| 4 | `B4_Setup-Trust-Vulns.ps1` | DC01 | Trust bidirectionnel + 4 anomalies |

---

## Architecture

```
Internet
    |
[Routeur / Box — 192.168.0.1]
    |
[LabSwitch — External vSwitch Hyper-V]
    |
    +--- DC01-LAB    192.168.0.10    lab.local        DC + CA + 15 services
    |    4 vCPU / 4 Go RAM / 80 Go
    |
    +--- DC02-LAB    192.168.0.11    lab.local        RODC (Read-Only DC)
    |    2 vCPU / 2 Go RAM / 60 Go
    |
    +--- DC-PARTNER  192.168.0.12    partner.local    2e foret + trust
         2 vCPU / 2 Go RAM / 60 Go
```

**Trust** : bidirectionnel entre `lab.local` et `partner.local` (External Trust,
volontairement misconfigure : SID Filtering OFF, TGT Delegation ON, RC4 only).

---

## Anomalies injectees

### Vue d'ensemble (90+)

| Categorie | Nb | Exemples |
|-----------|----|----------|
| **Kerberos / Auth** | 15+ | Kerberoasting (8 SPNs), AS-REP Roast (8 comptes), DES/RC4 only, NTLMv1, WDigest |
| **ACLs / Delegation** | 15+ | DCSync (2), WriteDACL, GenericAll, WriteOwner, AdminSDHolder, Unconstrained/Constrained/RBCD |
| **Groupes / Cascade** | 10+ | 7 chaines BloodHound vers DA, circular groups, distribution→security |
| **Comptes** | 15+ | 12+ DA, ex-employes, pwd in description, PASSWD_NOTREQD, shadow admins |
| **GPOs** | 20 | LLMNR, WPAD, WDigest, AlwaysInstallElevated, UAC OFF, PS logging OFF, Defender OFF |
| **PKI / ADCS** | 8 | ESC1 (x2), ESC2, ESC3, ESC4, ESC6, ESC8, exportable keys |
| **Reseau / DNS** | 10+ | Null sessions, SMBv1, PrintNightmare, WPAD DNS, zone transfer, GQBL vide |
| **Config domaine** | 10+ | LDAP signing OFF, MachineAccountQuota=10, Guest ON, Recycle Bin OFF |
| **Password policies** | 7 | 5 PSOs vulns (1 char min, reversible, no lockout), LM hash storage |
| **Trust** | 3 | SID Filtering OFF, TGT Delegation, RC4 only (pas AES) |
| **RODC** | 1 | Domain Admins dans Allowed Password Replication |

### Detail par script

| Script | Anomalies |
|--------|-----------|
| `04c_Create-Users` | AS-REP Roast (3), pwd in description (3), wrong OU, PasswordNotRequired, Kerberoastable user |
| `04d_Create-Services` | Kerberoasting (8), AS-REP (5), pwd=username (3), service in DA, DCSync, delegation (5 types) |
| `04e_Create-Admins` | 12+ DA, ex-employes, DA kerberoastable, disabled in DA, pwd in description, DES only |
| `04f_Create-Partners` | External in DA, no expiration, shared/generic accounts |
| `04g_Create-Computers` | Unconstrained delegation (3), legacy OS (9), stale machines, RBCD, duplicate SPN |
| `04h_Set-ACLs` | 7 nested group paths, DCSync, AdminSDHolder backdoor, GenericWrite on DA group |
| `04i_Set-GPOs` | 20 GPOs vulnerables + 2 scheduled tasks backdoor |
| `04j_Set-DomainConfig` | SMBv1, PrintNightmare, null sessions, SNMP public/private, weak crypto |
| `04k_Set-PasswordPolicies` | 5 PSOs vulns + LM hash storage |
| `04l_Set-ADCS-Vulns` | ESC1-ESC8, exportable keys, 10-year certs |
| `04m_Set-CollectorTargets` | AADConnect, gMSA, GPP passwords, Exchange, SharePoint, ADFS, dSHeuristics, DisplaySpecifier |

---

## Couverture des collecteurs

**60 collecteurs** — chaque collecteur AD trouvera au moins une anomalie.
Les 9 collecteurs de scan remote (WMI/Registry) necessitent des machines jointes au domaine.

<details>
<summary>Tableau complet collecteur → anomalie → script source</summary>

| Collecteur | Anomalie detectee | Script |
|---|---|---|
| `Collect-AADConnect` | MSOL_* DCSync + AZUREADSSOACC Silver Ticket | 04m |
| `Collect-ADAttackSurface` | Kerberoasting, AS-REP, Unconstrained delegation | 04c/04d |
| `Collect-ADCS` | ESC1-ESC8, CA permissions | 04l |
| `Collect-ADCompleteTaxonomy` | Taxonomie complete | 04a-04m |
| `Collect-ADFSConfig` | DKM container + GenericRead Domain Users | 04m |
| `Collect-ADHygieneMetrics` | Stale users/computers (90+ days) | 04c/04g |
| `Collect-ADObjectsSecurityAttributes` | UAC flags dangereux | 04c/04d/04e |
| `Collect-DCHardening` | Print Spooler running + RDP sans NLA | 04j |
| `Collect-DCLogonRights` | Privileges dangereux sur DCs | 04m |
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
| `Collect-GMSADelegation` | gMSA avec GenericAll/WriteDACL | 04m |
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
| `Collect-ProtectedUsersAllowedList` | Membres avec delegation | 04m |
| `Collect-RecycleBinStatus` | AD Recycle Bin OFF | 04j |
| `Collect-RODCConfig` | DA dans Allowed PRP | B4 |
| `Collect-SchemaAdminsMembers` | Schema Admins non-vide | 04h |
| `Collect-SharePointConfig` | SCP + Farm Admins avec DA | 04m |
| `Collect-SIDHistory` | sIDHistory cross-domain | 04m |
| `Collect-SysvolPermissions` | SYSVOL writable par Domain Users | 04m |
| `Collect-Trusts` | SID Filtering OFF, TGT Delegation, RC4 | B4 |
| `Collect-UnixPasswordCount` | unixUserPassword sur 4 comptes | 04m |

</details>

---

## Structure du projet

```
ad_lab/
│
├── README.md                          # Ce fichier
├── GUIDE_INSTALLATION.md              # Guide technique detaille
├── DEPLOY.bat                         # Menu de lancement rapide
├── LICENSE                            # MIT License
├── VERSION                            # Version courante
│
│   --- Scripts principaux ---
│
├── 01_Create-VM.ps1                   # [HOTE]  Creer VM Hyper-V
├── 02_Install-ADDS.ps1                # [VM]    AD DS + DNS + DHCP + promotion DC
├── 03_Install-Services.ps1            # [VM]    15+ services Windows
├── 04_Populate-AD.ps1                 # [VM]    Orchestrateur → populate/04a-04m
├── 05_Deploy-SecondDC.ps1             # [HOTE]  VMs RODC + partner.local + trust
├── 05_Fix-Network.ps1                 # [HOTE]  Fix reseau / VLAN
├── 06_Install-Claude-Code.ps1         # [VM]    Claude Code CLI (optionnel)
│
│   --- Sous-scripts de population ---
│
├── populate/
│   ├── 04a_Create-OUs.ps1            # Structure organisationnelle (20+ OUs)
│   ├── 04b_Create-Groups.ps1         # Groupes securite/distribution (40+)
│   ├── 04c_Create-Users.ps1          # Utilisateurs par departement (80+)
│   ├── 04d_Create-Services.ps1       # Comptes de service + vulns Kerberos
│   ├── 04e_Create-Admins.ps1         # Comptes admin + vulns privileges
│   ├── 04f_Create-Partners.ps1       # Partenaires + comptes generiques
│   ├── 04g_Create-Computers.ps1      # Serveurs + postes + legacy OS
│   ├── 04h_Set-ACLs.ps1              # ACLs dangereuses + nested groups
│   ├── 04i_Set-GPOs.ps1              # GPOs normales + 20 vulnerables
│   ├── 04j_Set-DomainConfig.ps1      # Config domaine dangereuses
│   ├── 04k_Set-PasswordPolicies.ps1  # Fine-Grained Password Policies
│   ├── 04l_Set-ADCS-Vulns.ps1        # Certificats ADCS (ESC1-ESC8)
│   └── 04m_Set-CollectorTargets.ps1  # Objets pour collecteurs LIA-Scan
│
│   --- Utilitaires ---
│
├── run_in_vm.ps1                      # [HOTE]  Deploiement auto PowerShell Direct
├── deploy_collectors.ps1              # [HOTE]  Copie + corrige les collecteurs dans la VM
├── run_collectors.ps1                 # [HOTE]  Execute tous les collecteurs + resume
├── fix_collectors.ps1                 # [HOTE]  Correctifs des bugs collecteurs
├── setup_share2.ps1                   # [HOTE]  Cree share SMB + copie scripts dans VM
├── config.ps1                         # [LOCAL] Mot de passe (gitignored)
├── config.example.ps1                 # Template pour config.ps1
├── .gitignore                         # Exclut config.ps1
├── diag.ps1                           # [HOTE]  Diagnostic VM
├── fix_boot.ps1                       # [HOTE]  Fix boot DVD
├── fix_missing_objects.ps1            # [HOTE]  Cree les objets AD manquants
└── rebuild.ps1                        # [HOTE]  Reconstruction complete VM
```

---

## Credentials

| Compte | Mot de passe | Usage |
|--------|-------------|-------|
| `Administrator` | `(voir config.ps1)` | Admin local / DSRM |
| `LAB\Administrator` | `(voir config.ps1)` | Admin domaine |
| Tous les users standard | `(voir config.ps1)` | Mot de passe par defaut |
| Comptes `adm.*` | `Adm1n!(voir config.ps1)` | Comptes admin |
| Comptes faibles | `Password1` | Services legacy, partenaires |
| `PARTNER\Administrator` | `(voir config.ps1)` | Admin partner.local |

---

## Depannage

| Probleme | Solution |
|----------|----------|
| La VM n'a pas internet | `.\05_Fix-Network.ps1` ou `Set-VMNetworkAdapterVlan -VMName DC01-LAB -Untagged` |
| La VM ne boote pas sur l'ISO | `.\fix_boot.ps1 -ISOPath "D:\ISOs\server2022.iso"` |
| Reconstruction complete | `.\rebuild.ps1 -ISOPath "D:\ISOs\server2022.iso"` |
| PowerShell Direct ne marche pas | Transfert HTTP (voir [Installation detaillee](#etape-2-alternative--installation-manuelle-dans-la-vm)) |
| Script 02 demande plusieurs reboots | Normal — relancer apres chaque reboot (2-3 fois) |

---

## Contribuer

Les contributions sont les bienvenues. Pour ajouter de nouvelles anomalies :

1. Identifier le collecteur cible
2. Ajouter les objets AD dans le sous-script `populate/` correspondant
3. Documenter l'anomalie dans ce README (tableau couverture)
4. Tester avec le collecteur concerne

---

## Licence

Ce projet est distribue sous licence **MIT**. Voir le fichier [LICENSE](LICENSE).

```
Copyright (c) 2026 pizzif

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Version

Voir [VERSION](VERSION) — version courante : **1.0.0**
