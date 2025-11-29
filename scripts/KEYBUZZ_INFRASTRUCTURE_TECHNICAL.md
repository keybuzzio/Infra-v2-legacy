# KeyBuzz Infrastructure - Document Technique Complet

**Date** : 20 novembre 2025  
**Version** : 1.3  
**Statut** : ✅ Infrastructure opérationnelle

## 📋 Résumé Exécutif

Ce document technique détaille l'architecture complète de l'infrastructure KeyBuzz, incluant tous les modules installés, leurs configurations, leurs points d'accès, et leurs intégrations. Il sert de référence complète pour la compréhension, la maintenance, et l'audit de l'infrastructure.

## 🏗️ Architecture Globale

### Topologie Réseau
- **Réseau privé** : 10.0.0.0/16
- **Load Balancers Hetzner internes** :
  - 10.0.0.10 : PostgreSQL HA (HAProxy)
  - 10.0.0.20 : MariaDB Galera HA (ProxySQL)
- **Isolation** : Tous les services sur réseau privé uniquement

### Modules Installés

| Module | Composants | Statut | Documentation |
|--------|-----------|--------|---------------|
| Module 2 | Base OS & Sécurité | ✅ | Intégré dans scripts |
| Module 3 | PostgreSQL HA | ✅ | `03_postgresql_ha/MODULE3_VALIDATION.md` |
| Module 4 | Redis HA | ✅ | `04_redis_ha/MODULE4_VALIDATION.md` |
| Module 5 | RabbitMQ HA | ✅ | `05_rabbitmq_ha/MODULE5_VALIDATION.md` |
| Module 6 | MinIO S3 HA | ✅ | `06_minio/MODULE6_VALIDATION.md` |
| Module 7 | MariaDB Galera HA | ✅ | `07_mariadb_galera/MODULE7_VALIDATION.md` |
| Module 8 | ProxySQL Avancé & Optimisation Galera | ✅ | `08_proxysql_advanced/MODULE8_VALIDATION.md` |
| Module 9 | K3s HA Core | ✅ | `09_k3s_ha/MODULE9_VALIDATION.md` |
| Module 10 | KeyBuzz API & Front | ✅ | `10_keybuzz/MODULE10_VALIDATION.md` |
| Module 9 | K3s HA Core | ✅ | `09_k3s_ha/MODULE9_VALIDATION.md` |
| Module 10 | KeyBuzz API & Front | ✅ | `10_keybuzz/README.md` |

---

## 📦 Module 2 - Base OS & Sécurité

### Objectif
Standardisation Ubuntu sur tous les nœuds avec durcissement SSH, UFW, et configuration de base.

### Composants
- Ubuntu 22.04 LTS
- Docker CE
- UFW (firewall)
- Swap désactivé
- Configuration SSH sécurisée

### Scripts
- `02_base_os_and_security/apply_base_os_to_all.sh`

### Validation
- Tous les nœuds standardisés
- UFW configuré
- Docker CE installé

---

## 🗄️ Module 3 - PostgreSQL HA

### Objectif
Cluster PostgreSQL hautement disponible avec Patroni RAFT (3 nœuds).

### Architecture
- **3 nœuds PostgreSQL** : db-master-01, db-slave-01, db-slave-02
- **Patroni RAFT** : Consensus pour failover automatique
- **HAProxy** : Load balancing (2 nœuds)
- **LB Hetzner** : 10.0.0.10:5432

### Points d'Accès
- **PostgreSQL** : 10.0.0.10:5432 (LB Hetzner via HAProxy)
- **PgBouncer** : 10.0.0.10:6432 (connection pooling)

### Scripts
1. `03_pg_00_setup_credentials.sh`
2. `03_pg_01_prepare_nodes.sh`
3. `03_pg_02_install_patroni_cluster.sh`
4. `03_pg_03_install_pgbouncer.sh`
5. `03_pg_04_configure_haproxy.sh`
6. `03_pg_05_configure_lb_healthcheck.sh`
7. `03_pg_06_tests.sh`
8. `03_pg_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/03_postgresql_ha/MODULE3_VALIDATION.md`

---

## 🔴 Module 4 - Redis HA

### Objectif
Cluster Redis hautement disponible avec Sentinel pour failover automatique.

### Architecture
- **3 nœuds Redis** : redis-01 (master), redis-02, redis-03 (replicas)
- **Sentinel** : 3 instances pour monitoring et failover
- **HAProxy** : Load balancing (partagé avec PostgreSQL)
- **LB Hetzner** : 10.0.0.10 (partagé)

### Points d'Accès
- **Redis** : 10.0.0.10:6379 (LB Hetzner via HAProxy)

### Scripts
1. `04_redis_00_setup_credentials.sh`
2. `04_redis_01_prepare_nodes.sh`
3. `04_redis_02_deploy_redis_cluster.sh`
4. `04_redis_03_deploy_sentinel.sh`
5. `04_redis_04_configure_haproxy_redis.sh`
6. `04_redis_05_configure_lb_healthcheck.sh`
7. `04_redis_06_tests.sh`
8. `04_redis_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/04_redis_ha/MODULE4_VALIDATION.md`

---

## 🐰 Module 5 - RabbitMQ HA

### Objectif
Cluster RabbitMQ hautement disponible avec Quorum Queues.

### Architecture
- **3 nœuds RabbitMQ** : queue-01, queue-02, queue-03
- **Quorum Queues** : Réplication synchrone
- **HAProxy** : Load balancing (partagé)
- **LB Hetzner** : 10.0.0.10 (partagé)

### Points d'Accès
- **RabbitMQ** : 10.0.0.10:5672 (LB Hetzner via HAProxy)

### Scripts
1. `05_rmq_00_setup_credentials.sh`
2. `05_rmq_01_prepare_nodes.sh`
3. `05_rmq_02_deploy_cluster.sh`
4. `05_rmq_03_configure_haproxy_rabbitmq.sh`
5. `05_rmq_04_configure_lb_healthcheck.sh`
6. `05_rmq_05_tests.sh`
7. `05_rmq_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/05_rabbitmq_ha/MODULE5_VALIDATION.md`

---

## 📦 Module 6 - MinIO S3 HA

### Objectif
Stockage objet S3-compatible pour backups et assets.

### Architecture
- **MinIO** : Mode single-node (mono-node)
- **Bucket** : keybuzz-backups (avec versioning)
- **Future** : 4-node distributed cluster

### Points d'Accès
- **MinIO** : 10.0.0.134:9000
- **Console** : 10.0.0.134:9001

### Scripts
1. `06_minio_00_setup_credentials.sh`
2. `06_minio_01_prepare_nodes.sh`
3. `06_minio_02_install_single.sh`
4. `06_minio_03_configure_client.sh`
5. `06_minio_04_tests.sh`
6. `06_minio_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/06_minio/MODULE6_VALIDATION.md`

---

## 🗄️ Module 7 - MariaDB Galera HA

### Objectif
Cluster MariaDB Galera multi-master pour ERPNext.

### Architecture
- **3 nœuds MariaDB Galera** : maria-01, maria-02, maria-03
- **ProxySQL** : 2 nœuds (proxysql-01, proxysql-02)
- **LB Hetzner** : 10.0.0.20:3306 (dédié MariaDB)

### Points d'Accès
- **MariaDB** : 10.0.0.20:3306 (LB Hetzner via ProxySQL)
- **Pour ERPNext** : 10.0.0.20:3306 (LB Hetzner)

### Scripts
1. `07_maria_00_setup_credentials.sh`
2. `07_maria_01_prepare_nodes.sh`
3. `07_maria_02_deploy_galera.sh`
4. `07_maria_03_install_proxysql.sh`
5. `07_maria_04_tests.sh`
6. `07_maria_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/07_mariadb_galera/MODULE7_VALIDATION.md`

### Notes Importantes

#### Port 4567 (Galera)
**NON**, le port 4567 ne doit **PAS** être ajouté au LB Hetzner pour ProxySQL. Ce port est utilisé uniquement pour la réplication interne entre les nœuds Galera (communication wsrep). Le LB Hetzner doit uniquement exposer le port **3306** de ProxySQL, qui est le port frontend pour les connexions clientes (ERPNext).

---

## 🔄 Module 8 - ProxySQL Avancé & Optimisation Galera

### Objectif
Configuration avancée de ProxySQL et optimisation du cluster Galera pour ERPNext.

### Architecture
- **ProxySQL** : Configuration avancée avec WSREP checks
- **Galera** : Optimisation des paramètres pour ERPNext
- **Monitoring** : Scripts de monitoring ProxySQL et Galera

### Scripts
1. `08_proxysql_01_generate_config.sh`
2. `08_proxysql_02_apply_config.sh`
3. `08_proxysql_03_optimize_galera.sh`
4. `08_proxysql_04_monitoring_setup.sh`
5. `08_proxysql_05_failover_tests.sh`
6. `08_proxysql_apply_all.sh`

### Documentation
- **Chemin** : `Infra/scripts/08_proxysql_advanced/MODULE8_VALIDATION.md`

---

## 🚀 Module 9 - K3s HA Core

### Objectif

Déployer un cluster K3s hautement disponible, capable de gérer des milliers de pods/tickets, supporter des pics de charge, et être la fondation multi-tenant de KeyBuzz.

### Architecture
- **3 masters K3s** : k3s-master-01, k3s-master-02, k3s-master-03
- **5 workers K3s** : k3s-worker-01 à k3s-worker-05
- **Ingress NGINX** : DaemonSet (CRITIQUE pour LB Hetzner)
- **Addons** : CoreDNS, metrics-server, StorageClass
- **Monitoring** : Prometheus Stack

### Composants

#### Control-plane HA
- **3 masters** avec etcd intégré
- **API Server** load balanced
- **Consensus RAFT** pour etcd

#### Addons Bootstrap
- **CoreDNS** : DNS interne K3s
- **metrics-server** : Métriques de base
- **local-path-provisioner** : StorageClass local

#### Ingress NGINX DaemonSet
- **CRITIQUE** : Mode DaemonSet (pas Deployment)
- **hostNetwork=true** : Pour LB Hetzner L4
- **Un Pod Ingress par node** : Garantit la disponibilité
- **NodePort** : 31695 (HTTP et HTTPS - même port)
- **SSL Termination** : Géré par les LB Hetzner
- **Health Check** : HTTP GET `/healthz` sur port 31695 (⚠️ HTTP pour HTTPS aussi)

#### Monitoring K3s
- **Prometheus Stack** : Prometheus + Grafana
- **kube-state-metrics** : Métriques K8s
- **node-exporter** : Métriques nodes

### Scripts
1. `09_k3s_01_prepare.sh` - Préparation des nœuds K3s
2. `09_k3s_02_install_control_plane.sh` - Installation control-plane HA
3. `09_k3s_03_join_workers.sh` - Join des workers
4. `09_k3s_04_bootstrap_addons.sh` - Bootstrap addons
5. `09_k3s_05_ingress_daemonset.sh` - Ingress NGINX DaemonSet
6. `09_k3s_06_deploy_core_apps.sh` - Préparation applications
7. `09_k3s_07_install_monitoring.sh` - Installation monitoring
8. `09_k3s_08_install_vault_agent.sh` - Préparation Vault
9. `09_k3s_09_final_validation.sh` - Validation finale
10. `09_k3s_test_healthcheck.sh` - Test healthcheck Ingress pour LB Hetzner
11. `09_k3s_apply_all.sh` - Script master

### Documentation
- **Chemin** : `Infra/scripts/09_k3s_ha/MODULE9_VALIDATION.md`
- **Structure proposée** : `Infra/scripts/09_k3s_ha/MODULE9_STRUCTURE_PROPOSAL.md`

### Notes Importantes

#### Ingress DaemonSet (OBLIGATOIRE)
- **NE PAS** utiliser Deployment pour Ingress
- **OBLIGATOIRE** : DaemonSet avec hostNetwork=true
- Permet l'exploitation du Load Balancing L4 Hetzner
- Un Pod Ingress par node garantit la disponibilité

#### Applications (Modules séparés)
Les applications KeyBuzz sont déployées dans des modules séparés :
- ✅ Module 10 : KeyBuzz API & Front
- Module 11 : Chatwoot
- Module 12 : n8n
- Module 13 : Superset
- Module 14 : Vault Agent
- Module 15 : LiteLLM & Services IA

---

## 🎯 Module 10 - KeyBuzz API & Front

### Objectif

Déployer l'application principale KeyBuzz (API Backend et Frontend UI) sur le cluster K3s HA.

### Architecture
- **KeyBuzz API** : Deployment + HPA (min: 3, max: 30)
- **KeyBuzz Front** : Deployment (3+ réplicas)
- **Namespace** : `keybuzz`
- **Ingress** : `platform.keybuzz.io` (Front), `platform-api.keybuzz.io` (API)

### Composants

#### KeyBuzz API
- **Type** : Deployment + HPA
- **Réplicas** : 3 (min), 30 (max)
- **Affinity** : Évite worker IA (#3) et monitoring
- **Variables d'environnement** :
  - `DATABASE_URL=postgres://kb_app:<pass>@10.0.0.10:5432/keybuzz`
  - `REDIS_URL=redis://10.0.0.10:6379`
  - `RABBITMQ_URL=amqp://kb_rmq:<pass>@10.0.0.10:5672//`
  - `MINIO_URL=http://10.0.0.134:9000`
  - `VECTOR_URL=http://10.0.0.136:6333`
  - `LLM_URL=http://llm-proxy.ai.svc.cluster.local:4000`

#### KeyBuzz Front
- **Type** : Deployment
- **Réplicas** : 3+
- **Build** : Static → container
- **Servi via** : NGINX container dans K3s

### Scripts
1. `10_keybuzz_00_setup_credentials.sh` - Génération des credentials KeyBuzz
2. `10_keybuzz_01_deploy_api.sh` - Déploiement KeyBuzz API
3. `10_keybuzz_02_deploy_front.sh` - Déploiement KeyBuzz Front
4. `10_keybuzz_03_configure_ingress.sh` - Configuration Ingress
5. `10_keybuzz_04_tests.sh` - Tests de validation
6. `10_keybuzz_apply_all.sh` - Script master

### Documentation
- **Chemin** : `Infra/scripts/10_keybuzz/README.md`
- **DNS Configuration** : `Infra/scripts/10_keybuzz/DNS_CONFIGURATION.md`
- **URLs Alternatives** : `Infra/scripts/10_keybuzz/URLS_ALTERNATIVES.md`

### Points d'Accès
- **Frontend** : `https://platform.keybuzz.io`
- **API** : `https://platform-api.keybuzz.io`

### Configuration Ingress

#### IngressClass
- **Nom** : `nginx`
- **Controller** : `k8s.io/ingress-nginx`
- **Statut** : ✅ Créée et configurée

#### Ingress Rules
- `platform.keybuzz.io` → `keybuzz-front:80`
- `platform-api.keybuzz.io` → `keybuzz-api:80`

#### Annotations
- `nginx.ingress.kubernetes.io/proxy-body-size: "50m"`

### Configuration Load Balancer Hetzner

#### LB 1 (lb-keybuzz-1)
- **IP Publique** : 49.13.42.76
- **IP Privée** : 10.0.0.5
- **Service HTTPS** : 443 → 31695
- **Certificats** : platform.keybuzz.io, platform-api.keybuzz.io
- **Healthcheck** : `/healthz` (HTTP, port 31695, status 200)
- **Targets** : 8 nodes K3s (3 masters + 5 workers)

#### LB 2 (lb-keybuzz-2)
- **IP Publique** : 138.199.132.240
- **IP Privée** : 10.0.0.6
- **Service HTTPS** : 443 → 31695
- **Certificats** : platform.keybuzz.io, platform-api.keybuzz.io
- **Healthcheck** : `/healthz` (HTTP, port 31695, status 200)
- **Targets** : 8 nodes K3s (3 masters + 5 workers)

### DNS Configuration
- **Enregistrements A** :
  - `platform.keybuzz.io` → 49.13.42.76, 138.199.132.240
  - `platform-api.keybuzz.io` → 49.13.42.76, 138.199.132.240
- **TTL** : 60 secondes
- **Statut** : ✅ Configuré

### Notes Importantes

#### Images Docker
- **Actuellement** : Images placeholder `nginx:alpine` pour tests
- **À remplacer** : Par les images KeyBuzz réelles une fois construites
- **Voir** : `10_keybuzz/IMAGES_DOCKER.md` pour instructions

#### Secrets
- Les credentials sont stockés dans des Secrets Kubernetes
- Migration vers Vault prévue dans Module 13

#### Problèmes Résolus
1. ✅ IngressClass "nginx" créée
2. ✅ Permissions RBAC corrigées (EndpointSlices, Leases)
3. ✅ Argument `--ingress-class=nginx` ajouté au DaemonSet
4. ✅ Pages HTML créées dans tous les pods
5. ✅ Service API corrigé (port 80)

### Validation
- **Statut** : ✅ **VALIDÉ ET OPÉRATIONNEL**
- **Date** : 20 novembre 2025
- **Documentation** : `10_keybuzz/MODULE10_VALIDATION.md`

---

## 🚀 Prochaines Étapes

### Modules à Implémenter
- **Module 11** : n8n (Workflow Automation) - Priorité 1
- **Module 12** : Superset (Business Intelligence) - Priorité 2
- **Module 13** : Vault Agent (Secret Management) - Priorité 3
- **Module 14** : Chatwoot (Customer Support) - Priorité 4
- **Module 15** : Marketplace Connectors & Services IA - Priorité 5

**Note** : Voir `09_k3s_ha/MODULE9_STRUCTURE_PROPOSAL.md` pour la structure détaillée de chaque module.

---

## ⚠️ Notes Importantes

### Ports et Load Balancers
- **Port 4567 (Galera)** : Port de réplication interne, **NE PAS** exposer dans LB Hetzner
- **LB Hetzner** : Expose uniquement les ports frontend (3306 pour MariaDB, 5432 pour PostgreSQL, etc.)
- **Ports internes** : 4444, 4567, 4568 (Galera) restent sur réseau privé uniquement

### Sécurité
- Tous les services sur réseau privé 10.0.0.0/16
- UFW configuré sur tous les nœuds
- Credentials stockés de manière sécurisée
- Pas d'exposition publique des services

### Haute Disponibilité
- Tous les modules en mode HA (3 nœuds minimum)
- Failover automatique configuré
- Load balancing via HAProxy ou ProxySQL
- LB Hetzner pour redondance

---

**Dernière mise à jour** : 20 novembre 2025  
**Auteur** : Infrastructure KeyBuzz  
**Version** : 1.4
