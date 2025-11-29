# Module 3 — PostgreSQL HA (Patroni RAFT + HAProxy + PgBouncer + pgvector)

**Version** : 1.0  
**Date** : 25 novembre 2025  
**Statut** : ⏳ À implémenter

---

## 📘 SOMMAIRE

1. [Introduction](#1-introduction)
2. [Objectifs du module](#2-objectifs-du-module)
3. [Portée (serveurs concernés)](#3-portée-serveurs-concernés)
4. [Prérequis](#4-prérequis)
5. [Architecture](#5-architecture)
6. [Procédure d'installation](#6-procédure-dinstallation)
7. [Checklist de validation](#7-checklist-de-validation)
8. [Bonnes pratiques](#8-bonnes-pratiques)
9. [Erreurs courantes à éviter](#9-erreurs-courantes-à-éviter)
10. [Tests manuels](#10-tests-manuels)
11. [Dépannage](#11-dépannage)

---

## 1. Introduction

Ce module installe et configure un cluster PostgreSQL 16 en haute disponibilité pour KeyBuzz avec :

- **PostgreSQL 16** avec Patroni RAFT (3 nœuds)
- **HAProxy** sur haproxy-01/02 pour load balancing
- **LB Hetzner** 10.0.0.10 pour accès unifié
- **PgBouncer** pour pooling de connexions (SCRAM)
- **pgvector** pour les embeddings

Ce module est la base de toutes les données relationnelles KeyBuzz (multi-tenant, tickets, logs structurés, etc.).

**⚠️ Ce module DOIT être installé après le Module 2 (Base OS & Sécurité).**

---

## 2. Objectifs du module

- Installer un cluster PostgreSQL 16 en haute disponibilité avec Patroni RAFT
- Configurer HAProxy pour le load balancing vers le primary
- Installer PgBouncer pour le pooling de connexions
- Installer l'extension pgvector pour les embeddings
- Garantir la haute disponibilité avec failover automatique
- Permettre la réinstallation rapide et reproductible

---

## 3. Portée : Serveurs concernés

### Cluster DB (3 nœuds)

- **db-master-01** – 10.0.0.120 – ROLE=db / SUBROLE=postgres
- **db-slave-01** – 10.0.0.121 – ROLE=db / SUBROLE=postgres
- **db-slave-02** – 10.0.0.122 – ROLE=db / SUBROLE=postgres

### Load Balancers internes (2 nœuds)

- **haproxy-01** – 10.0.0.11 – ROLE=lb / SUBROLE=internal-haproxy
- **haproxy-02** – 10.0.0.12 – ROLE=lb / SUBROLE=internal-haproxy

### LB Hetzner

- **lb-haproxy** – Public IP: 49.13.46.190 – Private IP: 10.0.0.10

**⚠️ IMPORTANT** : C'est le LB Hetzner (10.0.0.10) qui est contacté par toutes les applications pour la DB.

---

## 4. Prérequis

### 4.1 Module 2 appliqué

Le Module 2 (Base OS & Sécurité) DOIT être appliqué sur :
- ✅ db-master-01, db-slave-01, db-slave-02
- ✅ haproxy-01, haproxy-02

**Points critiques** :
- ✅ Swap désactivé (obligatoire pour Patroni)
- ✅ Docker CE installé et fonctionnel
- ✅ UFW ouvert sur les ports nécessaires
- ✅ DNS fixé (1.1.1.1 & 8.8.8.8)

### 4.2 Volumes XFS

Sur chaque nœud DB, un volume XFS doit être monté (ex: `/mnt/postgres-data`).

**Vérification** :
```bash
df -T | grep xfs
```

**Création des répertoires** :
```bash
mkdir -p /opt/keybuzz/postgres/{data,raft,archive}
chown -R 999:999 /opt/keybuzz/postgres
chmod 700 /opt/keybuzz/postgres/data
chmod 700 /opt/keybuzz/postgres/raft
```

### 4.3 Credentials

Créer `/opt/keybuzz-installer-v2/credentials/postgres.env` sur install-01 :

```bash
POSTGRES_SUPERUSER=kb_admin
POSTGRES_SUPERPASS=<mot_de_passe_fort>
POSTGRES_REPL_USER=kb_repl
POSTGRES_REPL_PASS=<mot_de_passe_fort>
POSTGRES_APP_USER=kb_app
POSTGRES_APP_PASS=<mot_de_passe_fort>
POSTGRES_DB=keybuzz
PATRONI_CLUSTER_NAME=keybuzz-pg
```

### 4.4 servers.tsv

Le fichier `servers.tsv` doit contenir les lignes correctes pour :
- db-master-01, db-slave-01, db-slave-02 (ROLE=db, SUBROLE=postgres)
- haproxy-01, haproxy-02 (ROLE=lb, SUBROLE=internal-haproxy)

---

## 5. Architecture

### 5.1 Topologie Logique

```
Applications
    ↓
LB Hetzner (10.0.0.10:5432)
    ↓
HAProxy-01/02 (10.0.0.11/12:5432)
    ↓
PgBouncer (10.0.0.11/12:6432)
    ↓
Patroni Cluster (RAFT)
    ├── db-master-01 (10.0.0.120) [Primary]
    ├── db-slave-01 (10.0.0.121) [Replica]
    └── db-slave-02 (10.0.0.122) [Replica]
```

### 5.2 Flux Réseau & Ports

#### Ports sur LB Hetzner (10.0.0.10)

- `5432/tcp` → HAProxy → PgBouncer → Patroni/PG16
- `6432/tcp` → HAProxy → PgBouncer direct (optionnel)

#### Ports sur HAProxy (haproxy-01/02)

- `5432/tcp` : Frontend DB (accès interne depuis 10.0.0.10)
- `6432/tcp` : Frontend PgBouncer
- Health checks HTTP vers Patroni : `http://db-XXX:8008/master` / `/replica`

#### Ports internes DB (db-master-01, db-slave-01, db-slave-02)

- `5432/tcp` : PostgreSQL dans le conteneur Patroni
- `8008/tcp` : REST API Patroni (health & rôle)
- `7000/tcp` : RAFT (communication interne Patroni)

---

## 6. Procédure d'installation

### 6.1 Étape 1 : Configuration des Credentials

**Script** : `03_pg_00_setup_credentials.sh`

**Objectif** : Créer le fichier `postgres.env` avec les credentials PostgreSQL.

**Commande** :
```bash
cd /opt/keybuzz-installer-v2/scripts/03_postgresql_ha
./03_pg_00_setup_credentials.sh
```

**Résultat attendu** :
- Fichier `/opt/keybuzz-installer-v2/credentials/postgres.env` créé
- Variables d'environnement définies

---

### 6.2 Étape 2 : Préparation des Volumes

**Script** : `03_pg_01_prepare_volumes.sh`

**Objectif** : Préparer les volumes XFS et les répertoires de données sur chaque nœud DB.

**Actions** :
- Vérifier que le FS est XFS
- Créer les répertoires `/opt/keybuzz/postgres/{data,raft,archive}`
- Configurer les permissions (UID 999:999 = postgres)

**Commande** :
```bash
./03_pg_01_prepare_volumes.sh ../../inventory/servers.tsv
```

---

### 6.3 Étape 3 : Installation du Cluster Patroni RAFT

**Script** : `03_pg_02_install_patroni_cluster.sh`

**Objectif** : Installer le cluster Patroni RAFT sur les 3 nœuds DB.

#### 6.3.1 Image Docker Patroni

**Image utilisée** : `zulfiqarh/patroni-pg16-raft:latest` ou équivalent validé

**Alternative** : Construire l'image depuis un Dockerfile :

```dockerfile
FROM postgres:16

USER root
RUN apt-get update && apt-get install -y \
    python3-pip python3-psycopg2 python3-dev gcc curl \
    postgresql-16-pgvector \
    && apt-get clean

RUN pip3 install --break-system-packages \
    'patroni[raft]==3.3.2' \
    psycopg2-binary

RUN mkdir -p /opt/keybuzz/postgres/raft \
    && chown -R postgres:postgres /opt/keybuzz/postgres

COPY --chown=postgres:postgres config/patroni.yml /etc/patroni/patroni.yml

USER postgres
EXPOSE 5432 8008 7000
CMD ["patroni", "/etc/patroni/patroni.yml"]
```

#### 6.3.2 Configuration Patroni

**Fichier** : `/etc/patroni/patroni.yml` (sur chaque nœud)

**Exemple pour db-master-01** :

```yaml
scope: keybuzz-pg
name: db-master-01

restapi:
  listen: 0.0.0.0:8008
  connect_address: 10.0.0.120:8008

raft:
  data_dir: /opt/keybuzz/postgres/raft
  self_addr: 10.0.0.120:7000
  partner_addrs:
    - 10.0.0.121:7000
    - 10.0.0.122:7000

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 100
        shared_buffers: 256MB
        wal_level: replica
        hot_standby: 'on'
        max_wal_senders: 10
        max_replication_slots: 10

  initdb:
    - encoding: UTF8
    - data-checksums

  pg_hba:
    - local all all trust
    - host all all 0.0.0.0/0 md5
    - host replication replicator 0.0.0.0/0 md5

  users:
    postgres:
      password: '${POSTGRES_SUPERPASS}'
      options:
        - createrole
        - createdb
    replicator:
      password: '${POSTGRES_REPL_PASS}'
      options:
        - replication

postgresql:
  listen: '*:5432'
  connect_address: 10.0.0.120:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/16/bin
  authentication:
    superuser:
      username: postgres
      password: '${POSTGRES_SUPERPASS}'
    replication:
      username: replicator
      password: '${POSTGRES_REPL_PASS}'
  create_replica_methods:
    - basebackup
  basebackup:
    max-rate: 100M
    checkpoint: fast

watchdog:
  mode: off
```

#### 6.3.3 Démarrage des Conteneurs

**Commande sur chaque nœud DB** :

```bash
docker run -d \
  --name patroni \
  --hostname db-master-01 \
  --network host \
  --restart unless-stopped \
  -v /opt/keybuzz/postgres/data:/var/lib/postgresql/data \
  -v /opt/keybuzz/postgres/raft:/opt/keybuzz/postgres/raft \
  -v /opt/keybuzz/postgres/archive:/opt/keybuzz/postgres/archive \
  -v /etc/patroni/patroni.yml:/etc/patroni/patroni.yml:ro \
  -e POSTGRES_SUPERPASS='${POSTGRES_SUPERPASS}' \
  -e POSTGRES_REPL_PASS='${POSTGRES_REPL_PASS}' \
  zulfiqarh/patroni-pg16-raft:latest
```

**Ordre de démarrage** :
1. db-master-01 (premier, devient primary)
2. db-slave-01 (rejoint le cluster)
3. db-slave-02 (rejoint le cluster)

**Attendre 30 secondes entre chaque démarrage.**

#### 6.3.4 Service Systemd (Optionnel mais Recommandé)

**Fichier** : `/etc/systemd/system/patroni-docker.service`

```ini
[Unit]
Description=Patroni PostgreSQL HA
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start patroni
ExecStop=/usr/bin/docker stop patroni
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Activation** :
```bash
systemctl daemon-reload
systemctl enable patroni-docker.service
systemctl start patroni-docker.service
```

---

### 6.4 Étape 4 : Installation HAProxy

**Script** : `03_pg_03_install_haproxy_db_lb.sh`

**Objectif** : Installer et configurer HAProxy sur haproxy-01/02 pour router vers le Patroni primary.

#### 6.4.1 Configuration HAProxy

**Fichier** : `/etc/haproxy/haproxy.cfg`

```conf
global
    log /dev/log local0
    chroot /var/lib/haproxy
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5000ms
    timeout client 50000ms
    timeout server 50000ms

# Frontend PostgreSQL
frontend fe_pg_5432
    bind *:5432
    default_backend be_pg_primary

# Backend PostgreSQL Primary
backend be_pg_primary
    option httpchk GET /master
    http-check expect status 200
    server db1 10.0.0.120:5432 check port 8008 inter 2s fall 3 rise 2
    server db2 10.0.0.121:5432 check port 8008 inter 2s fall 3 rise 2 backup
    server db3 10.0.0.122:5432 check port 8008 inter 2s fall 3 rise 2 backup

# Frontend PgBouncer
frontend fe_pgbouncer_6432
    bind *:6432
    default_backend be_pgbouncer

# Backend PgBouncer
backend be_pgbouncer
    balance roundrobin
    server pgbouncer1 10.0.0.11:6432 check
    server pgbouncer2 10.0.0.12:6432 check

# Stats (optionnel)
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
```

#### 6.4.2 Conteneur HAProxy

**Commande** :

```bash
docker run -d \
  --name haproxy \
  --network host \
  --restart unless-stopped \
  -v /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \
  haproxy:2.9-alpine
```

---

### 6.5 Étape 5 : Installation PgBouncer

**Script** : `03_pg_04_install_pgbouncer.sh`

**Objectif** : Installer PgBouncer sur haproxy-01/02 pour le pooling de connexions.

#### 6.5.1 Configuration PgBouncer

**Fichier** : `/etc/pgbouncer/pgbouncer.ini`

```ini
[databases]
keybuzz = host=10.0.0.10 port=5432 dbname=keybuzz

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 500
default_pool_size = 50
min_pool_size = 10
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 100
max_user_connections = 50
```

**Fichier** : `/etc/pgbouncer/userlist.txt`

```txt
"kb_admin" "SCRAM-SHA-256$4096:<hash>$<salt>"
"kb_app" "SCRAM-SHA-256$4096:<hash>$<salt>"
```

**Génération des hashes** :
```bash
psql -c "SELECT 'SCRAM-SHA-256$' || encode(digest('password' || username, 'sha256'), 'base64') FROM pg_user WHERE usename='kb_admin';"
```

#### 6.5.2 Conteneur PgBouncer

**Commande** :

```bash
docker run -d \
  --name pgbouncer \
  --network host \
  --restart unless-stopped \
  -v /etc/pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro \
  -v /etc/pgbouncer/userlist.txt:/etc/pgbouncer/userlist.txt:ro \
  pgbouncer/pgbouncer:latest
```

---

### 6.6 Étape 6 : Installation pgvector

**Script** : `03_pg_05_install_pgvector.sh`

**Objectif** : Installer l'extension pgvector sur le cluster HA.

**Commande** :

```bash
# Se connecter au primary via psql
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
  -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Vérifier
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
  -c "SELECT extname FROM pg_extension WHERE extname='vector';"
```

**Résultat attendu** :
```
 extname
--------
 vector
(1 row)
```

---

### 6.7 Étape 7 : Script Maître

**Script** : `03_pg_apply_all.sh`

**Objectif** : Lancer toutes les étapes dans le bon ordre.

**Commande** :
```bash
cd /opt/keybuzz-installer-v2/scripts/03_postgresql_ha
./03_pg_apply_all.sh ../../inventory/servers.tsv
```

---

## 7. Checklist de validation

### 7.1 Cluster Patroni

- [ ] 3/3 conteneurs Docker Patroni actifs
- [ ] Cluster opérationnel avec quorum RAFT
- [ ] 1 primary + 2 replicas
- [ ] Réplicas en streaming avec 0 lag
- [ ] Timeline synchronisée

**Commandes de vérification** :
```bash
# Vérifier les conteneurs
for host in 10.0.0.120 10.0.0.121 10.0.0.122; do
  ssh root@$host "docker ps | grep patroni"
done

# Vérifier le cluster
curl http://10.0.0.120:8008/cluster
curl http://10.0.0.121:8008/cluster
curl http://10.0.0.122:8008/cluster
```

### 7.2 HAProxy

- [ ] 2/2 services HAProxy actifs
- [ ] Configuration validée
- [ ] Health checks opérationnels
- [ ] Routage vers le Leader Patroni fonctionnel

**Commandes de vérification** :
```bash
# Vérifier les conteneurs
for host in 10.0.0.11 10.0.0.12; do
  ssh root@$host "docker ps | grep haproxy"
done

# Vérifier les stats
curl http://10.0.0.11:8404/stats
```

### 7.3 PgBouncer

- [ ] 2/2 services PgBouncer actifs
- [ ] Connection pooling configuré
- [ ] Connexions fonctionnelles

**Commandes de vérification** :
```bash
# Vérifier les conteneurs
for host in 10.0.0.11 10.0.0.12; do
  ssh root@$host "docker ps | grep pgbouncer"
done

# Test de connexion
psql "postgresql://${POSTGRES_APP_USER}:${POSTGRES_APP_PASS}@10.0.0.10:6432/${POSTGRES_DB}" \
  -c "SELECT 1;"
```

### 7.4 pgvector

- [ ] Extension installée sur le cluster
- [ ] Extension accessible depuis toutes les connexions

**Commande de vérification** :
```bash
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
  -c "SELECT extname, extversion FROM pg_extension WHERE extname='vector';"
```

---

## 8. Bonnes pratiques

- ✅ Toujours documenter les credentials dans `postgres.env`, jamais dans les scripts
- ✅ Toujours appliquer Module 2 avant d'installer Postgres HA
- ✅ Toujours utiliser XFS pour les volumes DB
- ✅ Toujours vérifier la santé du cluster avec un script dédié après toute modification
- ✅ Toujours utiliser le LB Hetzner (10.0.0.10) pour les connexions, jamais directement les nœuds DB
- ✅ Toujours tester le failover après installation

---

## 9. Erreurs courantes à éviter

- ❌ Ajouter directement les nœuds DB comme cibles dans le LB Hetzner lb-haproxy
- ❌ Laisser SWAP activé (Patroni refuse le swap)
- ❌ Lancer plusieurs conteneurs Patroni sur le même nœud
- ❌ Modifier `patroni.yml` à la main sur un seul nœud sans répercuter
- ❌ Utiliser des versions `latest` non figées
- ❌ Oublier de configurer les health checks HAProxy

---

## 10. Tests manuels

### 10.1 Test de Connectivité

```bash
# Via HAProxy direct
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.11:5432/${POSTGRES_DB}" \
  -c "SELECT 'KeyBuzz DB OK' as status;"

# Via LB Hetzner
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
  -c "SELECT 'KeyBuzz DB OK' as status;"

# Via PgBouncer
psql "postgresql://${POSTGRES_APP_USER}:${POSTGRES_APP_PASS}@10.0.0.10:6432/${POSTGRES_DB}" \
  -c "SELECT 1;"
```

### 10.2 Test de Failover

```bash
# Vérifier le primary actuel
curl http://10.0.0.120:8008/cluster | jq '.members[] | select(.role=="Leader")'

# Forcer un failover (sur install-01)
ssh root@10.0.0.120 "docker exec patroni patronictl -c /etc/patroni/patroni.yml failover --force"

# Vérifier le nouveau primary
curl http://10.0.0.121:8008/cluster | jq '.members[] | select(.role=="Leader")'

# Vérifier que les connexions fonctionnent toujours
psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
  -c "SELECT now();"
```

---

## 11. Dépannage

### 11.1 Patroni ne démarre pas

**Symptômes** :
- Conteneur Docker ne démarre pas
- Erreur dans les logs : `Failed to start Patroni`

**Diagnostic** :
```bash
docker logs patroni
```

**Solutions** :
- Vérifier que le swap est désactivé : `swapon --summary`
- Vérifier les permissions : `ls -la /opt/keybuzz/postgres/`
- Vérifier la configuration : `cat /etc/patroni/patroni.yml`

### 11.2 Cluster sans quorum

**Symptômes** :
- Cluster en état "no quorum"
- Pas de primary élu

**Diagnostic** :
```bash
curl http://10.0.0.120:8008/cluster
```

**Solutions** :
- Vérifier la connectivité réseau entre les nœuds (port 7000)
- Vérifier que les 3 nœuds sont démarrés
- Redémarrer le cluster dans l'ordre : db-master-01, db-slave-01, db-slave-02

### 11.3 HAProxy ne route pas vers le primary

**Symptômes** :
- Connexions échouent via HAProxy
- Health checks échouent

**Diagnostic** :
```bash
curl http://10.0.0.11:8404/stats
```

**Solutions** :
- Vérifier les health checks : `curl http://10.0.0.120:8008/master`
- Vérifier la configuration HAProxy : `cat /etc/haproxy/haproxy.cfg`
- Redémarrer HAProxy : `docker restart haproxy`

---

**Dernière mise à jour** : 25 novembre 2025

