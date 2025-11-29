# Module 7 - MariaDB Galera HA pour ERPNext - Validation

**Date** : 19 novembre 2025  
**Statut** : ✅ Opérationnel et Validé

## Résumé

Le Module 7 (MariaDB Galera HA pour ERPNext) a été installé et validé avec succès. Le cluster Galera 3 nœuds est opérationnel, ProxySQL est déployé sur 2 nœuds, et le LB Hetzner 10.0.0.20:3306 est configuré et accessible.

## Composants installés

### MariaDB Galera Cluster
- **3 nœuds Galera** : maria-01 (10.0.0.170), maria-02 (10.0.0.171), maria-03 (10.0.0.172)
- **Version** : panubo/mariadb-galera:latest
- **Mode** : Multi-master synchro (wsrep)
- **Network** : --network host
- **Cluster Name** : keybuzz-galera
- **Database** : erpnext
- **User** : erpnext

### ProxySQL
- **2 nœuds ProxySQL** : proxysql-01 (10.0.0.173), proxysql-02 (10.0.0.174)
- **Version** : proxysql/proxysql:latest
- **Frontend** : 0.0.0.0:3306
- **Admin** : 0.0.0.0:6032 (admin/admin)
- **Backend** : 3 nœuds Galera (hostgroup 10)

### Load Balancer Hetzner
- **IP** : 10.0.0.20:3306
- **Targets** : proxysql-01:3306, proxysql-02:3306
- **Health Check** : TCP simple
- **Statut** : ✅ Accessible et opérationnel

## Points d'accès

- **Pour ERPNext** : 10.0.0.20:3306 (LB Hetzner) ✅
- **ProxySQL direct** : 10.0.0.173:3306, 10.0.0.174:3306 ✅
- **MariaDB direct** : 10.0.0.170:3306, 10.0.0.171:3306, 10.0.0.172:3306 (non recommandé)
- **ProxySQL Admin** : 10.0.0.173:6032, 10.0.0.174:6032 (admin/admin) ✅

## Credentials

- **Root Password** : Généré automatiquement (stocké dans `/opt/keybuzz-installer/credentials/mariadb.env`)
- **App User** : erpnext
- **App Password** : Généré automatiquement
- **Database** : erpnext

## Tests effectués

✅ **Cluster Galera** : 3 nœuds synchronisés (wsrep_cluster_size=3)  
✅ **Statut Galera** : Tous les nœuds en "Synced" et "Ready"  
✅ **Connectivité Galera** : Ports 3306, 4567 accessibles sur tous les nœuds  
✅ **ProxySQL** : 2 nœuds déployés et configurés  
✅ **ProxySQL Backend** : 3 nœuds Galera configurés dans ProxySQL  
✅ **ProxySQL Connectivité** : Ports 3306 (frontend) et 6032 (admin) accessibles  
✅ **LB Hetzner** : 10.0.0.20:3306 configuré et accessible  
✅ **Compatibilité** : Compatible avec tous les autres modules (PostgreSQL, Redis, RabbitMQ, MinIO)

## Scripts disponibles

1. `07_maria_00_setup_credentials.sh` - Configuration des credentials
2. `07_maria_01_prepare_nodes.sh` - Préparation des nœuds MariaDB
3. `07_maria_02_deploy_galera.sh` - Déploiement du cluster Galera
4. `07_maria_03_install_proxysql.sh` - Installation ProxySQL
5. `07_maria_04_tests.sh` - Tests et diagnostics
6. `07_maria_apply_all.sh` - Script master

## Commandes utiles

### Vérifier le statut du cluster
```bash
docker exec mariadb mysql -uroot -p<PASSWORD> -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
docker exec mariadb mysql -uroot -p<PASSWORD> -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"
```

### Vérifier ProxySQL
```bash
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT * FROM mysql_servers;"
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT * FROM stats_mysql_connection_pool;"
```

### Tester la connexion via ProxySQL
```bash
mysql -uerpnext -p<PASSWORD> -h10.0.0.173 -P3306 erpnext
```

### Tester via LB Hetzner
```bash
mysql -uerpnext -p<PASSWORD> -h10.0.0.20 -P3306 erpnext
```

## Configuration ERPNext

Dans `site_config.json` d'ERPNext :
```json
{
  "db_type": "mariadb",
  "db_name": "erpnext",
  "db_password": "<MARIADB_APP_PASSWORD>",
  "db_host": "10.0.0.20",
  "db_port": "3306"
}
```

## Notes importantes

- **ERPNext uniquement** : ERPNext NE fonctionne PAS sous PostgreSQL, uniquement MariaDB/MySQL
- **ProxySQL obligatoire** : ERPNext DOIT utiliser ProxySQL (via LB Hetzner), jamais directement le cluster
- **Multi-master** : Tous les nœuds peuvent accepter les écritures
- **LB Hetzner** : 10.0.0.20:3306 est le point d'entrée unique pour ERPNext
- **Image Docker** : Utilisation de `panubo/mariadb-galera:latest` (bitnami n'existe pas)
- **ProxySQL Version** : Utilisation de `proxysql/proxysql:latest` (2.6 n'existe pas)

## Intégration avec autres modules

✅ **Module 3 (PostgreSQL)** : MariaDB Galera est indépendant (ERPNext uniquement)  
   - PostgreSQL HA : 10.0.0.11:5432 (HAProxy) - ✅ Accessible  
   - Pas de conflit de ports (PostgreSQL 5432, MariaDB 3306)  

✅ **Module 4 (Redis)** : Compatible  
   - Redis HA : 10.0.0.11:6379 (HAProxy) - ✅ Accessible  
   - Pas de conflit de ports  

✅ **Module 5 (RabbitMQ)** : Compatible  
   - RabbitMQ HA : 10.0.0.11:5672 (HAProxy) - ✅ Accessible  
   - Pas de conflit de ports  

✅ **Module 6 (MinIO)** : Compatible (backups possibles)  
   - MinIO S3 : 10.0.0.134:9000 - ✅ Accessible  
   - Peut stocker les backups MariaDB  

✅ **Réseau** : Tous les services sur le réseau privé 10.0.0.0/16  
✅ **Isolation** : Chaque service utilise ses propres ports, pas de conflit

## Validation de connectivité

### ProxySQL
- ✅ proxysql-01:3306 (frontend) - Accessible
- ✅ proxysql-01:6032 (admin) - Accessible
- ✅ proxysql-02:3306 (frontend) - Accessible
- ✅ proxysql-02:6032 (admin) - Accessible
- ✅ LB Hetzner 10.0.0.20:3306 - Accessible

### Compatibilité services
- ✅ PostgreSQL HA (10.0.0.11:5432) - Accessible
- ✅ Redis HA (10.0.0.11:6379) - Accessible
- ✅ RabbitMQ HA (10.0.0.11:5672) - Accessible
- ✅ MinIO S3 (10.0.0.134:9000) - Accessible
- ✅ MariaDB Galera (10.0.0.20:3306) - Accessible

---

**Dernière mise à jour** : 19 novembre 2025  
**Validé par** : Scripts automatisés et tests manuels  
**Master script** : ✅ À jour avec Module 7
