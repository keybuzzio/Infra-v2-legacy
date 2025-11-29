# 📋 Plan d'Installation Complète - Infrastructure KeyBuzz V2

**Date de création** : 2025-11-25  
**Version** : 2.0 (Réinstallation depuis serveurs vierges)  
**Statut** : 🟢 **PRÊT POUR DÉMARRAGE**

---

## 🎯 Objectif

Réinstaller complètement l'infrastructure KeyBuzz depuis des serveurs vierges, avec une documentation technique complète et détaillée pour chaque module, permettant une réinstallation fluide sans encombre.

---

## 📂 Structure de l'Espace de Travail

### Sur install-01

```
/opt/keybuzz-installer-v2/
├── inventory/
│   └── servers.tsv                    # Inventaire des serveurs (copie)
├── credentials/                        # Credentials (à créer)
│   ├── postgres.env
│   ├── redis.env
│   ├── rabbitmq.env
│   ├── minio.env
│   ├── mariadb.env
│   └── proxysql.env
├── scripts/                           # Scripts d'installation
│   ├── 00_master_install.sh          # Script maître
│   ├── 02_base_os_and_security/
│   ├── 03_postgresql_ha/
│   ├── 04_redis_ha/
│   ├── 05_rabbitmq_ha/
│   ├── 06_minio/
│   ├── 07_mariadb_galera/
│   ├── 08_proxysql_advanced/
│   └── 09_k3s_ha/
├── docs/                              # Documentation technique
│   ├── MODULE_02_BASE_OS.md
│   ├── MODULE_03_POSTGRESQL.md
│   ├── MODULE_04_REDIS.md
│   ├── MODULE_05_RABBITMQ.md
│   ├── MODULE_06_MINIO.md
│   ├── MODULE_07_MARIADB.md
│   ├── MODULE_08_PROXYSQL.md
│   └── MODULE_09_K3S.md
├── logs/                              # Logs d'installation
└── reports/                           # Rapports de validation
    ├── RAPPORT_VALIDATION_MODULE2.md
    ├── RAPPORT_VALIDATION_MODULE3.md
    ├── RAPPORT_VALIDATION_MODULE4.md
    ├── RAPPORT_VALIDATION_MODULE5.md
    ├── RAPPORT_VALIDATION_MODULE6.md
    ├── RAPPORT_VALIDATION_MODULE7.md
    ├── RAPPORT_VALIDATION_MODULE8.md
    └── RAPPORT_VALIDATION_MODULE9.md
```

---

## 📚 Modules d'Installation

### Module 2 : Base OS & Sécurité ⚠️ OBLIGATOIRE EN PREMIER

**Objectif** : Standardiser et sécuriser tous les serveurs avant l'installation des services applicatifs.

**Actions** :
1. Mise à jour système (apt update && apt upgrade)
2. Installation Docker (script officiel)
3. Désactivation du swap (obligatoire pour Patroni, RabbitMQ, K3s)
4. Configuration UFW (firewall)
5. Durcissement SSH
6. Configuration DNS fixe (1.1.1.1, 8.8.8.8)
7. Optimisations kernel (sysctl.conf)
8. Configuration journald

**Scripts** :
- `02_base_os_and_security/base_os.sh` - Script de base OS
- `02_base_os_and_security/apply_base_os_to_all.sh` - Application sur tous les serveurs

**Documentation** : `docs/MODULE_02_BASE_OS.md`

---

### Module 3 : PostgreSQL HA (Patroni RAFT)

**Objectif** : Cluster PostgreSQL haute disponibilité avec Patroni en mode RAFT.

**Architecture** :
- 3 nœuds : db-master-01, db-slave-01, db-slave-02
- Patroni RAFT (consensus distribué)
- HAProxy pour load balancing
- PgBouncer pour connection pooling

**Versions** :
- PostgreSQL : 16.x (image `postgres:16`)
- Patroni : 3.3.6+ (avec support RAFT)
- Python : 3.12.7 (compilé dans image Patroni)

**Scripts** :
- `03_postgresql_ha/03_pg_00_setup_credentials.sh`
- `03_postgresql_ha/03_pg_01_prepare_volumes.sh`
- `03_postgresql_ha/03_pg_02_install_patroni_cluster.sh`
- `03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh`
- `03_postgresql_ha/03_pg_04_install_pgbouncer.sh`
- `03_postgresql_ha/03_pg_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_03_POSTGRESQL.md`

---

### Module 4 : Redis HA (Sentinel)

**Objectif** : Cluster Redis haute disponibilité avec Sentinel pour failover automatique.

**Architecture** :
- 3 nœuds Redis : redis-01, redis-02, redis-03
- 3 instances Sentinel (une par nœud)
- HAProxy pour load balancing

**Versions** :
- Redis : 7.4.7 (image `redis:7-alpine`)
- Redis Sentinel : 7.4.7 (même image)

**Scripts** :
- `04_redis_ha/04_redis_00_setup_credentials.sh`
- `04_redis_ha/04_redis_01_prepare_nodes.sh`
- `04_redis_ha/04_redis_02_deploy_redis_cluster.sh`
- `04_redis_ha/04_redis_03_deploy_sentinel.sh`
- `04_redis_ha/04_redis_04_configure_haproxy_redis.sh`
- `04_redis_ha/04_redis_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_04_REDIS.md`

---

### Module 5 : RabbitMQ HA (Quorum)

**Objectif** : Cluster RabbitMQ haute disponibilité en mode Quorum.

**Architecture** :
- 3 nœuds : queue-01, queue-02, queue-03
- Cluster Quorum
- HAProxy pour load balancing

**Versions** :
- RabbitMQ : 3.12-management (image `rabbitmq:3.12-management`)

**Scripts** :
- `05_rabbitmq_ha/05_rmq_00_setup_credentials.sh`
- `05_rabbitmq_ha/05_rmq_01_prepare_nodes.sh`
- `05_rabbitmq_ha/05_rmq_02_deploy_cluster.sh`
- `05_rabbitmq_ha/05_rmq_03_configure_haproxy.sh`
- `05_rabbitmq_ha/05_rmq_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_05_RABBITMQ.md`

---

### Module 6 : MinIO S3 (Cluster 3 Nœuds)

**Objectif** : Cluster MinIO distribué pour stockage objet S3.

**Architecture** :
- 3 nœuds : minio-01, minio-02, minio-03
- Mode distribué avec erasure coding
- 1 pool, 1 set, 3 drives per set

**Versions** :
- MinIO : RELEASE.2024-10-02T10-00Z (image `minio/minio:RELEASE.2024-10-02T10-00Z`)

**Scripts** :
- `06_minio/06_minio_00_setup_credentials.sh`
- `06_minio/06_minio_01_deploy_minio_distributed.sh`
- `06_minio/06_minio_02_configure_client.sh`
- `06_minio/06_minio_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_06_MINIO.md`

---

### Module 7 : MariaDB Galera HA

**Objectif** : Cluster MariaDB haute disponibilité en mode multi-master (Galera).

**Architecture** :
- 3 nœuds : maria-01, maria-02, maria-03
- Cluster Galera multi-master
- ProxySQL pour load balancing (2 nœuds)

**Versions** :
- MariaDB : 10.11.6 (image `bitnami/mariadb-galera:10.11.6`)
- ProxySQL : 2.6.4 (image `proxysql/proxysql:2.6.4`)

**Scripts** :
- `07_mariadb_galera/07_maria_00_setup_credentials.sh`
- `07_mariadb_galera/07_maria_01_prepare_nodes.sh`
- `07_mariadb_galera/07_maria_02_deploy_galera.sh`
- `07_mariadb_galera/07_maria_03_install_proxysql.sh`
- `07_mariadb_galera/07_maria_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_07_MARIADB.md`

---

### Module 8 : ProxySQL Advanced

**Objectif** : Configuration avancée de ProxySQL avec optimisations Galera.

**Architecture** :
- 2 nœuds ProxySQL : proxysql-01, proxysql-02
- Configuration avancée pour ERPNext
- Monitoring et optimisations

**Scripts** :
- `08_proxysql_advanced/08_proxysql_01_generate_config.sh`
- `08_proxysql_advanced/08_proxysql_02_apply_config.sh`
- `08_proxysql_advanced/08_proxysql_03_optimize_galera.sh`
- `08_proxysql_advanced/08_proxysql_04_monitoring_setup.sh`
- `08_proxysql_advanced/08_proxysql_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_08_PROXYSQL.md`

---

### Module 9 : Kubernetes HA Core (K8s) ⚠️ IMPORTANT : K8s DIRECT, PAS K3s

**Objectif** : Cluster Kubernetes haute disponibilité avec Kubernetes complet (K8s).

**⚠️ PRIMORDIAL** : Installation directe de K8s, PAS de K3s. Tout est vierge, on installe proprement K8s dès le départ.

**Architecture** :
- 3 masters : k8s-master-01, k8s-master-02, k8s-master-03
- 5 workers : k8s-worker-01 à k8s-worker-05
- CNI : Calico IPIP (pour Hetzner Cloud)
- Ingress NGINX (DaemonSet + hostNetwork)
- Prometheus Stack

**Versions** :
- Kubernetes : 1.30.x (via Kubespray ou kubeadm)
- Calico : 3.27.0 (IPIP mode, VXLAN désactivé)
- kube-proxy : iptables mode

**Méthode d'installation** :
- Option A : Kubespray (recommandé pour HA)
- Option B : kubeadm (si Kubespray non disponible)

**Scripts** :
- `09_k8s_ha/09_k8s_01_prepare.sh` - Préparation (swap, kernel, etc.)
- `09_k8s_ha/09_k8s_02_install_kubespray.sh` - Installation Kubespray
- `09_k8s_ha/09_k8s_03_configure_inventory.sh` - Configuration inventaire
- `09_k8s_ha/09_k8s_04_deploy_cluster.sh` - Déploiement cluster K8s
- `09_k8s_ha/09_k8s_05_configure_calico_ipip.sh` - Configuration Calico IPIP
- `09_k8s_ha/09_k8s_06_ingress_daemonset.sh` - Ingress NGINX
- `09_k8s_ha/09_k8s_07_install_monitoring.sh` - Prometheus Stack
- `09_k8s_ha/09_k8s_apply_all.sh` - Script maître

**Documentation** : `docs/MODULE_09_K8S.md`

**⚠️ RÈGLES STRICTES** :
- ❌ NE PAS installer K3s
- ❌ NE PAS utiliser Flannel
- ✅ Installer K8s complet directement
- ✅ Utiliser Calico IPIP (VXLAN désactivé)
- ✅ Configuration conforme Hetzner Cloud

---

## 🔄 Processus d'Installation

### Phase 1 : Préparation

1. **Créer l'espace de travail sur install-01**
   ```bash
   mkdir -p /opt/keybuzz-installer-v2/{inventory,credentials,scripts,docs,logs,reports}
   ```

2. **Copier l'inventaire**
   ```bash
   cp /path/to/servers.tsv /opt/keybuzz-installer-v2/inventory/
   ```

3. **Vérifier l'accès SSH à tous les serveurs**
   ```bash
   ./scripts/00_check_ssh_access_all_servers.sh
   ```

### Phase 2 : Installation Module par Module

**Ordre obligatoire** :
1. ✅ Module 2 : Base OS & Sécurité (OBLIGATOIRE EN PREMIER)
2. ✅ Module 3 : PostgreSQL HA
3. ✅ Module 4 : Redis HA
4. ✅ Module 5 : RabbitMQ HA
5. ✅ Module 6 : MinIO S3
6. ✅ Module 7 : MariaDB Galera
7. ✅ Module 8 : ProxySQL Advanced
8. ✅ Module 9 : K3s HA Core

**Pour chaque module** :
1. Exécuter le script `*_apply_all.sh`
2. Valider avec le script de validation
3. Générer le rapport de validation
4. Documenter dans `docs/MODULE_XX_*.md`

---

## 📝 Documentation Requise

### Pour chaque module, créer :

1. **Documentation technique** (`docs/MODULE_XX_*.md`) :
   - Architecture détaillée
   - Versions utilisées
   - Configuration complète
   - Commandes d'installation
   - Commandes de vérification
   - Dépannage

2. **Rapport de validation** (`reports/RAPPORT_VALIDATION_MODULEXX.md`) :
   - Résumé exécutif
   - Composants validés
   - Tests effectués
   - Résultats
   - Points d'attention
   - Conclusion

3. **Scripts d'installation** :
   - Scripts modulaires et idempotents
   - Gestion d'erreurs
   - Logs détaillés
   - Validation automatique

---

## ✅ Checklist de Validation

### Après chaque module :

- [ ] Scripts exécutés sans erreur
- [ ] Services opérationnels
- [ ] Tests de connectivité réussis
- [ ] Documentation technique créée
- [ ] Rapport de validation généré
- [ ] Logs archivés

### Validation finale :

- [ ] Tous les modules installés
- [ ] Tous les tests réussis
- [ ] Documentation complète
- [ ] Rapports de validation générés
- [ ] Infrastructure prête pour production

---

## 🚀 Démarrage

### 1. Se connecter à install-01

```bash
ssh root@install-01
```

### 2. Créer l'espace de travail

```bash
mkdir -p /opt/keybuzz-installer-v2/{inventory,credentials,scripts,docs,logs,reports}
```

### 3. Copier les fichiers nécessaires

```bash
# Copier servers.tsv
cp /path/to/servers.tsv /opt/keybuzz-installer-v2/inventory/

# Copier les scripts (depuis le dépôt local ou GitHub)
# ...
```

### 4. Commencer par le Module 2

```bash
cd /opt/keybuzz-installer-v2/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../inventory/servers.tsv
```

---

## 📊 Suivi de l'Installation

Un document de suivi sera créé : `SUIVI_INSTALLATION_V2.md`

Il contiendra :
- État de chaque module (⏳ En cours / ✅ Terminé / ❌ Erreur)
- Dates d'installation
- Problèmes rencontrés et solutions
- Notes importantes

---

**Ce plan sera mis à jour au fur et à mesure de l'avancement de l'installation.**

