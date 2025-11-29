# 📚 Guide d'Installation Complète KeyBuzz - Depuis Zéro (Pour ChatGPT)

**Date** : 2025-11-23  
**Version** : 1.0  
**But** : Document complet pour réinstaller toute l'infrastructure KeyBuzz depuis zéro après un rebuild complet des serveurs

---

## 📋 Vue d'Ensemble

Ce guide permet de réinstaller **complètement** l'infrastructure KeyBuzz (Modules 2 à 9) depuis zéro après un rebuild complet des serveurs et volumes.

### Infrastructure

- **49 serveurs** Ubuntu 24.04 LTS
- **Réseau privé** : 10.0.0.0/16
- **Serveur install-01** : 10.0.0.20 (IP publique : 91.98.128.153)
- **Inventaire** : `servers.tsv`

---

## 🔑 Prérequis OBLIGATOIRES

### 1. Serveurs

- ✅ Tous les serveurs **rebuildés** (Ubuntu 24.04 LTS)
- ✅ **Volumes XFS** créés et montés (pour les serveurs DB)
- ✅ **Réseau privé** 10.0.0.0/16 fonctionnel
- ✅ **SSH** accessible depuis install-01 vers tous les serveurs

### 2. Accès SSH

- ✅ **Clé SSH** : `keybuzz_infra` déposée sur tous les serveurs
- ✅ **Passphrase** : Disponible dans `SSH/passphrase.txt`
- ✅ **Pageant** : Configuré pour automatisation (Windows)
- ✅ **Script SSH** : `Infra/scripts/ssh_install01.ps1` (Windows)

### 3. install-01

- ✅ **Dépôt cloné** : `/opt/keybuzz-installer`
- ✅ **Fichier servers.tsv** : `/opt/keybuzz-installer/servers.tsv`
- ✅ **Credentials** : `/opt/keybuzz-installer/credentials/`

---

## 🚀 PROCESSUS D'INSTALLATION COMPLET

### ÉTAPE 0 : Vérifications Préalables

```bash
# Sur install-01
cd /opt/keybuzz-installer

# Vérifier que servers.tsv existe
ls -la servers.tsv

# Vérifier la structure
ls -la scripts/

# Vérifier les credentials (seront générés si nécessaire)
ls -la credentials/
```

---

### ÉTAPE 1 : Module 2 - Base OS & Sécurité ⚠️ OBLIGATOIRE EN PREMIER

**Ce module DOIT être appliqué en PREMIER sur TOUS les serveurs.**

#### 1.1 Vérification ADMIN_IP

```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security

# Vérifier ADMIN_IP (doit être 91.98.128.153)
grep ADMIN_IP base_os.sh

# Si nécessaire, modifier :
nano base_os.sh
# Ligne 19 : ADMIN_IP="91.98.128.153"
```

#### 1.2 Installation sur TOUS les serveurs

```bash
# Lancer l'installation
./apply_base_os_to_all.sh ../../servers.tsv
```

**Durée** : 10-15 minutes pour 49 serveurs

**Ce que fait ce module** :
- ✅ Mise à jour OS (Ubuntu 24.04)
- ✅ Installation Docker
- ✅ Désactivation swap
- ✅ Configuration UFW (firewall)
- ✅ Durcissement SSH
- ✅ Configuration DNS
- ✅ Optimisations kernel/sysctl
- ✅ Configuration journald

#### 1.3 Validation Module 2

```bash
# Vérifier l'état
./check_module2_status.sh ../../servers.tsv
```

**Checkpoints** :
- ✅ Docker installé et actif sur tous les serveurs
- ✅ Swap désactivé partout
- ✅ UFW activé partout
- ✅ SSH durci partout

---

### ÉTAPE 2 : Module 3 - PostgreSQL HA (Patroni RAFT)

**⚠️ PRÉREQUIS** : Volumes XFS montés sur `/opt/keybuzz/postgres/data` pour les 3 nœuds DB

#### 2.1 Vérification Volumes XFS

```bash
# Vérifier que les volumes XFS sont montés
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
  echo "=== $ip ==="
  ssh root@$ip "df -T /opt/keybuzz/postgres/data | tail -1"
done
```

**Résultat attendu** : Filesystem = `xfs`

#### 2.2 Installation Complète Module 3

```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha

# Installation complète (toutes les étapes)
./03_pg_apply_all.sh ../../servers.tsv --yes
```

**Ce script installe automatiquement** :
1. ✅ Configuration credentials PostgreSQL
2. ✅ Cluster Patroni RAFT (3 nœuds : db-master-01, db-slave-01, db-slave-02)
3. ✅ HAProxy sur haproxy-01 et haproxy-02
4. ✅ PgBouncer sur haproxy-01 et haproxy-02
5. ✅ Extension pgvector
6. ✅ Diagnostics et tests

**Durée** : 15-20 minutes

**Checkpoints** :
- ✅ 3 containers Patroni actifs
- ✅ 1 Leader élu dans le cluster
- ✅ HAProxy accessible sur port 5432
- ✅ PgBouncer accessible sur port 6432

#### 2.3 Vérification Module 3

```bash
# Vérifier le statut du cluster
ssh root@10.0.0.120 "docker exec patroni patronictl -c /etc/patroni/patroni.yml list"

# Vérifier HAProxy
ssh root@10.0.0.11 "docker ps | grep haproxy"
ssh root@10.0.0.11 "nc -z localhost 5432 && echo OK || echo FAIL"

# Tests complets
./03_pg_06_diagnostics.sh ../../servers.tsv
```

---

### ÉTAPE 3 : Module 4 - Redis HA (Sentinel)

```bash
cd /opt/keybuzz-installer/scripts/04_redis_ha

# Installation complète
./04_redis_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ Redis Master (redis-01)
- ✅ Redis Replicas (redis-02, redis-03)
- ✅ Redis Sentinel (sur les 3 nœuds)
- ✅ HAProxy Redis (sur haproxy-01/02)

**Durée** : 10-15 minutes

**Checkpoints** :
- ✅ Redis Master actif
- ✅ 2 Redis Replicas actifs
- ✅ Sentinel actif (3 instances)
- ✅ HAProxy Redis accessible sur port 6379

---

### ÉTAPE 4 : Module 5 - RabbitMQ HA (Quorum)

```bash
cd /opt/keybuzz-installer/scripts/05_rabbitmq_ha

# Installation complète
./05_rmq_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ RabbitMQ Cluster Quorum (3 nœuds : queue-01, queue-02, queue-03)
- ✅ Quorum queues activées

**Durée** : 10-15 minutes

**Checkpoints** :
- ✅ 3 containers RabbitMQ actifs
- ✅ Cluster formé (3/3 nœuds)
- ✅ Quorum queues fonctionnelles

---

### ÉTAPE 5 : Module 6 - MinIO

```bash
cd /opt/keybuzz-installer/scripts/06_minio

# Installation complète
./06_minio_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ MinIO (actuellement 1 nœud, migration cluster prévue)

**Durée** : 5-10 minutes

**Checkpoints** :
- ✅ Container MinIO actif
- ✅ S3 API accessible
- ✅ Buckets créés

---

### ÉTAPE 6 : Module 7 - MariaDB Galera

```bash
cd /opt/keybuzz-installer/scripts/07_mariadb_galera

# Installation complète
./07_maria_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ Cluster MariaDB Galera (3 nœuds : mariadb-01, mariadb-02, mariadb-03)

**Durée** : 15-20 minutes

**Checkpoints** :
- ✅ 3 containers MariaDB actifs
- ✅ Cluster Galera formé
- ✅ Réplication synchrone active

---

### ÉTAPE 7 : Module 8 - ProxySQL

```bash
cd /opt/keybuzz-installer/scripts/08_proxysql_advanced

# Installation complète
./08_proxysql_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ ProxySQL (2 nœuds : proxysql-01, proxysql-02)
- ✅ Configuration pour MariaDB Galera

**Durée** : 10-15 minutes

**Checkpoints** :
- ✅ 2 containers ProxySQL actifs
- ✅ Configuration MariaDB correcte
- ✅ Load balancing actif

---

### ÉTAPE 8 : Module 9 - K3s HA

```bash
cd /opt/keybuzz-installer/scripts/09_k3s_ha

# Installation complète
./09_k3s_apply_all.sh ../../servers.tsv
```

**Ce script installe** :
- ✅ K3s Control Plane (3 masters : k3s-master-01, k3s-master-02, k3s-master-03)
- ✅ K3s Workers (5 workers : k3s-worker-01 à k3s-worker-05)
- ✅ Addons : CoreDNS, Traefik Ingress, Metrics Server
- ✅ Ingress DaemonSet
- ✅ Monitoring : Prometheus, Grafana, Loki

**Durée** : 30-40 minutes

**Checkpoints** :
- ✅ 3 masters K3s actifs
- ✅ 5 workers K3s actifs
- ✅ Cluster Kubernetes opérationnel (8/8 nœuds Ready)
- ✅ CoreDNS fonctionnel
- ✅ Traefik Ingress actif

---

## 🧪 VALIDATION COMPLÈTE

### Script de Test Complet

```bash
cd /opt/keybuzz-installer/scripts

# Tests complets de toute l'infrastructure
./00_test_complet_infrastructure.sh
```

**Ce script teste** :
- ✅ Connectivité SSH vers tous les serveurs
- ✅ Services Docker sur tous les serveurs
- ✅ Module 2 : Base OS
- ✅ Module 3 : PostgreSQL HA
- ✅ Module 4 : Redis HA
- ✅ Module 5 : RabbitMQ HA
- ✅ Module 6 : MinIO
- ✅ Module 7 : MariaDB Galera
- ✅ Module 8 : ProxySQL
- ✅ Module 9 : K3s HA

**Durée** : 10-15 minutes

---

## 📊 ORDRE D'INSTALLATION VALIDÉ

**⚠️ IMPORTANT** : Respecter cet ordre STRICTEMENT

1. ✅ **Module 2** : Base OS & Sécurité (OBLIGATOIRE EN PREMIER)
2. ✅ **Module 3** : PostgreSQL HA (Patroni RAFT)
3. ✅ **Module 4** : Redis HA (Sentinel)
4. ✅ **Module 5** : RabbitMQ HA (Quorum)
5. ✅ **Module 6** : MinIO
6. ✅ **Module 7** : MariaDB Galera HA
7. ✅ **Module 8** : ProxySQL Advanced
8. ✅ **Module 9** : K3s HA Core
9. ⏳ **Module 10** : Load Balancers & Apps (non couvert ici)

---

## 🔧 SCRIPTS PRINCIPAUX PAR MODULE

### Module 2 : Base OS
- **Script principal** : `scripts/02_base_os_and_security/apply_base_os_to_all.sh`
- **Validation** : `scripts/02_base_os_and_security/check_module2_status.sh`

### Module 3 : PostgreSQL HA
- **Script principal** : `scripts/03_postgresql_ha/03_pg_apply_all.sh`
- **Diagnostics** : `scripts/03_postgresql_ha/03_pg_06_diagnostics.sh`
- **Tests failover** : `scripts/03_postgresql_ha/03_pg_07_test_failover_safe.sh`

### Module 4 : Redis HA
- **Script principal** : `scripts/04_redis_ha/04_redis_apply_all.sh`

### Module 5 : RabbitMQ HA
- **Script principal** : `scripts/05_rabbitmq_ha/05_rmq_apply_all.sh`

### Module 6 : MinIO
- **Script principal** : `scripts/06_minio/06_minio_apply_all.sh`

### Module 7 : MariaDB Galera
- **Script principal** : `scripts/07_mariadb_galera/07_maria_apply_all.sh`

### Module 8 : ProxySQL
- **Script principal** : `scripts/08_proxysql_advanced/08_proxysql_apply_all.sh`

### Module 9 : K3s HA
- **Script principal** : `scripts/09_k3s_ha/09_k3s_apply_all.sh`
- **Validation** : `scripts/09_k3s_ha/09_k3s_09_final_validation.sh`

### Tests Globaux
- **Tests complets** : `scripts/00_test_complet_infrastructure.sh`

---

## 📝 NOTES IMPORTANTES

### Volumes XFS

**⚠️ CRITIQUE** : Les serveurs DB (PostgreSQL, MariaDB) **DOIVENT** avoir des volumes XFS montés :

```bash
# Vérifier le filesystem
df -T /opt/keybuzz/postgres/data
# Doit retourner : xfs

# Si ce n'est pas XFS, le script Patroni refusera de continuer
```

### Credentials

Les credentials sont générés automatiquement lors de la première installation de chaque module :
- **PostgreSQL** : `/opt/keybuzz-installer/credentials/postgres.env`
- **Redis** : `/opt/keybuzz-installer/credentials/redis.env`
- **RabbitMQ** : `/opt/keybuzz-installer/credentials/rabbitmq.env`
- **MinIO** : `/opt/keybuzz-installer/credentials/minio.env`
- **MariaDB** : `/opt/keybuzz-installer/credentials/mariadb.env`

**⚠️ IMPORTANT** : Conserver ces fichiers pour les réinstallations !

### Idempotence

Tous les scripts sont **idempotents** : vous pouvez les relancer sans risque. Ils vérifient l'état actuel avant d'agir.

### Mode Non-Interactif

La plupart des scripts supportent `--yes` ou `-y` pour le mode non-interactif :

```bash
./03_pg_apply_all.sh ../../servers.tsv --yes
```

---

## 🆘 DÉPANNAGE

### Module 2 échoue

```bash
# Vérifier la connectivité SSH
for ip in 10.0.0.120 10.0.0.121; do
  ssh root@$ip "echo OK $ip"
done

# Relancer sur un serveur spécifique
ssh root@10.0.0.120 "bash -s" < scripts/02_base_os_and_security/base_os.sh db postgres
```

### Module 3 - Patroni ne bootstrappe pas

```bash
# Vérifier les volumes XFS
ssh root@10.0.0.120 "df -T /opt/keybuzz/postgres/data"

# Vérifier les containers
ssh root@10.0.0.120 "docker ps | grep patroni"

# Vérifier les logs
ssh root@10.0.0.120 "docker logs patroni --tail 50"

# Réinitialiser le cluster
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
./reinit_cluster.sh
```

### Module 9 - K3s ne démarre pas

```bash
# Vérifier les services
ssh root@10.0.0.100 "systemctl status k3s"

# Vérifier les nodes
ssh root@10.0.0.100 "kubectl get nodes"

# Logs
ssh root@10.0.0.100 "journalctl -u k3s -n 50"
```

---

## 📚 DOCUMENTS DE RÉFÉRENCE

### Documents Principaux

- **`Infra/GUIDE_COMPLET_INSTALLATION_KEYBUZZ.md`** ⭐ - Guide complet avec tous les chemins
- **`Infra/INSTALLATION_FROM_SCRATCH.md`** - Installation depuis zéro
- **`Infra/INSTALLATION_PROCESS.md`** - Processus d'installation détaillé
- **`Context/Context.txt`** ⭐ - Spécification technique complète (13778 lignes)
- **`Infra/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`** ⭐ - Rapport technique complet

### Documentation par Module

- **Module 2** : `Infra/docs/02_base_os_and_security.md`
- **Module 3** : `Infra/docs/03_postgresql_ha.md`
- **Module 4** : `Infra/docs/04_redis_ha.md`
- **Module 5** : `Infra/docs/05_rabbitmq_ha.md`
- **Module 9** : `Infra/docs/06_k3s_ha.md`

---

## ✅ CHECKLIST FINALE

Après installation complète, vérifier :

### Infrastructure

- [ ] Module 2 : Tous les serveurs ont Docker, swap désactivé, UFW activé
- [ ] Module 3 : Cluster Patroni opérationnel (1 Leader + 2 Replicas)
- [ ] Module 3 : HAProxy accessible (port 5432)
- [ ] Module 3 : PgBouncer accessible (port 6432)
- [ ] Module 4 : Redis Master + 2 Replicas + Sentinel actifs
- [ ] Module 5 : RabbitMQ Cluster formé (3/3 nœuds)
- [ ] Module 6 : MinIO accessible (S3 API)
- [ ] Module 7 : MariaDB Galera Cluster formé (3/3 nœuds)
- [ ] Module 8 : ProxySQL actif (2 nœuds)
- [ ] Module 9 : K3s Cluster opérationnel (8/8 nœuds Ready)

### Tests

- [ ] Tests complets infrastructure : `./00_test_complet_infrastructure.sh` ✅
- [ ] Tests failover PostgreSQL : `./03_pg_07_test_failover_safe.sh`
- [ ] Tests failover K3s : `./09_k3s_10_test_failover_complet.sh`

---

## 🎯 COMMANDES RAPIDES

### Connexion à install-01

```powershell
# Sur Windows
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1
```

```bash
# Sur install-01
cd /opt/keybuzz-installer/scripts
```

### Installation Module par Module

```bash
# Module 2
cd 02_base_os_and_security && ./apply_base_os_to_all.sh ../../servers.tsv

# Module 3
cd ../03_postgresql_ha && ./03_pg_apply_all.sh ../../servers.tsv --yes

# Module 4
cd ../04_redis_ha && ./04_redis_apply_all.sh ../../servers.tsv

# Module 5
cd ../05_rabbitmq_ha && ./05_rmq_apply_all.sh ../../servers.tsv

# Module 6
cd ../06_minio && ./06_minio_apply_all.sh ../../servers.tsv

# Module 7
cd ../07_mariadb_galera && ./07_maria_apply_all.sh ../../servers.tsv

# Module 8
cd ../08_proxysql_advanced && ./08_proxysql_apply_all.sh ../../servers.tsv

# Module 9
cd ../09_k3s_ha && ./09_k3s_apply_all.sh ../../servers.tsv
```

### Tests Complets

```bash
cd /opt/keybuzz-installer/scripts
./00_test_complet_infrastructure.sh
```

---

**Ce document est la référence complète pour réinstaller toute l'infrastructure KeyBuzz depuis zéro.**

**Dernière mise à jour** : 2025-11-23  
**Statut** : ✅ Modules 2-9 documentés et validés













