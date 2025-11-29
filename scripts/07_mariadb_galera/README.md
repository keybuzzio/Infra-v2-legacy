# Module 7 - MariaDB Galera HA pour ERPNext

**Version** : 1.0  
**Date** : 19 novembre 2025  
**Statut** : ⏳ À implémenter

## 🎯 Objectif

Déployer une base MariaDB Galera 3 nœuds avec ProxySQL pour ERPNext :
- Multi-master synchro (galera wsrep)
- Récupération automatique en cas de panne
- Parfaitement compatible ERPNext
- Accessible via LB Hetzner 10.0.0.20:3306

## 📋 Topologie

### Nœuds MariaDB Galera
- **maria-01** : 10.0.0.170 (Galera node 1 - bootstrap)
- **maria-02** : 10.0.0.171 (Galera node 2)
- **maria-03** : 10.0.0.172 (Galera node 3)

### Nœuds ProxySQL
- **proxysql-01** : 10.0.0.173 (ProxySQL #1)
- **proxysql-02** : 10.0.0.174 (ProxySQL #2)

### Load Balancer
- **LB Hetzner** : 10.0.0.20:3306 (point d'entrée unique pour ERPNext)

## 🔌 Ports

### MariaDB Galera
- **3306/tcp** : MariaDB
- **4444/tcp** : Galera SST (State Snapshot Transfer)
- **4567/tcp + UDP** : Galera replication (Primary cluster)
- **4568/tcp** : Galera IST (Incremental State Transfer)

### ProxySQL
- **6032/tcp** : Admin console
- **3306/tcp** : Frontend pour ERPNext

## 📦 Scripts (à créer)

1. **`07_maria_00_setup_credentials.sh`** : Configuration des credentials
2. **`07_maria_01_prepare_nodes.sh`** : Préparation des nœuds MariaDB
3. **`07_maria_02_deploy_galera.sh`** : Déploiement du cluster Galera
4. **`07_maria_03_install_proxysql.sh`** : Installation ProxySQL
5. **`07_maria_04_tests.sh`** : Tests et diagnostics
6. **`07_maria_apply_all.sh`** : Script master

## 🔧 Prérequis

- Module 2 appliqué sur tous les serveurs MariaDB et ProxySQL
- Docker CE opérationnel
- UFW configuré pour les ports Galera (réseau privé uniquement)
- Credentials configurés (`mariadb.env`)
- Volume XFS recommandé pour `/opt/keybuzz/mariadb/data`

## 📝 Notes Importantes

- **ERPNext uniquement** : ERPNext NE fonctionne PAS sous PostgreSQL, uniquement MariaDB/MySQL
- **ProxySQL obligatoire** : ERPNext DOIT utiliser ProxySQL, jamais directement le cluster
- **Multi-master** : Tous les nœuds peuvent accepter les écritures
- **LB Hetzner** : 10.0.0.20:3306 est le point d'entrée unique pour ERPNext

## 🔗 Références

- Documentation complète : `Context.txt` (section Module 7 - MariaDB Galera HA)
- Anciens scripts fonctionnels : `keybuzz-installer/scripts/11_MariaDB/` (si disponibles)

---

**Dernière mise à jour** : 19 novembre 2025  
**Statut** : ⏳ Structure créée, scripts à développer

