# Module 3 - PostgreSQL HA avec Patroni RAFT

## Scripts principaux (à utiliser)

### Installation complète
- **`03_pg_apply_all.sh`** : Script master qui exécute tous les scripts dans le bon ordre

### Scripts d'installation (dans l'ordre)
1. **`03_pg_00_setup_credentials.sh`** : Configuration des credentials PostgreSQL et Patroni
2. **`03_pg_02_install_patroni_cluster.sh`** : Installation du cluster Patroni RAFT (PostgreSQL 16 + Python 3.12)
3. **`03_pg_03_install_haproxy_db_lb.sh`** : Installation HAProxy pour load balancing
4. **`03_pg_04_install_pgbouncer.sh`** : Installation PgBouncer pour connection pooling
5. **`03_pg_05_install_pgvector.sh`** : Installation de l'extension pgvector
6. **`03_pg_06_diagnostics.sh`** : Diagnostics et tests finaux

### Scripts utilitaires
- **`reinit_cluster.sh`** : Réinitialisation complète du cluster (nettoyage données + redémarrage)
- **`check_module3_status.sh`** : Vérification de l'état de tous les services Module 3
- **`check_build_status.sh`** : Vérification de l'état de construction des images Docker
- **`03_pg_07_test_failover_safe.sh`** : Test de failover automatique (sûr et réversible)

## Architecture

- **PostgreSQL 16** : Base de données
- **Python 3.12.7** : Compilé depuis les sources pour Patroni
- **Patroni 4.1.0** : Gestionnaire de haute disponibilité avec RAFT
- **psycopg2-binary 2.9.11** : Driver PostgreSQL pour Python
- **pgvector** : Extension pour recherches vectorielles

## Nœuds

- **db-master-01** (10.0.0.120) : Leader
- **db-slave-01** (10.0.0.121) : Replica
- **db-slave-02** (10.0.0.122) : Replica

## Configuration

- **Cluster name** : `keybuzz-pg`
- **RAFT** : Port 7000 sur chaque nœud
- **PostgreSQL** : Port 5432
- **Patroni API** : Port 8008
- **HAProxy** : Port 5432 (load balancing)
- **PgBouncer** : Port 6432 (connection pooling)

## Scripts obsolètes (à supprimer)

Ces scripts sont des versions de debug/temporaires et ne doivent plus être utilisés :
- `03_pg_02_install_patroni_cluster_FIXED.sh`
- `fix_*.sh`
- `clean_*.sh`
- `start_patroni_cluster.sh`
- `prepare_volumes_replicas.sh`
- `fix_replicas*.sh`
- `force_clean_and_start.sh`
- `fix_config_and_reinit.sh`

