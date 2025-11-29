# 📚 Guide Complet - Installation Infrastructure KeyBuzz

**Date de dernière mise à jour** : 2025-11-23  
**État** : Modules 2-9 validés à 100% ✅  
**Prochaine étape** : Ajout de nœuds MinIO pour cluster

### ⭐ Document de Référence Principal pour ChatGPT

- **`Infra/GUIDE_INSTALLATION_COMPLETE_DEPUIS_ZERO.md`** ⭐⭐⭐
  - **Guide complet pour réinstaller toute l'infrastructure depuis zéro**
  - Processus étape par étape pour Modules 2-9
  - Tous les scripts et commandes nécessaires
  - Checklists et vérifications
  - Dépannage et résolution de problèmes
  - **À donner à ChatGPT pour valider l'installation complète**

---

## 📋 Table des Matières

1. [Documents Principaux de Référence](#documents-principaux-de-référence)
2. [Documentation Technique Détaillée](#documentation-technique-détaillée)
3. [Scripts d'Installation par Module](#scripts-dinstallation-par-module)
4. [Scripts de Test](#scripts-de-test)
5. [Rapports Techniques et États](#rapports-techniques-et-états)
6. [Configuration et Credentials](#configuration-et-credentials)

---

## 📄 Documents Principaux de Référence

### Documentation Générale

- **`Infra/README.md`** - Vue d'ensemble du projet et structure
- **`Infra/QUICK_START.md`** - Guide de démarrage rapide
- **`Infra/ETAT_ACTUEL.md`** - État actuel de l'infrastructure (49 serveurs)
- **`Infra/INSTALLATION_PROCESS.md`** - Processus d'installation détaillé
- **`Infra/INSTALLATION_FROM_SCRATCH.md`** - Installation depuis zéro
- **`Infra/INSTALLATION_CHECKPOINT.md`** - Système de checkpoints par module
- **`Infra/EXECUTER_SUR_INSTALL01.md`** - Guide d'exécution sur install-01

### Documentation Technique Complète

- **`Infra/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`** ⭐
  - **Rapport technique complet de 1678 lignes**
  - Architecture globale
  - Tous les modules détaillés (2-9)
  - Tests et validations
  - Corrections et résolutions

- **`Context/Context.txt`** ⭐
  - **Document de référence principal (13778 lignes)**
  - Toute la spécification technique de l'infrastructure
  - Architecture complète
  - Spécifications des modules
  - Plan des scripts

### Documentation par Module

- **`Infra/docs/01_intro.md`** - Introduction générale
- **`Infra/docs/02_base_os_and_security.md`** - Module 2 : Base OS & Sécurité
- **`Infra/docs/03_postgresql_ha.md`** - Module 3 : PostgreSQL HA
- **`Infra/docs/04_redis_ha.md`** - Module 4 : Redis HA
- **`Infra/docs/05_rabbitmq_ha.md`** - Module 5 : RabbitMQ HA
- **`Infra/docs/06_k3s_ha.md`** - Module 6 : K3s HA
- **`Infra/docs/07_load_balancers.md`** - Module 7 : Load Balancers
- **`Infra/docs/RECAP_MODULE_2.md`** - Récapitulatif Module 2
- **`Infra/docs/RECAP_MODULE_3.md`** - Récapitulatif Module 3
- **`Infra/docs/TEMPLATE_RECAP_MODULE.md`** - Template pour nouveaux récapitulatifs

---

## 📂 Documentation Technique Détaillée

### États et Validations par Module

#### Module 9 (K3s HA) - 100% Validé ✅

- **`Infra/scripts/MODULE9_100_POURCENT_COMPLET.md`** ⭐
  - Module 9 entièrement validé
  - Toutes les corrections appliquées
  - Documentation complète

- **`Infra/scripts/ETAT_FINAL_COMPLET_MODULE9.md`** - État final complet
- **`Infra/scripts/ETAT_COMPLET_MODULE9_ET_CORRECTIONS.md`** - État avec corrections
- **`Infra/scripts/RESUME_FINAL_COMPLET_MODULE9.md`** - Résumé final
- **`Infra/scripts/RESUME_FINAL_MODULE9.md`** - Résumé court
- **`Infra/scripts/MODULE9_INSTALLATION_REUSSIE.md`** - Confirmation d'installation
- **`Infra/scripts/09_k3s_ha/MODULE9_VALIDATION.md`** - Validation Module 9
- **`Infra/scripts/09_k3s_ha/MODULE9_STRUCTURE_PROPOSAL.md`** - Structure proposée

#### Module 8 (ProxySQL)

- **`Infra/scripts/MODULE_8_RESOLU.md`** - Module 8 résolu
- **`Infra/scripts/SUIVI_MODULE_8.md`** - Suivi Module 8
- **`Infra/scripts/08_proxysql_advanced/MODULE8_VALIDATION.md`** - Validation Module 8

#### Module 7 (MariaDB Galera)

- **`Infra/scripts/MODULE_7_RESOLU.md`** - Module 7 résolu
- **`Infra/scripts/ETAT_MODULE_7_FINAL.md`** - État final Module 7
- **`Infra/scripts/RESUME_CORRECTION_MODULE_7.md`** - Résumé corrections
- **`Infra/scripts/PROBLEME_MODULE_7_CLUSTER.md`** - Problèmes cluster
- **`Infra/scripts/DIAGNOSTIC_MODULE_7.md`** - Diagnostic Module 7
- **`Infra/scripts/SUIVI_MODULE_7.md`** - Suivi Module 7
- **`Infra/scripts/07_mariadb_galera/MODULE7_VALIDATION.md`** - Validation Module 7

#### Modules 3-6

- **`Infra/scripts/03_postgresql_ha/MODULE3_VALIDATION.md`** - Validation Module 3
- **`Infra/scripts/04_redis_ha/MODULE4_VALIDATION.md`** - Validation Module 4
- **`Infra/scripts/05_rabbitmq_ha/MODULE5_VALIDATION.md`** - Validation Module 5
- **`Infra/scripts/05_rabbitmq_ha/MODULE5_FINAL_VALIDATION.md`** - Validation finale Module 5
- **`Infra/scripts/06_minio/MODULE6_VALIDATION.md`** - Validation Module 6

---

## 🔧 Scripts d'Installation par Module

### Scripts Principaux

- **`Infra/scripts/00_master_install.sh`** ⭐
  - **Script maître** qui orchestre l'installation de tous les modules
  - Usage : `./00_master_install.sh [--module N]`

- **`Infra/scripts/00_init_install01.sh`** - Initialisation install-01
- **`Infra/scripts/00_check_prerequisites.sh`** - Vérification prérequis
- **`Infra/scripts/00_check_servers_status.sh`** - Vérification statut serveurs
- **`Infra/scripts/00_check_ssh_access_all_servers.sh`** - Vérification SSH

### Module 2 : Base OS & Sécurité

- **`Infra/scripts/02_base_os_and_security/base_os.sh`** - Script base OS
- **`Infra/scripts/02_base_os_and_security/apply_base_os_to_all.sh`** ⭐
  - **Script principal** pour appliquer Module 2 sur tous les serveurs
  - Usage : `./apply_base_os_to_all.sh ../../servers.tsv`

- **`Infra/scripts/check_module2_status.sh`** - Vérification statut Module 2

### Module 3 : PostgreSQL HA

- **`Infra/scripts/03_postgresql_ha/03_pg_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/03_postgresql_ha/03_pg_01_prepare.sh`** - Préparation
- **`Infra/scripts/03_postgresql_ha/03_pg_02_install.sh`** - Installation Patroni
- **`Infra/scripts/03_postgresql_ha/03_pg_07_test_failover_safe.sh`** - Tests failover

### Module 4 : Redis HA

- **`Infra/scripts/04_redis_ha/04_redis_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/04_redis_ha/04_redis_verif_et_test.sh`** - Vérification et tests
- **`Infra/scripts/04_redis_ha/04_redis_test_failover.sh`** - Tests failover
- **`Infra/scripts/04_redis_ha/04_redis_test_failover_final.sh`** - Tests failover finaux
- **`Infra/scripts/04_redis_ha/04_redis_06_tests.sh`** - Tests complets

### Module 5 : RabbitMQ HA

- **`Infra/scripts/05_rabbitmq_ha/05_rmq_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/05_rabbitmq_ha/05_rmq_04_tests.sh`** - Tests
- **`Infra/scripts/05_rabbitmq_ha/05_rmq_05_integration_tests.sh`** - Tests d'intégration

### Module 6 : MinIO

- **`Infra/scripts/06_minio/06_minio_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/06_minio/06_minio_04_tests.sh`** - Tests
- **⚠️ À FAIRE** : Scripts pour migration en cluster (4 nœuds)

### Module 7 : MariaDB Galera

- **`Infra/scripts/07_mariadb_galera/07_maria_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/07_mariadb_galera/07_maria_04_tests.sh`** - Tests

### Module 8 : ProxySQL

- **`Infra/scripts/08_proxysql_advanced/08_proxysql_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/08_proxysql_advanced/08_proxysql_05_failover_tests.sh`** - Tests failover

### Module 9 : K3s HA

- **`Infra/scripts/09_k3s_ha/09_k3s_apply_all.sh`** ⭐ - Installation complète
- **`Infra/scripts/09_k3s_ha/09_k3s_01_prepare.sh`** - Préparation
- **`Infra/scripts/09_k3s_ha/09_k3s_02_install_control_plane.sh`** - Installation control-plane
- **`Infra/scripts/09_k3s_ha/09_k3s_03_join_workers.sh`** - Jointure workers
- **`Infra/scripts/09_k3s_ha/09_k3s_04_bootstrap_addons.sh`** - Bootstrap addons
- **`Infra/scripts/09_k3s_ha/09_k3s_05_ingress_daemonset.sh`** - Ingress DaemonSet
- **`Infra/scripts/09_k3s_ha/09_k3s_06_deploy_core_apps.sh`** - Déploiement apps
- **`Infra/scripts/09_k3s_ha/09_k3s_07_install_monitoring.sh`** - Installation monitoring
- **`Infra/scripts/09_k3s_ha/09_k3s_08_install_vault_agent.sh`** - Vault Agent
- **`Infra/scripts/09_k3s_ha/09_k3s_09_final_validation.sh`** - Validation finale
- **`Infra/scripts/09_k3s_ha/09_k3s_fix_coredns_final.sh`** ⭐ - Fix CoreDNS (solution définitive)
- **`Infra/scripts/09_k3s_ha/09_k3s_10_test_failover_complet.sh`** - Tests failover complets
- **`Infra/scripts/09_k3s_ha/09_k3s_test_healthcheck.sh`** - Tests healthcheck

### Module 10 : KeyBuzz Apps

- **`Infra/scripts/10_keybuzz/10_keybuzz_03_tests.sh`** - Tests KeyBuzz
- **`Infra/scripts/10_keybuzz/MODULE10_VALIDATION.md`** - Validation Module 10

---

## 🧪 Scripts de Test

### Tests Complets Infrastructure

- **`Infra/scripts/00_test_complet_infrastructure.sh`** ⭐
  - **Script principal de test complet** (760 lignes)
  - Tests tous les modules installés
  - Vérifie que les dernières modifications n'ont pas cassé de services

- **`Infra/scripts/00_test_complet_infrastructure_v2.sh`** - Version améliorée
- **`Infra/scripts/00_test_complet_infrastructure_avance.sh`** - Version avancée
- **`Infra/scripts/00_test_complet_infrastructure_haproxy01.sh`** - Tests avec HAProxy
- **`Infra/scripts/00_test_complet_avec_failover.sh`** - Tests avec failover
- **`Infra/scripts/00_test_failover_infrastructure_complet.sh`** - Tests failover complets

### Tests Spécifiques

- **`Infra/scripts/00_test_redis_pg_direct.sh`** - Tests Redis/PostgreSQL directs
- **`Infra/scripts/00_test_3_problemes.sh`** - Tests 3 problèmes spécifiques
- **`Infra/scripts/00_verification_complete.sh`** - Vérification complète
- **`Infra/scripts/00_verification_complete_apres_redemarrage.sh`** - Vérification après redémarrage

### Guide des Tests

- **`Infra/scripts/COMMENT_LANCER_LES_TESTS.md`** - Comment lancer les tests
- **`Infra/scripts/TESTS_COMPLETS_INFRASTRUCTURE.md`** - Documentation tests complets

---

## 📊 Rapports Techniques et États

### États Globaux

- **`Infra/scripts/ETAT_ACTUEL_COMPLET.md`** - État actuel complet
- **`Infra/scripts/ETAT_ACTUEL_DEPLOIEMENT.md`** - État déploiement
- **`Infra/scripts/ETAT_ACTUEL_DETAIL.md`** - État détaillé
- **`Infra/scripts/ETAT_ACTUEL_RESUME.md`** - Résumé état actuel
- **`Infra/scripts/ETAT_INFRASTRUCTURE_COMPLET.md`** - État infrastructure complète
- **`Infra/scripts/ETAT_AVANCEMENT_FINAL.md`** - Avancement final
- **`Infra/scripts/ETAT_DEPLOIEMENT_ACTUEL.md`** - État déploiement actuel
- **`Infra/scripts/ETAT_FINAL_DEPLOIEMENT.md`** - État final déploiement

### Rapports de Tests

- **`Infra/scripts/ETAT_TESTS_FAILOVER_K3S.md`** - Tests failover K3s
- **`Infra/scripts/ETAT_TESTS_FINAUX.md`** - Tests finaux
- **`Infra/scripts/ETAT_VERIFICATION_COMPLETE.md`** - Vérification complète
- **`Infra/scripts/RESULTATS_TESTS_FAILOVER_K3S.md`** - Résultats tests failover K3s
- **`Infra/scripts/RESUME_TESTS_COMPLETS.md`** - Résumé tests complets
- **`Infra/scripts/RESUME_TESTS_INFRASTRUCTURE.md`** - Résumé tests infrastructure
- **`Infra/scripts/VALIDATION_COMPLETE_ET_TESTS_FAILOVER.md`** - Validation complète et failover
- **`Infra/scripts/VALIDATION_FINALE_100_POURCENT.md`** - Validation finale 100%

### Diagnostics

- **`Infra/scripts/00_diagnostic_rapide.sh`** - Diagnostic rapide
- **`Infra/scripts/00_diagnostic_detaille.sh`** - Diagnostic détaillé
- **`Infra/scripts/00_diagnostic_failover.sh`** - Diagnostic failover
- **`Infra/scripts/00_diagnostic_postgres_redis.sh`** - Diagnostic PostgreSQL/Redis
- **`Infra/scripts/00_diagnostic_services.sh`** - Diagnostic services
- **`Infra/scripts/00_complete_diagnostic.sh`** - Diagnostic complet
- **`Infra/scripts/00_DIAGNOSTIC_504_COMPLET.md`** - Diagnostic problème 504

---

## 🔑 Configuration et Credentials

### Inventaire

- **`Infra/servers.tsv`** ⭐ - **Inventaire complet des 49 serveurs**
- **`keybuzz-installer/inventory/servers.tsv`** - Copie dans keybuzz-installer
- **`keybuzz-installer/inventory/inventory.ini`** - Inventaire Ansible

### Credentials

- **`keybuzz-installer/credentials/app_configs.env`** - Configurations apps
- **`keybuzz-installer/credentials/postgres.env`** - Credentials PostgreSQL
- **`keybuzz-installer/credentials/redis.env`** - Credentials Redis
- **`keybuzz-installer/credentials/rabbitmq.env`** - Credentials RabbitMQ
- **`keybuzz-installer/credentials/minio.env`** - Credentials MinIO
- **`keybuzz-installer/credentials/mariadb.env`** - Credentials MariaDB
- **`keybuzz-installer/credentials/k3s.env`** - Credentials K3s
- **`keybuzz-installer/credentials/k3s_token.txt`** - Token K3s

### Configuration SSH

- **`Infra/scripts/ssh_install01.ps1`** ⭐ - **Script principal SSH (Pageant + plink)**
- **`Infra/scripts/README_SSH_INSTALL01.md`** - Guide utilisation SSH
- **`Infra/GUIDE_CONNEXION_SSH.md`** - Guide connexion SSH
- **`Infra/CONNEXION_SSH.md`** - Connexion SSH
- **`Infra/SETUP_SSH_ACCESS.md`** - Configuration accès SSH
- **`SSH/passphrase.txt`** - Passphrase clé SSH (sur Windows)
- **`SSH/keybuzz_infra`** - Clé SSH privée
- **`SSH/keybuzz_infra.pub`** - Clé SSH publique

---

## 🚀 Ordre d'Installation Validé

1. ✅ **Module 2** : Base OS & Sécurité (OBLIGATOIRE EN PREMIER)
2. ✅ **Module 3** : PostgreSQL HA (Patroni RAFT)
3. ✅ **Module 4** : Redis HA (Sentinel)
4. ✅ **Module 5** : RabbitMQ HA (Quorum)
5. ✅ **Module 6** : MinIO (actuellement 1 nœud, migration cluster prévue)
6. ✅ **Module 7** : MariaDB Galera HA
7. ✅ **Module 8** : ProxySQL Advanced
8. ✅ **Module 9** : K3s HA Core (100% validé)
9. ⏳ **Module 10** : Load Balancers & Apps

---

## 📝 Prochaines Étapes Identifiées

### MinIO Cluster (En cours)

D'après `Context/Context.txt` :
- Migration MinIO de 1 nœud vers **cluster 3-4 nœuds**
- Scripts à créer :
  - `06_minio_03_install_cluster.sh` - Installation cluster
  - Migration des données existantes
  - Configuration erasure coding

### Scripts de Test à Réutiliser

- **`Infra/scripts/00_test_complet_infrastructure.sh`** - Pour valider l'état actuel
- Tests de failover complets après modifications MinIO

---

## 📍 Localisation des Fichiers Clés

### Sur install-01 (serveur)

```
/opt/keybuzz-installer/
├── servers.tsv                 # Inventaire 49 serveurs
├── credentials/                # Tous les credentials
├── scripts/                    # Tous les scripts d'installation
│   ├── 00_master_install.sh   # Script maître
│   ├── 02_base_os_and_security/
│   ├── 03_postgresql_ha/
│   ├── 04_redis_ha/
│   ├── 05_rabbitmq_ha/
│   ├── 06_minio/
│   ├── 07_mariadb_galera/
│   ├── 08_proxysql_advanced/
│   ├── 09_k3s_ha/
│   └── 10_keybuzz/
└── docs/                       # Documentation technique
```

### Sur Windows (développement)

```
C:\Users\ludov\Mon Drive\keybuzzio\
├── Infra/                      # Dépôt principal
│   ├── scripts/                # Scripts + documentation
│   ├── docs/                   # Documentation technique
│   └── servers.tsv             # Inventaire
├── SSH/                        # Clés SSH
└── Context/                    # Context.txt (référence complète)
```

---

## ✅ État Final des Modules

### Modules Validés à 100%

- ✅ **Module 2** : Base OS & Sécurité
- ✅ **Module 3** : PostgreSQL HA
- ✅ **Module 4** : Redis HA
- ✅ **Module 5** : RabbitMQ HA
- ✅ **Module 6** : MinIO (1 nœud - cluster en attente)
- ✅ **Module 7** : MariaDB Galera HA
- ✅ **Module 8** : ProxySQL Advanced
- ✅ **Module 9** : K3s HA Core (100% documenté et validé)

### Modules en Cours / À Faire

- ⏳ **Module 6** : Migration MinIO vers cluster (3-4 nœuds)
- ⏳ **Module 10** : Load Balancers & Apps KeyBuzz

---

## 🎯 Utilisation Rapide

### 1. Se connecter à install-01

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1
```

### 2. Lancer les tests complets

```bash
cd /opt/keybuzz-installer/scripts
./00_test_complet_infrastructure.sh
```

### 3. Consulter le rapport technique complet

```bash
cat /opt/keybuzz-installer/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md
```

---

**Ce document est la référence principale pour retrouver tous les éléments techniques de l'installation KeyBuzz.**

---

## 🔄 Réinstallation Complète depuis Zéro

### Guide pour ChatGPT

Pour réinstaller complètement l'infrastructure après un rebuild des serveurs, consulter :

**`Infra/GUIDE_INSTALLATION_COMPLETE_DEPUIS_ZERO.md`** ⭐⭐⭐

Ce guide contient :
- ✅ Processus complet étape par étape (Modules 2-9)
- ✅ Tous les scripts nécessaires avec chemins exacts
- ✅ Commandes de vérification et validation
- ✅ Dépannage et résolution de problèmes
- ✅ Checklists complètes
- ✅ **Prêt à être donné à ChatGPT pour validation**

### Processus Rapide

1. **Vérifier prérequis** : Volumes XFS, SSH, install-01
2. **Module 2** : Base OS sur tous les serveurs (OBLIGATOIRE EN PREMIER)
3. **Modules 3-9** : Installation séquentielle avec scripts `*_apply_all.sh`
4. **Validation** : `./00_test_complet_infrastructure.sh`

**Durée totale** : ~2-3 heures pour installation complète

