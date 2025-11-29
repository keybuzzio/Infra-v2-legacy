# Journal Détaillé d'Installation - KeyBuzz Infrastructure

**Date de début :** $(date '+%Y-%m-%d %H:%M:%S')  
**Méthode :** Installation module par module avec validation  
**Objectif :** Installation complète et propre de l'infrastructure KeyBuzz depuis zéro

---

## Table des Matières

1. [Préparation](#préparation)
2. [Nettoyage Complet](#nettoyage-complet)
3. [Installation Module par Module](#installation-module-par-module)
4. [Erreurs Rencontrées et Corrections](#erreurs-rencontrées-et-corrections)
5. [Validation Finale](#validation-finale)

---

## Préparation

### Étape 1.1 : Vérification des Prérequis

- [ ] Fichier `servers.tsv` présent et valide
- [ ] Clé SSH `keybuzz_infra` accessible
- [ ] Accès SSH à install-01 vérifié
- [ ] Tous les serveurs accessibles depuis install-01

### Étape 1.2 : Création des Dossiers

**Sur install-01 :**
- `/opt/keybuzz-installer/scripts`
- `/opt/keybuzz-installer/credentials`
- `/opt/keybuzz-installer/logs`
- `/opt/keybuzz-installer/tmp`
- `/opt/keybuzz-installer/inventory`

**Sur tous les serveurs :**
- `/opt/keybuzz-installer/credentials` (permissions 700)
- Dossiers spécifiques selon le rôle (postgres, redis, rabbitmq, etc.)

### Étape 1.3 : Préparation des Scripts

- [ ] Script de nettoyage : `00_cleanup_complete_installation.sh`
- [ ] Script d'installation : `00_install_module_by_module.sh`
- [ ] Tous les scripts de modules présents et exécutables

---

## Nettoyage Complet

### Objectif
Supprimer TOUTES les données pour permettre une réinstallation propre depuis zéro.

### Actions Effectuées

#### Sur chaque serveur (sauf install-01 et backn8n) :

1. **Arrêt des conteneurs Docker**
   ```bash
   docker stop $(docker ps -q)
   docker rm $(docker ps -aq)
   ```

2. **Suppression des images Docker**
   ```bash
   docker images --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi -f
   ```

3. **Nettoyage des volumes Docker**
   ```bash
   docker volume prune -f
   docker network prune -f
   ```

4. **Formatage des volumes XFS**
   - Détection du périphérique (généralement `/dev/sdb`, `/dev/sdc`, etc.)
   - Démontage si monté
   - Suppression de l'entrée fstab
   - Formatage en XFS : `mkfs.xfs -f /dev/sdX`
   - **ATTENTION : Toutes les données sont supprimées**

5. **Nettoyage des fichiers de configuration**
   ```bash
   rm -rf /opt/keybuzz/*
   rm -rf /etc/patroni
   rm -rf /etc/redis
   rm -rf /etc/rabbitmq
   rm -rf /etc/mariadb
   rm -rf /etc/minio
   rm -rf /etc/haproxy
   rm -rf /etc/pgbouncer
   rm -rf /etc/proxysql
   ```

6. **Désactivation des services systemd**
   ```bash
   systemctl stop patroni-docker redis-docker rabbitmq-docker mariadb-docker
   systemctl disable patroni-docker redis-docker rabbitmq-docker mariadb-docker
   rm -f /etc/systemd/system/*patroni*.service
   rm -f /etc/systemd/system/*redis*.service
   rm -f /etc/systemd/system/*rabbitmq*.service
   rm -f /etc/systemd/system/*mariadb*.service
   systemctl daemon-reload
   ```

#### Sur install-01 :

- Nettoyage des logs et fichiers temporaires
- **CONSERVATION des credentials (.env)**

### Résultat Attendu

- ✅ Tous les conteneurs Docker arrêtés et supprimés
- ✅ Tous les volumes XFS formatés (données supprimées)
- ✅ Tous les fichiers de configuration nettoyés
- ✅ Tous les services systemd désactivés
- ✅ Credentials (.env) CONSERVÉS sur install-01

---

## Installation Module par Module

### Module 2 : Base OS and Security

**Script :** `02_base_os_and_security/apply_base_os_to_all.sh`

**Actions :**
- Configuration de base du système d'exploitation
- Configuration UFW (firewall)
- Installation des outils de base
- Configuration SSH

**Validation :**
- [ ] Tous les serveurs accessibles
- [ ] UFW configuré correctement
- [ ] Outils de base installés

**Logs :** `${LOG_DIR}/module_2_install.log`

---

### Module 3 : PostgreSQL HA

**Script :** `03_postgresql_ha/03_pg_apply_all.sh`

**Sous-étapes :**
1. `03_pg_00_setup_credentials.sh` - Génération des credentials
2. `03_pg_02_install_patroni_cluster.sh` - Installation du cluster Patroni
3. `03_pg_03_install_haproxy_db_lb.sh` - Configuration HAProxy
4. `03_pg_04_install_pgbouncer.sh` - Installation PgBouncer
5. `03_pg_05_install_pgvector.sh` - Installation pgvector

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/postgres.env`
- Copié sur : install-01, postgres-01, postgres-02, postgres-03, haproxy-01, haproxy-02

**Validation :**
- [ ] Cluster Patroni opérationnel (3 nœuds)
- [ ] HAProxy fonctionnel
- [ ] PgBouncer opérationnel
- [ ] pgvector installé
- [ ] Tests de failover réussis

**Logs :** `${LOG_DIR}/module_3_install.log`, `${LOG_DIR}/module_3_test.log`

---

### Module 4 : Redis HA

**Script :** `04_redis_ha/04_redis_apply_all.sh`

**Sous-étapes :**
1. `04_redis_00_setup_credentials.sh` - Génération des credentials
2. `04_redis_01_prepare_nodes.sh` - Préparation des nœuds
3. `04_redis_02_deploy_redis_cluster.sh` - Déploiement Redis
4. `04_redis_03_deploy_sentinel.sh` - Déploiement Sentinel
5. `04_redis_04_configure_haproxy_redis.sh` - Configuration HAProxy + Watcher
6. `04_redis_05_configure_lb_healthcheck.sh` - Configuration LB healthcheck

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/redis.env`
- Copié sur : install-01, redis-01, redis-02, redis-03, haproxy-01, haproxy-02

**Points Critiques :**
- ✅ Watcher Sentinel INDISPENSABLE (corrigé dans CORRECTIONS_ET_ERREURS.md)
- ✅ Authentification Redis requise
- ✅ Variables correctement passées dans heredoc

**Validation :**
- [ ] Redis master/replica opérationnel
- [ ] Sentinel opérationnel (3 instances)
- [ ] HAProxy + Watcher fonctionnels
- [ ] Tests de failover réussis

**Logs :** `${LOG_DIR}/module_4_install.log`, `${LOG_DIR}/module_4_test.log`

---

### Module 5 : RabbitMQ HA

**Script :** `05_rabbitmq_ha/05_rmq_apply_all.sh`

**Sous-étapes :**
1. `05_rmq_00_setup_credentials.sh` - Génération des credentials (Erlang Cookie)
2. `05_rmq_01_prepare_nodes.sh` - Préparation des nœuds
3. `05_rmq_02_deploy_cluster.sh` - Déploiement cluster quorum
4. `05_rmq_03_configure_haproxy.sh` - Configuration HAProxy

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/rabbitmq.env`
- Copié sur : install-01, rabbitmq-01, rabbitmq-02, rabbitmq-03, haproxy-01, haproxy-02

**Points Critiques :**
- ✅ Erlang Cookie identique sur tous les nœuds
- ✅ Cluster quorum pour haute disponibilité

**Validation :**
- [ ] Cluster RabbitMQ opérationnel (3 nœuds)
- [ ] HAProxy fonctionnel
- [ ] Tests de failover réussis

**Logs :** `${LOG_DIR}/module_5_install.log`, `${LOG_DIR}/module_5_test.log`

---

### Module 6 : MinIO

**Script :** `06_minio/06_minio_apply_all.sh`

**Sous-étapes :**
1. `06_minio_00_setup_credentials.sh` - Génération des credentials
2. `06_minio_01_prepare_nodes.sh` - Préparation des nœuds
3. `06_minio_02_install_single.sh` - Installation mono-nœud (puis cluster)
4. `06_minio_03_configure_client.sh` - Configuration client mc

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/minio.env`
- Copié sur : install-01, minio-01 (et autres nœuds si cluster)

**Validation :**
- [ ] MinIO opérationnel
- [ ] Client mc configuré
- [ ] Tests de connexion réussis

**Logs :** `${LOG_DIR}/module_6_install.log`, `${LOG_DIR}/module_6_test.log`

---

### Module 7 : MariaDB Galera HA

**Script :** `07_mariadb_galera/07_maria_apply_all.sh`

**Sous-étapes :**
1. `07_maria_00_setup_credentials.sh` - Génération des credentials
2. `07_maria_01_prepare_nodes.sh` - Préparation des nœuds
3. `07_maria_02_deploy_galera_cluster.sh` - Déploiement cluster Galera
4. `07_maria_03_configure_lb.sh` - Configuration LB

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/mariadb.env`
- Copié sur : install-01, mariadb-01, mariadb-02, mariadb-03

**Points Critiques :**
- ✅ Cluster Galera multi-master
- ✅ Synchronisation synchrone

**Validation :**
- [ ] Cluster Galera opérationnel (3 nœuds)
- [ ] LB fonctionnel
- [ ] Tests de failover réussis

**Logs :** `${LOG_DIR}/module_7_install.log`, `${LOG_DIR}/module_7_test.log`

---

### Module 8 : ProxySQL Advanced

**Script :** `08_proxysql_advanced/08_proxysql_apply_all.sh`

**Sous-étapes :**
1. `08_proxysql_00_setup_credentials.sh` - Génération des credentials
2. `08_proxysql_01_prepare_nodes.sh` - Préparation des nœuds
3. `08_proxysql_02_deploy_proxysql.sh` - Déploiement ProxySQL
4. `08_proxysql_03_configure_backends.sh` - Configuration backends MariaDB
5. `08_proxysql_04_monitoring_setup.sh` - Configuration monitoring

**Credentials :**
- Fichier : `/opt/keybuzz-installer/credentials/proxysql.env`
- Copié sur : install-01, proxysql-01, proxysql-02

**Validation :**
- [ ] ProxySQL opérationnel (2 instances)
- [ ] Backends MariaDB configurés
- [ ] Monitoring fonctionnel

**Logs :** `${LOG_DIR}/module_8_install.log`, `${LOG_DIR}/module_8_test.log`

---

### Module 9 : K3s HA Core

**Script :** `09_k3s_ha/09_k3s_apply_all.sh`

**Sous-étapes :**
1. `09_k3s_01_fix_ufw_networks.sh` - Configuration UFW pour K3s
2. `09_k3s_02_install_masters.sh` - Installation 3 masters
3. `09_k3s_03_join_workers.sh` - Ajout des workers
4. `09_k3s_04_bootstrap_addons.sh` - Bootstrap des addons
5. `09_k3s_05_ingress_daemonset.sh` - Ingress NGINX DaemonSet

**Points Critiques :**
- ✅ Solution Validée : DaemonSet + hostNetwork (contourne VXLAN bloqué)
- ✅ Ingress NGINX en DaemonSet avec hostNetwork: true
- ✅ NodePort pour HTTP/HTTPS (31695)

**Validation :**
- [ ] Cluster K3s opérationnel (3 masters + N workers)
- [ ] Ingress NGINX fonctionnel
- [ ] CoreDNS fonctionnel
- [ ] StorageClass configuré

**Logs :** `${LOG_DIR}/module_9_install.log`, `${LOG_DIR}/module_9_test.log`

---

### Module 10 : KeyBuzz API & Front

**Script :** `10_keybuzz/10_keybuzz_apply_all.sh`

**Sous-étapes :**
1. `10_keybuzz_01_deploy_daemonsets.sh` - Déploiement API et Front en DaemonSet
2. Configuration Ingress
3. Tests de connectivité

**Points Critiques :**
- ✅ DaemonSet + hostNetwork: true
- ✅ NodePort pour exposition
- ✅ URLs : platform.keybuzz.io et platform-api.keybuzz.io

**Validation :**
- [ ] API KeyBuzz accessible
- [ ] Front KeyBuzz accessible
- [ ] Ingress fonctionnel
- [ ] Healthchecks OK

**Logs :** `${LOG_DIR}/module_10_install.log`, `${LOG_DIR}/module_10_test.log`

---

### Module 11 : n8n

**Script :** `11_n8n/11_n8n_apply_all.sh`

**Sous-étapes :**
1. `11_n8n_00_setup_credentials.sh` - Génération des credentials
2. `11_n8n_01_deploy.sh` - Déploiement n8n en DaemonSet
3. Configuration Ingress
4. Tests de connectivité

**Points Critiques :**
- ✅ DaemonSet + hostNetwork: true
- ✅ Connexion à PostgreSQL via PgBouncer
- ✅ Connexion à Redis

**Validation :**
- [ ] n8n accessible
- [ ] Connexion DB OK
- [ ] Connexion Redis OK
- [ ] Ingress fonctionnel

**Logs :** `${LOG_DIR}/module_11_install.log`, `${LOG_DIR}/module_11_test.log`

---

## Erreurs Rencontrées et Corrections

Toutes les erreurs sont documentées dans `CORRECTIONS_ET_ERREURS.md`.

### Erreurs Critiques Corrigées

1. **Watcher Sentinel Redis** - Authentification manquante
2. **Variables non définies** - Heredoc avec variables
3. **Fichiers manquants** - Dossiers non créés avant utilisation
4. **Credentials non copiés** - Scripts de copie manquants

---

## Validation Finale

### Tests Complets

Exécuter : `00_test_complet_infrastructure.sh`

**Vérifications :**
- [ ] PostgreSQL HA opérationnel
- [ ] Redis HA opérationnel
- [ ] RabbitMQ HA opérationnel
- [ ] MinIO opérationnel
- [ ] MariaDB Galera opérationnel
- [ ] ProxySQL opérationnel
- [ ] K3s cluster opérationnel
- [ ] KeyBuzz API/Front accessibles
- [ ] n8n accessible
- [ ] Tous les failovers testés

### Documentation Finale

- [ ] `CORRECTIONS_ET_ERREURS.md` à jour
- [ ] `INSTALLATION_DETAILED_LOG.md` complété
- [ ] `00_master_install.sh` mis à jour avec les corrections
- [ ] Tous les scripts validés

---

## Notes Importantes

1. **Aucune erreur n'est "petite"** - Toutes doivent être corrigées
2. **Le watcher Sentinel est INDISPENSABLE** - Ne jamais le rendre optionnel
3. **Documenter toutes les corrections** - Pour éviter de retomber sur les mêmes problèmes
4. **Tester tous les failovers** - Avant de considérer l'installation comme complète
5. **Credentials toujours sauvegardés** - Sur install-01 ET sur les serveurs concernés

---

**Date de fin :** $(date '+%Y-%m-%d %H:%M:%S')  
**Statut :** [ ] En cours [ ] Terminé [ ] Échec

