# Notes Importantes pour l'Installation des Modules

**Date** : 2025-11-23  
**Source** : RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md (section Design Définitif)

## ⚠️ Informations Critiques à Appliquer

### 1. Module 3 : PostgreSQL HA (Patroni RAFT)

**⚠️ IMPORTANT** : Patroni doit être **rebuild** avec un Dockerfile custom, **PAS** utiliser directement `zalando/patroni:3.3.0`

**Dockerfile Patroni (basé sur les scripts existants)** :
```dockerfile
FROM postgres:16.4-alpine

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-pip \
        python3-dev \
        python3-psycopg2 \
        python3-setuptools \
        python3-wheel \
        gcc \
        postgresql-server-dev-16 \
        git \
        ca-certificates && \
    pip3 install --break-system-packages --no-cache-dir \
        patroni[raft]==3.3.0 \
        python-etcd && \
    apt-get remove -y gcc git && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# pgvector
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-16-pgvector && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/postgresql && \
    chown -R postgres:postgres /var/run/postgresql

USER postgres

CMD ["patroni", "/etc/patroni/patroni.yml"]
```

**Image finale** : `patroni-pg16-raft:latest` (ou `keybuzz/patroni-postgres16:latest`)

**Référence** : Scripts dans `keybuzz-installer/scripts/08_PostgreSQL_16_HA_Patroni/`

---

### 2. Module 6 : MinIO S3 - RÈGLES DÉFINITIVES

**⚠️ MODULE 6 DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**Cluster MinIO - RÈGLE STRICTE** :
- ✅ **3 nœuds fixes** : minio-01 (10.0.0.134), minio-02 (10.0.0.131), minio-03 (10.0.0.132)
- ❌ **INTERDICTION** : Ne JAMAIS ajouter ou retirer de nœuds sans instruction explicite

**Mode Distributed avec Erasure Coding** :
- ✅ Topologie obligatoire : 1 pool, 1 set, 3 drives per set
- ✅ Erasure coding activé automatiquement

**Version Docker Figée** :
- ✅ Version obligatoire : `minio/minio:RELEASE.2024-10-02T10-00Z`
- ❌ **INTERDICTION** : Ne JAMAIS utiliser `latest`

**Accès Interne Uniquement** :
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS exposer MinIO à Internet
- ✅ IP autorisées uniquement : 10.0.0.134:9000, 10.0.0.131:9000, 10.0.0.132:9000

**Point d'Entrée Officiel** :
- ✅ Point d'entrée unique : `http://10.0.0.134:9000`
- ⚠️ `s3.keybuzz.io` doit rester en interne uniquement

**Configuration Alias MinIO** :
- ✅ Configuration obligatoire : `mc alias set minio http://10.0.0.134:9000 <USER> <PASSWORD>`
- ❌ **INTERDICTION** : Ne JAMAIS utiliser d'autres points d'entrée pour l'alias

**Référence** : Section "B. MinIO : Cluster 3 Nœuds Distributed" du rapport technique

---

### 3. Module 4 : Redis HA (Sentinel) - RÈGLES DÉFINITIVES

**⚠️ MODULE 4 DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**Utilisation Redis - RÈGLE STRICTE** :
- ✅ **Toutes les applications doivent utiliser UNIQUEMENT** : `REDIS_URL=redis://10.0.0.10:6379`
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser directement redis-01, redis-02, redis-03
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser haproxy-01 ou haproxy-02 directement
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS modifier la configuration Redis/Sentinel/HAProxy

**Watcher Sentinel** :
- ✅ Watcher Sentinel actif sur haproxy-01 et haproxy-02
- ✅ Mise à jour automatique du backend redis-master dans HAProxy lors d'un failover
- ✅ Cron 5-10s ou daemon en continu

**Services Systemd** :
- ⚠️ Les services systemd Redis/Sentinel peuvent rester inactifs
- ✅ Les conteneurs Docker assurent la persistance et le redémarrage automatique

**Load Balancer Hetzner** :
- Configuration manuelle requise : Service TCP port 6379
- Targets : haproxy-01 (10.0.0.11), haproxy-02 (10.0.0.12)
- Health check : TCP

**Applications concernées** : KeyBuzz API, KeyBuzz UI, Chatwoot KeyBuzz, n8n, Workers KeyBuzz, Connecteurs Marketplace, Superset, Workplace, Backoffice Admin

---

### 4. Module 5 : RabbitMQ HA (Quorum) - RÈGLES DÉFINITIVES

**⚠️ MODULE 5 DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**Utilisation RabbitMQ - RÈGLE STRICTE** :
- ✅ **Toutes les applications doivent utiliser UNIQUEMENT** : `AMQP_URL=amqp://10.0.0.10:5672`
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser directement queue-01, queue-02, queue-03
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser haproxy-01 ou haproxy-02 directement
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS modifier la configuration RabbitMQ/HAProxy

**HAProxy RabbitMQ** :
- ✅ HAProxy fonctionnel et routant correctement vers le cluster quorum
- ✅ Configuration finale, ne plus modifier

**Services Systemd** :
- ⚠️ Ne PAS créer ou activer de services systemd pour RabbitMQ
- ✅ Tous les nœuds gérés par Docker avec `--restart unless-stopped`

**Version Docker Figée** :
- ✅ Version obligatoire : `rabbitmq:3.12.14-management`

**Load Balancer Hetzner** :
- Configuration manuelle requise : Service TCP port 5672
- Targets : haproxy-01 (10.0.0.11), haproxy-02 (10.0.0.12)
- Health check : TCP, interval 2s, timeout 2-3s, retries 3

**Applications concernées** : KeyBuzz API, Workers IA, n8n, Marketplace Connectors, Chatwoot KeyBuzz, Superset, Backoffice

---

### 5. Module 7 : MariaDB Galera HA - RÈGLES DÉFINITIVES

**⚠️ MODULE 7 DÉFINITIVEMENT TERMINÉ ET STABLE - NE PLUS MODIFIER**

**Adresse Officielle MariaDB - RÈGLE STRICTE** :
- ✅ **Toutes les applications doivent utiliser UNIQUEMENT** : `MARIADB_HOST=10.0.0.20` (Load Balancer Hetzner)
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser directement maria-01, maria-02, maria-03
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS utiliser proxysql-01 ou proxysql-02 directement
- ❌ **INTERDICTION ABSOLUE** : Ne JAMAIS modifier la configuration Galera/ProxySQL

**Load Balancer Hetzner 10.0.0.20** :
- Configuration manuelle requise : Service TCP port 3306
- Targets : proxysql-01 (10.0.0.173), proxysql-02 (10.0.0.174)
- Health check : TCP, interval 2s, timeout 2s, retries 3

**Deux ProxySQL Obligatoires** :
- ✅ proxysql-01 (10.0.0.173) : Déployé
- ✅ proxysql-02 (10.0.0.174) : Déployé
- ❌ **INTERDICTION** : Aucun SPOF ProxySQL autorisé

**Versions Docker Figées** :
- ✅ MariaDB Galera : `bitnami/mariadb-galera:10.11.6`
- ✅ ProxySQL : `proxysql/proxysql:2.6.4`
- ❌ **INTERDICTION** : Ne JAMAIS utiliser `latest`

**Configuration Galera Obligatoire** :
- ✅ `binlog_format=ROW`
- ✅ `innodb_autoinc_lock_mode=2`
- ✅ `wsrep_sst_method=rsync`
- ✅ `wsrep_on=ON`

**Applications concernées** : ERPNext, n8n, Workers

---

### 6. Versions Figées

**⚠️ RÈGLE STRICTE** : Plus jamais de tags `latest`, toujours des versions précises

**Fichier** : `/opt/keybuzz-installer/versions.yaml` (à créer)

**Versions à utiliser** :
- PostgreSQL : `postgres:16.4-alpine`
- Patroni : **Rebuild custom** (voir section 1)
- Redis : `redis:7.2.5-alpine`
- RabbitMQ : `rabbitmq:3.12.14-management` ⚠️ **VERSION FIGÉE**
- MinIO : `minio/minio:RELEASE.2024-10-02T10-00Z`
- HAProxy : `haproxy:2.8.5`
- MariaDB Galera : `bitnami/mariadb-galera:10.11.6`
- ProxySQL : `proxysql/proxysql:2.6.4`

**Référence** : Section "F. Images Docker : Versions Figées" du rapport technique

---

### 7. Architecture Load Balancers

**LB 10.0.0.10** :
- Load Balancer Hetzner privé (sans IP publique)
- Distribue vers haproxy-01 (10.0.0.11) et haproxy-02 (10.0.0.12)
- Services : `10.0.0.10:5432` (PostgreSQL), `10.0.0.10:6432` (PgBouncer), `10.0.0.10:6379` (Redis), `10.0.0.10:5672` (RabbitMQ)
- ⚠️ HAProxy écoute sur `0.0.0.0`, jamais sur `10.0.0.10` directement

**LB 10.0.0.20** :
- Load Balancer Hetzner privé (sans IP publique)
- Distribue vers proxysql-01 (10.0.0.173) et proxysql-02 (10.0.0.174)
- Service : `10.0.0.20:3306` (ProxySQL/MariaDB)
- ⚠️ ProxySQL écoute sur `0.0.0.0:3306`, jamais sur `10.0.0.20` directement

**Référence** : Section "A. Load Balancers Hetzner Internes" du rapport technique

---

### 8. Redis HA : Architecture Définitive (OBSOLÈTE - Voir Module 4)

**Configuration** :
- Tous les clients Redis parlent au master via `10.0.0.10:6379` → HAProxy → master Redis
- Script `/usr/local/bin/redis-update-master.sh` met à jour automatiquement HAProxy avec le master actuel
- Exécution : au boot, cron toutes les 15s/30s, ou via hook Sentinel
- ⚠️ Pas de round-robin, toujours le master

**Référence** : Section "C. Redis HA : Architecture Définitive" du rapport technique

---

### 9. K3s : Architecture Figée

**Masters** : 3 masters (k3s-master-01..03)  
**Workers** : 5 workers (k3s-worker-01..05)

**Ingress NGINX** : DaemonSet avec `hostNetwork: true`

**Applications** : Deployments K8s standards, ClusterIP, derrière ingress NGINX, HPA activé

**⚠️ RÈGLE** : Pas de DaemonSet + hostNetwork pour les apps, seulement pour Ingress

**Référence** : Section "E. K3s : Architecture Figée" du rapport technique

---

### 10. Gestion des Secrets & Credentials

**Emplacement central** : `/opt/keybuzz-installer/credentials/`

**Fichiers .env** :
- `postgres.env`, `redis.env`, `rabbitmq.env`, `minio.env`, `mariadb.env`, `proxysql.env`, `k3s.env`, `mail.env`, `marketplaces.env`, `stripe.env`

**Permissions** : `chmod 600`, propriété `root:root`

**⚠️ RÈGLES STRICTES** :
- Jamais de secrets dans `servers.tsv`, scripts `*.sh`, manifests `*.yaml`, repo Git
- Distribution via SSH avec `-e VAR=...` au `docker run`
- Préparation migration Vault avec noms de variables standardisés

**Référence** : Section "H. Gestion des Secrets & Credentials" du rapport technique

---

## Ordre d'Installation Validé

1. ✅ **Module 2** : Base OS & Sécurité (OBLIGATOIRE EN PREMIER)
2. ✅ **Module 3** : PostgreSQL HA (Patroni RAFT) - **⚠️ Rebuild image Patroni**
3. ✅ **Module 4** : Redis HA (Sentinel) - **⚠️ DÉFINITIVEMENT TERMINÉ - NE PLUS MODIFIER**
4. ✅ **Module 5** : RabbitMQ HA (Quorum) - **⚠️ DÉFINITIVEMENT TERMINÉ - NE PLUS MODIFIER**
5. ✅ **Module 6** : MinIO S3 - **⚠️ DÉFINITIVEMENT TERMINÉ - NE PLUS MODIFIER**
6. ✅ **Module 7** : MariaDB Galera HA - **⚠️ DÉFINITIVEMENT TERMINÉ - NE PLUS MODIFIER**
7. ⏳ **Module 8** : ProxySQL Advanced
8. ⏳ **Module 9** : K3s HA Core

---

## Scripts de Référence

**Patroni Rebuild** :
- `keybuzz-installer/scripts/08_PostgreSQL_16_HA_Patroni/04_postgres16_patroni_raft_FIXED.sh`
- `keybuzz-installer/scripts/08_PostgreSQL_16_HA_Patroni/08_postgres_to_patroni_raft.sh`

**MinIO Cluster** :
- `Context/Context.txt` (section MinIO distributed)
- `keybuzz-installer/scripts/07-MinIO/install_minio.sh`

---

## Notes Finales

- Toujours vérifier le document `RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md` en commençant par la fin (section "DESIGN DÉFINITIF INFRASTRUCTURE")
- Les dernières informations fonctionnelles sont dans la partie la plus basse du document
- Consulter les scripts existants dans `keybuzz-installer/scripts/` pour les implémentations validées

