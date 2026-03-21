# TRACKING: Réassignation des collectors ADDS

**Date création:** 2026-03-20
**Objectif:** Réassigner 298 rules de Collect-ADCompleteTaxonomy.ps1 vers les collectors spécialisés
**Repo rules:** lia-security-platform-v2/lia_rules/rule_analysis/ADDS/
**Repo collectors:** lia-security-platform-v2/scripts/collect/active_directory/

## Statut global
- [x] Phase 1: Construire la table de mapping pattern → ObjectClass → collector
- [ ] Phase 2: Réassigner les YAML (batch par groupe) — 299 rules
- [ ] Phase 3: Identifier les collectors MANQUANTS à créer — 43 rules sans collector + 31 UNKNOWN
- [ ] Phase 4: Vérifier avec lia-test (405/405 PASS)
- [ ] Phase 5: Commit + push

## Audit complet (fichier CSV)
Voir `ad_lab/reassign_audit.csv` — format: rule_id|current_script|pattern|objectclass|proposed_script|confidence

### Résumé de l'audit (299 rules)
| Nouveau collector proposé | Rules | Confidence |
|--------------------------|-------|------------|
| Collect-ADObjectsSecurityAttributes.ps1 | 103 | MEDIUM (ObjectClass user/computer → adapter) |
| Collect-GPOSettings.ps1 | 55 | MEDIUM (multiples ObjectClasses GPO) |
| NEED_NEW_COLLECTOR | 43 | LOW (domain_config:18, domain:8, group:6, domainDNS:4, etc.) |
| UNKNOWN | 31 | LOW (ObjectClasses rares/vides) |
| Collect-ADCS.ps1 | 26 | MEDIUM (trusted_certificate → adcs_authority) |
| Collect-Trusts.ps1 | 12 | HIGH (trustedDomain/trust) |
| Collect-ADUptimeAndVersion.ps1 | 8 | MEDIUM (domain_controller) |
| Collect-Delegations.ps1 | 7 | HIGH (delegation) |
| Collect-GPOAuditSettings.ps1 | 4 | HIGH (audit) |
| Collect-GPOUserRights.ps1 | 3 | HIGH (privilege) |
| Collect-DsHeuristics.ps1 | 2 | HIGH |
| Collect-DNSConfig.ps1 | 2 | HIGH |
| Collect-GPPPasswords.ps1 | 1 | HIGH |
| Collect-DisplaySpecifier.ps1 | 1 | HIGH |
| Collect-ADReplication.ps1 | 1 | MEDIUM |

### Collectors manquants à créer (43 rules)
| ObjectClass manquant | Rules | Proposition |
|---------------------|-------|-------------|
| domain_config | 18 | Nouveau: Collect-DomainConfig.ps1 |
| domain | 8 | Nouveau: Collect-DomainConfig.ps1 (meme) |
| group | 6 | Nouveau: Collect-ADGroups.ps1 |
| domainDNS | 4 | Nouveau: Collect-DomainConfig.ps1 (meme) |
| forest_functional_level | 3 | Nouveau: Collect-DomainConfig.ps1 (meme) |
| organizationalUnit | 2 | Nouveau: Collect-ADOUs.ps1 |
| schema_class_vulnerable | 1 | Nouveau: Collect-SchemaVulnClasses.ps1 |
| control_path | 1 | Enrichir Collect-Delegations.ps1 |

---

## GROUPE 1: *_DATA_Computers.xml (70 rules) — ObjectClass: computer
**Collector:** Collect-ADObjectsSecurityAttributes.ps1 (ObjectClass: ad_computer_security)
**Problème:** ObjectClass mismatch (computer vs ad_computer_security)
**Action:** Le collector produit ad_computer_security mais les rules attendent "computer"
**Décision:** [ ] Adapter le collector pour aussi produire ObjectClass=computer
             [ ] OU adapter les 70 rules pour utiliser ad_computer_security
**Statut:** ⬜ TODO

## GROUPE 2: *_DATA_GPO.xml (64 rules) — ObjectClass variés
ObjectClasses dans les rules:
- gpo_lsa_policy (13)
- groupPolicyContainer (11)
- gpo_hardened_path (8)
- gpo_policy (3)
- gpo_wsus (3)
- gpo_defender_asr (3)
- defender_asr_rule (3)
- advanced_audit_policy (3)
- gpo_privilege (2)
- registry_value (2)
- et 12 autres (1 chacun): gpo_user_rights, gpo_password_policy, gpo_audit_policy, etc.

**Collectors existants:**
- Collect-GPOSettings.ps1 (ObjectClass: gpo_setting)
- Collect-GPOAuditSettings.ps1 (ObjectClass: gpo_audit_simple, gpo_audit_advanced)
- Collect-GPOUserRights.ps1 (ObjectClass: gpo_privilege, gpo_privilege_summary)

**Problème:** Beaucoup d'ObjectClasses GPO ne matchent aucun collector existant
**Action:** Enrichir Collect-GPOSettings.ps1 pour couvrir tous les ObjectClasses GPO
**Statut:** ⬜ TODO

## GROUPE 3: *_DATA_Users.xml (41 rules) — ObjectClass: user
**Collector:** Collect-ADObjectsSecurityAttributes.ps1 (ObjectClass: ad_user_security)
**Problème:** ObjectClass mismatch (user vs ad_user_security)
**Action:** Même décision que GROUPE 1
**Statut:** ⬜ TODO

## GROUPE 4: CONFIGURATION_DATA_Directory Service.xml (38 rules) — ObjectClasses variés
ObjectClasses:
- domain_config (18)
- domain (7)
- forest_functional_level (3)
- domainDNS (3)
- ds_heuristics (2)
- domain_metadata (1), domain_aggregate (1), default_ou_redirect (1), domain} (2)

**Collectors existants:**
- Collect-DsHeuristics.ps1 (ObjectClass: dsheuristics_config) — pour ds_heuristics
- Collect-ADConsistency.ps1 — pas d'ObjectClass détecté

**Problème:** Pas de collector pour domain_config, domain, forest_functional_level
**Action:** Créer Collect-DirectoryServiceConfig.ps1 ou enrichir existant
**Statut:** ⬜ TODO

## GROUPE 5: CONFIGURATION_DATA_PKI Authorities.xml (21 rules) — ObjectClass: trusted_certificate
**Collector:** Collect-ADCS.ps1 (ObjectClass: adcs_authority, adcs_template, adcs_ntauth)
**Problème:** ObjectClass mismatch (trusted_certificate vs adcs_authority)
**Action:** Adapter
**Statut:** ⬜ TODO

## GROUPE 6: *_DATA_trustedDomain.xml (12 rules) — ObjectClass: trustedDomain/trust
**Collector:** Collect-Trusts.ps1 (ObjectClass: trust)
**Match partiel:** 4 rules ont ObjectClass=trust (OK), 6 ont trustedDomain, 2 ont trust_relationship
**Action:** Enrichir Collect-Trusts.ps1 pour aussi produire trustedDomain
**Statut:** ⬜ TODO

## GROUPE 7: *_DATA_Domain controllers.xml (11 rules) — ObjectClass: domain_controller/domaincontroller
**Collectors existants:**
- Collect-ADUptimeAndVersion.ps1
- Collect-ADSpooler.ps1
- Collect-DCHardening.ps1

**Action:** Identifier le bon collector par ObjectClass
**Statut:** ⬜ TODO

## GROUPE 8: *_ACL_*.xml (8 rules) — ObjectClass: delegation/control_path
**Collector:** Collect-Delegations.ps1 (ObjectClass: delegation)
**Action:** 7 rules=delegation (OK), 1=control_path (manquant)
**Statut:** ⬜ TODO

## GROUPE 9: *_DATA_Groups.xml (7 rules) — ObjectClass: group/dnsadmins_membership
**Collectors:**
- Collect-DnsAdminsMembers.ps1 (ObjectClass: dns_admins_membership) — 1 rule
- Collect-SchemaAdminsMembers.ps1 (ObjectClass: group_membership) — ??

**Problème:** 6 rules attendent ObjectClass=group, pas couvert par les collectors spécialisés
**Action:** Créer un collector pour les groupes standard (ou enrichir)
**Statut:** ⬜ TODO

## GROUPE 10: CONFIGURATION_DATA_PKI Templates.xml (5 rules)
**Collector:** Collect-ADCS.ps1 (ObjectClass: adcs_template)
**Statut:** ⬜ TODO

## GROUPE 11: Petits groupes (1-3 rules chacun)
| Pattern | Rules | ObjectClass | Collector potentiel |
|---------|-------|-------------|-------------------|
| CONFIGURATION_DATA_PKI Enrollment Services.xml | 2 | certificate_enrollment | Collect-ADCS.ps1 |
| *_DATA_DomainController.xml | 2 | computer | Collect-ADUptimeAndVersion.ps1 |
| *_DATA_Domain.xml | 2 | domain/domainDNS | ? |
| *_DATA_DNS zones*.xml | 2 | dns_zone | Collect-DNSConfig.ps1 |
| SCHEMA_DATA_Classes.xml | 1 | schema_class_vulnerable | ? |
| CONFIGURATION_DATA_nTDSConnection.xml | 1 | nTDSConnection | Collect-ADReplication.ps1 |
| CONFIGURATION_DATA_*.xml | 1 | display_specifier | Collect-DisplaySpecifier.ps1 |
| *_DATA_PasswordSettingsContainer.xml | 1 | msDS-PasswordSettings | ? |
| *_DATA_Partition_*.xml | 1 | crossRefContainer | ? |
| *_DATA_OrganizationalUnit.xml | 1 | organizationalUnit | ? |
| *_DATA_Organizational units.xml | 1 | organizationalUnit | ? |
| *_DATA_ManagedServiceAccount.xml | 1 | msDS-GroupManagedServiceAccount | Collect-GMSADelegation.ps1 |
| *_DATA_Forest.xml | 1 | crossRefContainer | ? |
| *_DATA_Directory Service.xml | 1 | nTDSService | ? |
| *_DATA_CertificateTemplates.xml | 1 | pKICertificateTemplate | Collect-ADCS.ps1 |
| *_DATA_*.xml | 3 | serviceConnectionPoint, msDFSR-Member, groupPolicyContainer | ? |

---

## Résumé des décisions à prendre

### Décision architecturale principale
Les 298 rules utilisent les ObjectClasses **natifs AD** (computer, user, group, domainDNS, etc.)
Les collectors spécialisés utilisent des ObjectClasses **customs** (ad_computer_security, ad_user_security, etc.)

**Option A:** Adapter les collectors pour produire les ObjectClasses natifs → 0 changement YAML
**Option B:** Adapter les 298 YAML pour utiliser les ObjectClasses custom → gros refactoring
**Option C:** Créer des collectors "bridge" qui produisent les ObjectClasses natifs attendus

### Collectors à créer (pas d'existant)
1. Collector pour ObjectClass=domain_config / domain / forest_functional_level (38 rules)
2. Collector pour ObjectClass=computer (natif AD, 70 rules)
3. Collector pour ObjectClass=user (natif AD, 41 rules)
4. Collector pour les nombreux ObjectClasses GPO (64 rules)

### Collectors existants réutilisables tel quel
- Collect-Delegations.ps1 → delegation (7 rules) ✅
- Collect-Trusts.ps1 → trust (4 rules) ✅
- Collect-DNSConfig.ps1 → dns_zone (2 rules) ✅
- Collect-DisplaySpecifier.ps1 → display_specifier (1 rule) ✅
- Collect-ADCS.ps1 → adcs_* (partiel) ✅

---

## Journal des actions
| Date | Action | Résultat |
|------|--------|---------|
| 2026-03-20 | Création du tracking | 298 rules identifiées, 26 patterns, 55 collectors existants |
| 2026-03-20 | Phase 2a: 28 HIGH confidence réassignées | 28/28 OK — lia-test 28/28 PASS |
| 2026-03-20 | Fix YAML duplicates (57 files, 79 blocs) | 4 rules trust avaient encore des duplicates |
| 2026-03-20 | Phase 2b: 103 ADObjectsSecurityAttributes | 103/103 OK (computer + user) |
| 2026-03-20 | Phase 2c: 60 GPO rules | 60/60 OK (GPOSettings/GPOAudit/GPOUserRights) |
| 2026-03-20 | Phase 2d: 86 remaining (ADCS, Trusts, DC, Domain, Groups, etc.) | 86/86 OK |
| 2026-03-20 | Phase 2e: 22 dernières (ObjectClass vide) | 22/22 OK |
| 2026-03-20 | **TOTAL: 0 refs ADCompleteTaxonomy dans collection_script** | 299/299 réassignées |
| 2026-03-20 | **Gate check lia-test 405 rules** | **405/405 PASS ✅ — 0 régression** |
