# Module 8 - ProxySQL Avancé & Optimisation Galera

**Version** : 1.0  
**Date** : 19 novembre 2025  
**Statut** : ✅ Scripts créés

## 🎯 Objectif

Ce module optimise et surveille le cluster MariaDB Galera et ProxySQL pour ERPNext en production. Il s'agit d'un module d'**expertise et d'optimisation** qui complète le Module 7.

### Objectifs principaux

1. **Optimisation ProxySQL** :
   - Équilibrage intelligent entre nœuds Galera
   - Détection automatique des nœuds down
   - Redirection automatique
   - Gestion propre des writes
   - Anti-double écriture
   - Latence minimale

2. **Optimisation Galera** :
   - Configuration wsrep adaptée pour ERPNext
   - SST/IST optimisés
   - Best-in-class pour charges ERP

3. **Monitoring complet** :
   - Métriques Galera
   - Métriques ProxySQL
   - Scripts de vérification de santé

4. **Auto-réparation** :
   - Rejoin automatique d'un nœud
   - Safe bootstrap
   - Règles de récupération

## 📋 Prérequis

- **Module 7 installé** : MariaDB Galera HA + ProxySQL basique
- **Cluster Galera opérationnel** : 3 nœuds synchronisés
- **ProxySQL basique** : 2 nœuds déployés
- **LB Hetzner** : 10.0.0.20:3306 configuré

## 🏗️ Architecture

### Basé sur Module 7

- **3 nœuds MariaDB Galera** : maria-01, maria-02, maria-03
- **2 nœuds ProxySQL** : proxysql-01, proxysql-02
- **LB Hetzner** : 10.0.0.20:3306

### Ce que Module 8 ajoute

- **Configuration ProxySQL avancée** : Checks Galera WSREP, détection automatique
- **Optimisations Galera** : wsrep_provider_options, InnoDB tuning
- **Monitoring** : Scripts de collecte de métriques
- **Tests failover** : Tests avancés de récupération

## 📦 Scripts

### 1. `08_proxysql_01_generate_config.sh`
Génère la configuration ProxySQL avancée :
- Configuration avec checks Galera WSREP
- Query rules optimisées pour ERPNext
- Script SQL pour application

### 2. `08_proxysql_02_apply_config.sh`
Applique la configuration ProxySQL avancée sur tous les nœuds ProxySQL.

### 3. `08_proxysql_03_optimize_galera.sh`
Optimise la configuration Galera pour ERPNext :
- wsrep_provider_options optimisés
- InnoDB tuning (buffer_pool_size=1G, log_file_size=512M)
- SST method: rsync
- Auto recovery activé

### 4. `08_proxysql_04_monitoring_setup.sh`
Configure le monitoring :
- Scripts de monitoring Galera
- Scripts de monitoring ProxySQL
- Déploiement sur les nœuds

### 5. `08_proxysql_05_failover_tests.sh`
Tests failover avancés :
- Test failover MariaDB (arrêt d'un nœud)
- Test failover ProxySQL (arrêt d'un nœud)
- Test cluster health
- Test récupération automatique

### 6. `08_proxysql_apply_all.sh`
Script master qui orchestre toutes les étapes.

## 🚀 Installation

### Installation complète

```bash
cd /opt/keybuzz-installer/scripts/08_proxysql_advanced
./08_proxysql_apply_all.sh [servers.tsv] [--yes]
```

### Installation étape par étape

```bash
# 1. Générer la configuration
./08_proxysql_01_generate_config.sh [servers.tsv]

# 2. Appliquer la configuration
./08_proxysql_02_apply_config.sh [servers.tsv]

# 3. Optimiser Galera
./08_proxysql_03_optimize_galera.sh [servers.tsv]

# 4. Configurer le monitoring
./08_proxysql_04_monitoring_setup.sh [servers.tsv]

# 5. Tests failover (optionnel)
./08_proxysql_05_failover_tests.sh [servers.tsv]
```

## 🔧 Configuration

### ProxySQL Avancée

- **Checks Galera WSREP** : Activés
  - `mysql_galera_check_enabled=true`
  - `mysql_galera_check_interval_ms=2000`
  - `mysql_galera_check_timeout_ms=500`
  - `mysql_galera_check_max_latency_ms=150`

- **Détection automatique DOWN** :
  - `mysql_server_advanced_check=1`
  - `mysql_server_advanced_check_timeout_ms=1000`
  - `mysql_server_advanced_check_interval_ms=2000`

- **Query Rules** : Toutes les requêtes → hostgroup 10 (writer)
  - Pas de read/write split pour ERPNext
  - Évite stale reads

### Galera Optimisé

- **wsrep_provider_options** :
  ```
  gcs.fc_limit=256; gcs.fc_factor=1.0; gcs.fc_master_slave=YES;
  evs.keepalive_period=PT3S; evs.suspect_timeout=PT10S;
  evs.inactive_timeout=PT30S; pc.recovery=TRUE
  ```

- **InnoDB Tuning** :
  - `innodb_buffer_pool_size=1G`
  - `innodb_log_file_size=512M`
  - `innodb_flush_method=O_DIRECT`
  - `innodb_flush_log_at_trx_commit=1`

- **SST Method** : `rsync` (stable et sûr pour ERPNext)

## 📊 Monitoring

### Scripts de monitoring

- **Galera** : `/usr/local/bin/monitor_galera.sh`
  - Cluster size
  - Local state
  - Flow control
  - Replication lag
  - Queries/sec

- **ProxySQL** : `/usr/local/bin/monitor_proxysql.sh`
  - MySQL servers status
  - Connection pool stats
  - Hostgroup health

### Utilisation

```bash
# Monitoring Galera
ssh root@<ip> /usr/local/bin/monitor_galera.sh

# Monitoring ProxySQL
ssh root@<ip> /usr/local/bin/monitor_proxysql.sh
```

## 🧪 Tests

### Tests failover

Le script `08_proxysql_05_failover_tests.sh` effectue :

1. **Test failover MariaDB** :
   - Arrêt d'un nœud MariaDB
   - Vérification de la continuité via ProxySQL
   - Redémarrage et vérification de la récupération

2. **Test failover ProxySQL** :
   - Arrêt d'un nœud ProxySQL
   - Vérification de la continuité via l'autre ProxySQL
   - Redémarrage

3. **Test cluster health** :
   - Vérification de tous les nœuds MariaDB
   - Vérification de tous les nœuds ProxySQL

## ⚠️ Notes importantes

### ERPNext et Read/Write Split

- **ERPNext NE doit PAS utiliser de read/write split**
- ERPNext utilise un ORM avec transactions
- Impossible de garantir l'ordre des lectures après écritures
- Risque de stale reads
- **Toutes les requêtes → hostgroup 10 (writer)**

### Port 4567

- **NON**, le port 4567 ne doit **PAS** être ajouté au LB Hetzner
- Port 4567 = Réplication Galera (wsrep) - communication interne uniquement
- LB Hetzner doit exposer uniquement le port **3306** (ProxySQL frontend)

### Auto Recovery

- `pc.recovery=TRUE` activé dans wsrep_provider_options
- Permet la récupération automatique d'un nœud après panne
- Safe bootstrap automatique

## 🔗 Intégration avec autres modules

✅ **Module 7** : Module 8 complète et optimise le Module 7  
✅ **Module 3 (PostgreSQL)** : Compatible (services indépendants)  
✅ **Module 4 (Redis)** : Compatible  
✅ **Module 5 (RabbitMQ)** : Compatible  
✅ **Module 6 (MinIO)** : Compatible  

## 📚 Documentation

- **Context.txt** : Section "Module 8 – ProxySQL Avancé & Optimisation Galera"
- **Module 7** : `07_mariadb_galera/README.md` et `MODULE7_VALIDATION.md`

## 🎉 Résultat

Après l'installation du Module 8, vous avez :

- ✅ ProxySQL optimisé pour production ERPNext
- ✅ Galera optimisé pour charges ERP
- ✅ Monitoring complet configuré
- ✅ Tests failover validés
- ✅ Cluster au niveau Entreprise

---

**Dernière mise à jour** : 19 novembre 2025  
**Auteur** : Infrastructure KeyBuzz

