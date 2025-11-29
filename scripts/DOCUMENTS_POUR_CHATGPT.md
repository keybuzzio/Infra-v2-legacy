# Documents pour ChatGPT - Infrastructure KeyBuzz

**Date de création** : 2025-11-24  
**Version** : 1.0  
**Objectif** : Liste des documents essentiels à communiquer à ChatGPT pour validation et compréhension de l'infrastructure KeyBuzz

---

## 📋 Documents Principaux (À lire en priorité)

### 1. Rapport Technique Complet
**Fichier** : `RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`  
**Description** : Document principal décrivant l'architecture complète de l'infrastructure KeyBuzz  
**Contenu** :
- Architecture globale (49 serveurs)
- Détails de chaque module (2 à 9)
- Configuration réseau
- Versions et technologies
- Points d'accès et load balancers

**⚠️ IMPORTANT** : Lire en commençant par la fin du document pour les informations les plus récentes.

---

### 2. Suivi d'Installation en Cours
**Fichier** : `SUIVI_INSTALLATION_EN_COURS.md`  
**Description** : Document de suivi en temps réel de l'installation, mis à jour au fur et à mesure  
**Contenu** :
- Statut de chaque module (terminé/en cours/en attente)
- Progression détaillée
- Corrections appliquées
- Logs et diagnostics
- Validation de chaque module

**⚠️ IMPORTANT** : Ce document est mis à jour en temps réel et contient l'état actuel de l'installation.

---

### 3. Notes d'Installation Critiques
**Fichier** : `NOTES_INSTALLATION_MODULES.md`  
**Description** : Notes critiques et corrections importantes pour chaque module  
**Contenu** :
- Patroni : Rebuild image Docker custom (PAS zalando/patroni:3.3.0)
- MinIO : Cluster 3 nœuds (PAS single node)
- Versions Docker figées
- Configurations load balancers
- Corrections spécifiques par module

**⚠️ CRITIQUE** : À consulter AVANT chaque installation de module.

---

## 📊 Rapports de Validation

### 4. Rapports de Validation

#### Module 3
**Fichier** : `RAPPORT_VALIDATION_MODULE3.md`  
**Description** : Rapport détaillé de validation du Module 3 (PostgreSQL HA)  
**Contenu** :
- Résultats des tests (16 tests)
- État du cluster Patroni
- Validation HAProxy et PgBouncer
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 3 validé à 100%

#### Module 4
**Fichier** : `RAPPORT_VALIDATION_MODULE4.md`  
**Description** : Rapport détaillé de validation du Module 4 (Redis HA avec Sentinel)  
**Contenu** :
- Résultats des tests (19 tests)
- État du cluster Redis (Master + 2 Replicas)
- Validation Redis Sentinel (3 instances)
- Validation HAProxy
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 4 validé à 100%

#### Module 5
**Fichier** : `RAPPORT_VALIDATION_MODULE5.md`  
**Description** : Rapport détaillé de validation du Module 5 (RabbitMQ HA avec Quorum)  
**Contenu** :
- Résultats des tests (15 tests)
- État du cluster RabbitMQ (3 nœuds, cluster name: keybuzz-queue)
- Validation HAProxy
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 5 validé à 100%

#### Module 6
**Fichier** : `RAPPORT_VALIDATION_MODULE6.md`  
**Description** : Rapport détaillé de validation du Module 6 (MinIO S3 Cluster Distributed)  
**Contenu** :
- Résultats des tests (18 tests)
- État du cluster MinIO (3 nœuds, mode distribué)
- Validation erasure coding
- Validation client mc
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 6 validé à 100%

#### Module 7
**Fichier** : `RAPPORT_VALIDATION_MODULE7.md`  
**Description** : Rapport détaillé de validation du Module 7 (MariaDB Galera HA avec ProxySQL)  
**Contenu** :
- Résultats des tests (16 tests)
- État du cluster Galera (3 nœuds, cluster name: keybuzz-galera)
- Validation ProxySQL
- Base de données et utilisateur erpnext
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 7 validé à 100%

#### Module 8
**Fichier** : `RAPPORT_VALIDATION_MODULE8.md`  
**Description** : Rapport détaillé de validation du Module 8 (ProxySQL Avancé & Optimisation Galera)  
**Contenu** :
- Résultats des tests (15 validations)
- Configuration ProxySQL avancée (proxysql-01 et proxysql-02)
- Optimisations Galera (3 nœuds)
- Monitoring (scripts déployés)
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 8 validé à 100%

#### Module 9
**Fichier** : `RAPPORT_VALIDATION_MODULE9.md`  
**Description** : Rapport détaillé de validation du Module 9 (K3s HA Core)  
**Contenu** :
- Résultats des tests (39 validations)
- Control-plane HA (3 masters avec etcd intégré)
- Workers (5 workers joints)
- Ingress NGINX DaemonSet (8 pods Running)
- Monitoring (Prometheus Stack - 13 pods Running)
- Addons (CoreDNS, metrics-server, StorageClass)
- Namespaces et ConfigMaps
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 9 validé à 100%

#### Module 10 Platform
**Fichier** : `RAPPORT_VALIDATION_MODULE10_PLATFORM.md`  
**Description** : Rapport détaillé de validation du Module 10 Platform (KeyBuzz API, UI, My Portal)  
**Contenu** :
- Résultats des tests (18 validations)
- Platform API (Deployment 3/3, Service ClusterIP, HPA, Ingress)
- Platform UI (Deployment 3/3, Service ClusterIP, Ingress)
- My Portal (Deployment 3/3, Service ClusterIP, Ingress)
- Architecture Deployment + Service ClusterIP + Ingress
- Credentials avec PgBouncer (port 6432)
- Healthchecks configurés
- Points d'attention
- Conclusion et recommandations

**Statut** : ✅ Module 10 Platform validé à 100%

---

## 🔧 Scripts de Validation

### 5. Scripts de Validation

#### Module 3
**Fichier** : `03_postgresql_ha/validate_module3_complete.sh`  
**Description** : Script de validation complète du Module 3  
**Usage** : `./validate_module3_complete.sh [servers.tsv]`  
**Tests effectués** :
- Conteneurs Patroni (3/3)
- Cluster Patroni (Leader + réplicas)
- HAProxy (2/2)
- PgBouncer (2/2)
- pgvector
- Services systemd

#### Module 4
**Fichier** : `04_redis_ha/validate_module4_complete.sh`  
**Description** : Script de validation complète du Module 4  
**Usage** : `./validate_module4_complete.sh [servers.tsv]`  
**Tests effectués** :
- Conteneurs Redis (3/3)
- Conteneurs Sentinel (3/3)
- Réplication Redis (Master + Replicas)
- Redis Sentinel (quorum)
- HAProxy (2/2)
- Test lecture/écriture
- Services systemd

#### Module 5
**Fichier** : `05_rabbitmq_ha/validate_module5_complete.sh`  
**Description** : Script de validation complète du Module 5  
**Usage** : `./validate_module5_complete.sh [servers.tsv]`  
**Tests effectués** :
- Conteneurs RabbitMQ (3/3)
- Cluster RabbitMQ (3 nœuds, cluster name)
- Ports RabbitMQ (5672)
- HAProxy (2/2)
- Connectivité RabbitMQ
- Services systemd

#### Module 6
**Fichier** : `06_minio/validate_module6_complete.sh`  
**Description** : Script de validation complète du Module 6  
**Usage** : `./validate_module6_complete.sh [servers.tsv]`  
**Tests effectués** :
- Conteneurs MinIO (3/3)
- Configuration cluster distribué (3 nœuds)
- Ports S3 API (9000) et Console (9001)
- Client mc configuré
- Tests lecture/écriture
- Logs MinIO

#### Module 7
**Fichier** : `07_mariadb_galera/07_maria_04_tests.sh`  
**Description** : Script de tests et diagnostics du Module 7  
**Usage** : `./07_maria_04_tests.sh [servers.tsv]`  
**Tests effectués** :
- Conteneurs MariaDB Galera (3/3)
- Cluster Galera (3 nœuds, cluster name: keybuzz-galera)
- Ports MariaDB (3306) et Galera (4567)
- ProxySQL (1/1)
- Connexion via ProxySQL
- Test d'écriture/lecture

---

## 📁 Structure des Scripts d'Installation

### Module 2 : Base OS & Sécurité
**Répertoire** : `02_base_os_and_security/`  
**Script principal** : `apply_base_os_to_all.sh`  
**Fonctionnalités** :
- Installation Docker
- Désactivation swap
- Configuration UFW
- Durcissement SSH
- DNS fixe
- Optimisations kernel

### Module 3 : PostgreSQL HA (Patroni RAFT)
**Répertoire** : `03_postgresql_ha/`  
**Script principal** : `03_pg_apply_all.sh`  
**Étapes** :
1. `03_pg_00_setup_credentials.sh` - Credentials
2. `03_pg_02_install_patroni_cluster.sh` - Cluster Patroni RAFT
3. `03_pg_03_install_haproxy_db_lb.sh` - HAProxy
4. `03_pg_04_install_pgbouncer.sh` - PgBouncer
5. `03_pg_05_install_pgvector.sh` - pgvector
6. `03_pg_06_diagnostics.sh` - Diagnostics

**Scripts de validation** :
- `check_module3_status.sh` - Vérification état
- `validate_module3_complete.sh` - Validation complète
- `reinit_cluster.sh` - Réinitialisation cluster

### Module 4 : Redis HA (Sentinel)
**Répertoire** : `04_redis_ha/`  
**Script principal** : `04_redis_apply_all.sh`  
**Étapes** :
1. `04_redis_00_setup_credentials.sh` - Credentials
2. `04_redis_01_prepare_nodes.sh` - Préparation nœuds
3. `04_redis_02_deploy_redis_cluster.sh` - Cluster Redis
4. `04_redis_03_deploy_sentinel.sh` - Redis Sentinel
5. `04_redis_04_configure_haproxy_redis.sh` - HAProxy
6. `04_redis_05_configure_lb_healthcheck.sh` - LB healthcheck
7. `04_redis_06_tests.sh` - Tests

**Scripts de diagnostic** :
- `04_redis_diagnostic_sentinel.sh` - Diagnostic Sentinel
- `04_redis_diagnostic_failover.sh` - Diagnostic failover
- `04_redis_test_failover.sh` - Test failover

---

## 📝 Fichiers de Configuration

### Credentials
**Répertoire** : `credentials/`  
**Fichiers** :
- `postgres.env` - Credentials PostgreSQL
- `redis.env` - Credentials Redis
- `rabbitmq.env` - Credentials RabbitMQ
- `mariadb.env` - Credentials MariaDB
- `minio.env` - Credentials MinIO

**⚠️ SÉCURITÉ** : Ces fichiers ne sont PAS dans Git, créés localement avec permissions strictes.

### Inventaire
**Fichier** : `servers.tsv` (ou `keybuzz-installer/inventory/servers.tsv`)  
**Format** : TSV (Tab-Separated Values)  
**Colonnes** :
- ENV
- IP_PUBLIQUE
- HOSTNAME
- IP_PRIVEE
- FQDN
- USER_SSH
- POOL
- ROLE
- SUBROLE
- DOCKER_STACK
- CORE
- NOTES

**Total serveurs** : 48 serveurs (prod) + 1 install-01 = 49 serveurs

---

## 🔍 Logs d'Installation

### Emplacement des Logs
**Répertoire** : `/tmp/` (sur install-01)  
**Fichiers** :
- `module2_installation_*.log` - Module 2
- `module3_installation_*.log` - Module 3
- `module4_installation_*.log` - Module 4
- `module3_validation.log` - Validation Module 3

**Accès** : Via SSH sur `install-01` (91.98.128.153)

---

## 🎯 Points Clés pour ChatGPT

### Architecture
- **49 serveurs** sur Hetzner Cloud
- **Réseau privé** : 10.0.0.0/16
- **Modules indépendants** et réinstallables
- **Haute disponibilité** pour tous les services stateful

### Modules Installés
1. ✅ **Module 2** : Base OS & Sécurité (48/48 serveurs)
2. ✅ **Module 3** : PostgreSQL HA (Patroni RAFT) - Validé à 100%
3. ✅ **Module 4** : Redis HA (Sentinel) - Validé à 100%
4. ✅ **Module 5** : RabbitMQ HA (Quorum) - Validé à 100%
5. ✅ **Module 6** : MinIO S3 (Cluster 3 Nœuds) - Validé à 100%
6. ✅ **Module 7** : MariaDB Galera HA - Validé à 100%
7. ✅ **Module 8** : ProxySQL Advanced - Validé à 100%
8. ✅ **Module 9** : K3s HA Core - Validé à 100%
9. ✅ **Module 10 Platform** : KeyBuzz API, UI, My Portal - Validé à 100%

### Corrections Critiques Appliquées
1. **Patroni** : Image Docker custom rebuild (PAS zalando/patroni:3.3.0)
2. **MinIO** : Cluster 3 nœuds (PAS single node)
3. **Volumes XFS** : Formatage et montage automatique
4. **Scripts parallèles** : Module 2 avec support parallèle

### Conformité KeyBuzz
- ✅ Architecture conforme aux spécifications KeyBuzz
- ✅ Versions Docker figées
- ✅ Load balancers Hetzner configurés
- ✅ Haute disponibilité pour tous les services
- ✅ Scripts idempotents et réinstallables

---

## 📚 Ordre de Lecture Recommandé pour ChatGPT

1. **`NOTES_INSTALLATION_MODULES.md`** - Notes critiques (5 min)
2. **`RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`** - Architecture complète (30 min)
   - Commencer par la fin pour les informations les plus récentes
3. **`SUIVI_INSTALLATION_EN_COURS.md`** - État actuel (15 min)
4. **`RAPPORT_VALIDATION_MODULE3.md`** - Validation Module 3 (10 min)
5. **`RAPPORT_VALIDATION_MODULE4.md`** - Validation Module 4 (10 min)
6. **`RAPPORT_VALIDATION_MODULE5.md`** - Validation Module 5 (10 min)
7. **`RAPPORT_VALIDATION_MODULE6.md`** - Validation Module 6 (10 min)
8. **`RAPPORT_VALIDATION_MODULE7.md`** - Validation Module 7 (10 min)
9. **`RAPPORT_VALIDATION_MODULE8.md`** - Validation Module 8 (10 min)
10. **`RAPPORT_VALIDATION_MODULE9.md`** - Validation Module 9 (10 min)
11. **`RAPPORT_VALIDATION_MODULE10_PLATFORM.md`** - Validation Module 10 Platform (10 min)
12. **Scripts d'installation** - Selon le module à valider

**Temps total estimé** : ~1h30 pour une compréhension complète

---

## 🔄 Mise à Jour

Ce document est mis à jour à chaque :
- Nouvelle validation de module
- Nouvelle correction critique
- Nouveau document créé

**Dernière mise à jour** : 2025-11-24 18:15 UTC

---

## ⚠️ RÈGLES DÉFINITIVES - MODULES 4 ET 5

### Module 4 : Redis HA (Sentinel)

**✅ MODULE DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**RÈGLE STRICTE** : Toutes les applications doivent utiliser UNIQUEMENT :
```
REDIS_URL=redis://10.0.0.10:6379
```

**❌ INTERDICTIONS** :
- Ne JAMAIS utiliser directement redis-01, redis-02, redis-03
- Ne JAMAIS modifier la configuration Redis/Sentinel/HAProxy

**Watcher Sentinel** : Actif sur haproxy-01 et haproxy-02 (cron 5-10s ou daemon)

### Module 5 : RabbitMQ HA (Quorum)

**✅ MODULE DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**RÈGLE STRICTE** : Toutes les applications doivent utiliser UNIQUEMENT :
```
AMQP_URL=amqp://10.0.0.10:5672
```

**❌ INTERDICTIONS** :
- Ne JAMAIS utiliser directement queue-01, queue-02, queue-03
- Ne JAMAIS modifier la configuration RabbitMQ/HAProxy

**Version Docker** : `rabbitmq:3.12.14-management` (figée)

**Services Systemd** : Ne PAS créer, Docker uniquement avec `--restart unless-stopped`

### Module 7 : MariaDB Galera HA

**✅ MODULE DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**RÈGLES STRICTES** :
- ✅ **MariaDB URL obligatoire** : `MARIADB_HOST=10.0.0.20` (Load Balancer Hetzner uniquement)
- ❌ **INTERDICTION** : Ne JAMAIS utiliser directement maria-01, maria-02, maria-03
- ❌ **INTERDICTION** : Ne JAMAIS utiliser proxysql-01 ou proxysql-02 directement
- ✅ **Deux ProxySQL obligatoires** : proxysql-01 (10.0.0.173) et proxysql-02 (10.0.0.174)
- ✅ **Versions Docker figées** : `bitnami/mariadb-galera:10.11.6` et `proxysql/proxysql:2.6.4` (jamais `latest`)
- ✅ **Load Balancer Hetzner** : 10.0.0.20:3306 → proxysql-01, proxysql-02 (à configurer manuellement)
- ✅ **Configuration Galera** : binlog_format=ROW, innodb_autoinc_lock_mode=2, wsrep_sst_method=rsync, wsrep_on=ON
- ✅ **Applications concernées** : ERPNext, n8n, Workers

### Module 6 : MinIO S3 (Cluster 3 Nœuds)

**✅ MODULE DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**RÈGLES STRICTES** :
- ✅ **3 nœuds fixes** : minio-01 (10.0.0.134), minio-02 (10.0.0.131), minio-03 (10.0.0.132)
- ❌ **INTERDICTION** : Ne JAMAIS ajouter ou retirer de nœuds sans instruction explicite
- ✅ **Version Docker figée** : `minio/minio:RELEASE.2024-10-02T10-00Z` (jamais `latest`)
- ❌ **INTERDICTION** : Ne JAMAIS exposer MinIO à Internet (interne uniquement)
- ✅ **Point d'entrée officiel** : `http://10.0.0.134:9000`
- ✅ **Alias mc obligatoire** : `mc alias set minio http://10.0.0.134:9000 <USER> <PASSWORD>`
- ✅ **Topologie** : 1 pool, 1 set, 3 drives per set (erasure coding)

### Module 8 : ProxySQL Advanced & Optimisation Galera

**✅ MODULE DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**RÈGLES STRICTES** :
- ✅ **Configuration ProxySQL avancée** : Checks Galera WSREP activés, détection automatique DOWN
- ✅ **Query Rules** : Toutes les requêtes → hostgroup 10 (writer) - Pas de read/write split pour ERPNext
- ✅ **Optimisations Galera** : wsrep_provider_options optimisés, InnoDB tuning (buffer_pool_size=1G)
- ✅ **Monitoring** : Scripts `/usr/local/bin/monitor_galera.sh` et `/usr/local/bin/monitor_proxysql.sh` déployés
- ✅ **Deux ProxySQL obligatoires** : proxysql-01 (10.0.0.173) et proxysql-02 (10.0.0.174) - Configuration identique
- ✅ **Versions Docker figées** : `proxysql/proxysql:2.6.4` et `bitnami/mariadb-galera:10.11.6` (jamais `latest`)
- ❌ **INTERDICTION** : Ne JAMAIS modifier la configuration ProxySQL avancée ou les optimisations Galera
- ✅ **ERPNext** : NE doit PAS utiliser de read/write split (risque de stale reads)
- ✅ **Port 4567** : Ne PAS ajouter au LB Hetzner (communication interne Galera uniquement)

---

## 📞 Support

Pour toute question sur l'infrastructure :
1. Consulter `SUIVI_INSTALLATION_EN_COURS.md` pour l'état actuel
2. Consulter `NOTES_INSTALLATION_MODULES.md` pour les notes critiques
3. Consulter les logs dans `/tmp/` sur install-01
4. Utiliser les scripts de diagnostic dans chaque module

