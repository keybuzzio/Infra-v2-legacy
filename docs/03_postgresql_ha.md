# Module 3 : PostgreSQL HA (Patroni RAFT + HAProxy + PgBouncer + pgvector)

**Version** : 1.0  
**Date** : 18 novembre 2025  
**Statut** : ⏳ À implémenter

## 📋 Résumé Exécutif

Ce module installe et configure un cluster PostgreSQL 16 en haute disponibilité pour KeyBuzz :

- **PostgreSQL 16** avec Patroni RAFT (3 nœuds)
- **HAProxy** sur haproxy-01/02 pour load balancing
- **LB Hetzner** 10.0.0.10 pour accès unifié
- **PgBouncer** pour pooling de connexions (SCRAM)
- **pgvector** pour les embeddings

## 🎯 Objectif et Périmètre

Ce module décrit l'installation complète et reproductible du cluster PostgreSQL pour KeyBuzz :

- PostgreSQL 16, en HA via Patroni RAFT
- 3 nœuds : db-master-01, db-slave-01, db-slave-02
- Tous les services DB en Docker (Patroni + Postgres + PgBouncer)
- Accès depuis les applis via un LB Hetzner interne lb-haproxy :
  - IP privée : 10.0.0.10
  - Qui cible les serveurs haproxy-01 & haproxy-02
- HAProxy (Docker) sur haproxy-01/02 pour router vers le Patroni primary
- PgBouncer (Docker) pour le pooling de connexions
- pgvector installé de façon homogène sur tout le cluster

Ce module est la base de toutes les données relationnelles KeyBuzz (multi-tenant, tickets, logs structurés, etc.).

## 🧱 Topologie Logique

### Nœuds concernés (d'après servers.tsv)

**Cluster DB** :
- db-master-01 – 10.0.0.120 – ROLE=db / SUBROLE=postgres
- db-slave-01 – 10.0.0.121 – ROLE=db / SUBROLE=postgres
- db-slave-02 – 10.0.0.122 – ROLE=db / SUBROLE=postgres

**Load balancers internes** :
- haproxy-01 – 10.0.0.11 – ROLE=lb / SUBROLE=internal-haproxy
- haproxy-02 – 10.0.0.12 – ROLE=lb / SUBROLE=internal-haproxy

**LB Hetzner** :
- lb-haproxy – Public IP: 49.13.46.190 – Private IP: 10.0.0.10

C'est ce LB Hetzner (10.0.0.10) qui est contacté par toutes les applis pour la DB.

## 🌐 Flux Réseau & Ports

### Ports sur lb-haproxy (10.0.0.10)

À terme, on doit simplifier et stabiliser ces services (idéalement) :

- `10.0.0.10:5432` → HAProxy → PgBouncer → Patroni/PG16
- `10.0.0.10:6432` → HAProxy → PgBouncer direct (optionnel)
- `10.0.0.10:6379` → HAProxy → Redis cluster
- `10.0.0.10:5672` → HAProxy → RabbitMQ quorum

👉 **Bonne pratique** : Ne cibler dans ce LB que haproxy-01/02, jamais directement les nœuds DB/Redis/Rabbit.

### Ports sur haproxy-01/02

- `5432/tcp` : frontend DB (accès interne depuis 10.0.0.10)
- `6432/tcp` : frontend PgBouncer (si on veut faire du double LB)
- healthchecks HTTP vers Patroni : `http://db-XXX:8008/master` / `/replica`

### Ports internes DB

Sur db-master-01, db-slave-01, db-slave-02 :

- `5432/tcp` : PostgreSQL dans le conteneur Patroni
- `8008/tcp` : REST API Patroni (health & rôle)
- `7000/tcp` : RAFT (communication interne Patroni)

PgBouncer écoutera localement (par exemple sur `0.0.0.0:6432`).

## 🔧 Prérequis

### OS & Sécurité

Module 2 Base OS & Sécurité déjà appliqué sur :
- db-master-01, db-slave-01, db-slave-02
- haproxy-01, haproxy-02

**Points critiques** :
- ✅ Swap désactivé
- ✅ Docker CE installé et fonctionnel
- ✅ UFW ouvert sur :
  - 5432 / 6432 (DB nodes)
  - 5432 / 6432 / 5672 / 6379 (HAProxy nodes)
- ✅ DNS fixé (1.1.1.1 & 8.8.8.8) et resolv.conf protégé

### servers.tsv

Les lignes pour les DB et HAProxy doivent avoir :
- `ROLE=db SUBROLE=postgres` pour db-*
- `ROLE=lb SUBROLE=internal-haproxy` pour haproxy-*

Ces champs sont utilisés par les scripts du module 3.

### Credentials

Créer un fichier `/opt/keybuzz-installer/credentials/postgres.env` sur install-01 :

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

Le script d'install DB utilisera ces variables pour générer la conf de Patroni + PgBouncer.

## 🚀 Processus d'Installation FROM SCRATCH

Tous les scripts de ce module seront sous :
`/opt/keybuzz-installer/scripts/03_postgresql_ha/`

### Ordre global

1. `03_pg_01_reset_cluster.sh` (optionnel, si réinstallation)
2. `03_pg_02_install_patroni_cluster.sh`
3. `03_pg_03_install_haproxy_db_lb.sh`
4. `03_pg_04_install_pgbouncer.sh`
5. `03_pg_05_install_pgvector.sh`
6. `03_pg_06_diagnostics.sh`
7. `03_pg_07_failover_tests.sh` (optionnel, pour validation HA)
8. `03_pg_apply_all.sh` (wrapper principal)

### 1. Nettoyage d'un ancien cluster (optionnel)

**Script** : `03_pg_01_reset_cluster.sh`

**Fonctions** :
- Arrête tous les conteneurs liés à Patroni/PG sur db-*
- Supprime les conteneurs, réseaux spécifiques, volumes Docker nommés
- Nettoie les répertoires data : `/opt/keybuzz/postgres/data` (avec confirmation)
- Nettoie les anciens fichiers Patroni, systemd override, etc.

**Bonnes pratiques** :
- Afficher un GROS WARNING, demander confirmation (type YES)
- Faire un backup vers MinIO avant (bucket keybuzz-backups)

### 2. Volumes XFS & Chemins Data

Sur chaque nœud DB :

- Volume data monté en XFS sur ex : `/mnt/postgres-data`
- Créer un répertoire data pour le conteneur :
  ```bash
  mkdir -p /opt/keybuzz/postgres/data
  chown -R 999:999 /opt/keybuzz/postgres/data   # UID postgres dans le conteneur
  ```

Le script d'install doit :
- Vérifier que le FS est bien xfs (via `df -T`)
- Refuser de continuer si ce n'est pas le cas (ou au moins logger un WARNING très visible)

### 3. Patroni : Configuration Cluster & RAFT

**Script** : `03_pg_02_install_patroni_cluster.sh`

#### Principe

Sur chaque nœud DB, le script :
- Lit `servers.tsv` pour trouver la liste des nœuds db-* (IP privées, hostname)
- Copie un fichier `patroni.yml` templatisé, avec :
  - `name` = hostname (db-master-01, db-slave-01, etc.)
  - `raft` = liste des 3 nœuds (IP + port 7000)
  - `postgresql.data_dir` = `/var/lib/postgresql/data` (mount docker vers `/opt/keybuzz/postgres/data`)
  - `authentication.superuser` et `replication` = variables du .env
  - `postgresql.parameters` (tunning : max_connections, shared_buffers, etc.)
- Lance un conteneur Docker patroni sur chaque nœud avec :
  - Image : `zulfiqarh/patroni-pg16-raft` ou équivalent validé
  - Volumes :
    - `/opt/keybuzz/postgres/data:/var/lib/postgresql/data`
    - `/etc/patroni/patroni.yml:/etc/patroni/patroni.yml`
  - Ports : 5432, 8008, 7000

#### Organisation des fichiers

Sur chaque nœud DB :
- `/etc/patroni/patroni.yml`
- `/opt/keybuzz/postgres/data/`
- `/etc/systemd/system/patroni-docker.service` (unit systemd qui lance le conteneur)

Systemd doit :
- Redémarrer automatiquement en cas de crash
- Lancer Patroni au boot

### 4. Normalisation Systemd

**Script utilitaire** : `03_pg_02b_normalize_systemd.sh` (ou inclus dans 02)

**Objectif** :
- S'assurer que le service `patroni-docker.service` est :
  - Enabled
  - Active: running
- S'assurer que docker est bien enabled et démarre avant patroni-docker

### 5. HAProxy sur haproxy-01/02

**Script** : `03_pg_03_install_haproxy_db_lb.sh`

#### Rôle

haproxy-01 & haproxy-02 sont les backends du LB Hetzner lb-haproxy (10.0.0.10)

Ils reçoivent le trafic sur :
- 5432 (DB)
- 6432 (PgBouncer)
- 5672 (RabbitMQ)
- 6379 (Redis)

Ce module ne traite que la partie Postgres, mais la conf sera préparée de façon modulaire.

#### HAProxy en Docker

Conteneur haproxy :
- Config montée depuis `/etc/haproxy/haproxy.cfg`
- Ports exposés : 5432/6432/6379/5672 vers l'hôte

Backend DB typique :
```
frontend fe_pg_5432
    bind *:5432
    default_backend be_pg_primary

backend be_pg_primary
    option httpchk GET /master
    http-check expect status 200
    server db1 10.0.0.120:8008 check
    server db2 10.0.0.121:8008 check backup
    server db3 10.0.0.122:8008 check backup
```

La logique exacte (use backend / master / replica) peut être dérivée de tes scripts actuels, mais la base est : Patroni REST est la source de vérité.

#### Intégration avec LB Hetzner

Dans l'interface Hetzner :
- Service TCP 5432 :
  - Target group : haproxy-01 (10.0.0.11), haproxy-02 (10.0.0.12)
  - Health check : TCP simple, ou HTTP sur une future URL `/healthz` exposée côté haproxy (conseillé)
- Ne pas ajouter db-master/slave directement comme cibles dans ce LB → tout doit passer par HAProxy

### 6. PgBouncer (SCRAM)

**Script** : `03_pg_04_install_pgbouncer.sh`

#### Rôle

- Limiter le nombre de connexions actives sur le cluster
- Offrir une couche de sécurité et de mapping des utilisateurs
- Parler au cluster via HAProxy & Patroni

PgBouncer peut tourner :
- Soit sur les nœuds DB eux-mêmes
- Soit sur haproxy-01/02

Vu ton existant (port 6432 sur LB), un schéma propre :
- PgBouncer en conteneur sur haproxy-01/02, écoute 6432
- HAProxy peut router 5432 → 6432 si tu veux encore une abstraction
- Ou les applis se connectent directement à 10.0.0.10:6432

#### Configuration SCRAM

Le script doit :
- Générer un `userlist.txt` basé sur `POSTGRES_APP_USER`/`POSTGRES_SUPERUSER`
- Créer un `pgbouncer.ini` avec :
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
  ```
- Lancer un conteneur pgbouncer avec cette config
- Ajouter un service systemd `pgbouncer-docker.service`

### 7. Installation pgvector (extension)

**Script** : `03_pg_05_install_pgvector.sh`

**Objectif** :
- Installer l'extension pgvector sur le cluster HA
- S'assurer que chaque nœud en est équipé

**Procédure** :
- Installer le package pgvector dans les conteneurs ou via l'image (Docker image déjà compilée)
- Se connecter au primary via psql depuis install-01 :
  ```bash
  psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/${POSTGRES_DB}" \
    -c "CREATE EXTENSION IF NOT EXISTS vector;"
  ```
- Vérifier via `SELECT extname FROM pg_extension WHERE extname='vector';`

Cette extension sera utilisée pour les embeddings (même si tu as aussi Qdrant, pgvector permet de garder certaines choses dans la DB relationnelle).

### 8. Diagnostics & Tests Automatiques

**Script** : `03_pg_06_diagnostics.sh`

**Tests à automatiser** :
- Vérifier que les 3 nœuds Patroni sont running, 1 primary + 2 replicas
- Vérifier l'accès :
  ```bash
  psql "postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@10.0.0.10:5432/postgres" \
       -c "SELECT now();"
  ```
- Vérifier PgBouncer (port 6432) :
  ```bash
  psql "postgresql://${POSTGRES_APP_USER}:${POSTGRES_APP_PASS}@10.0.0.10:6432/${POSTGRES_DB}" \
       -c "SELECT 1;"
  ```
- Check RAFT :
  ```bash
  curl http://db-master-01:8008/health
  ```

### 9. Tests de Failover

**Script** : `03_pg_07_failover_tests.sh`

Simuler un failover forcé (via `docker exec patroni patronictl failover --force`)

Vérifier que :
- Le primary passe sur un autre nœud
- 10.0.0.10:5432 pointe toujours vers le nouveau primary
- Les connexions PgBouncer restent OK

## ⭐ Bonnes Pratiques & Erreurs à Éviter

### Bonnes pratiques

- Toujours documenter les credentials dans `postgres.env`, jamais dans les scripts
- Toujours appliquer Module 2 avant d'installer Postgres HA
- Toujours utiliser XFS pour les volumes DB
- Toujours vérifier la santé du cluster avec un script dédié après toute modification

### Erreurs à éviter

- ❌ Ajouter directement les nœuds DB comme cibles dans le LB Hetzner lb-haproxy
- ❌ Laisser SWAP activé
- ❌ Lancer plusieurs conteneurs Patroni sur le même nœud
- ❌ Modifier `patroni.yml` à la main sur un seul nœud sans répercuter

## 🔬 Tests Manuels de Validation

Depuis install-01 :

```bash
# Vérifier cluster Patroni
for host in 10.0.0.120 10.0.0.121 10.0.0.122; do
  echo "== $host =="
  ssh root@$host "docker ps | grep patroni || echo 'no patroni container'"
done

# Test simple DB via LB + PgBouncer
psql "postgresql://${POSTGRES_APP_USER}:${POSTGRES_APP_PASS}@10.0.0.10:6432/${POSTGRES_DB}" \
     -c "SELECT 'KeyBuzz DB OK' as status;"

# Test failover
ssh root@10.0.0.120 "docker exec patroni patronictl -c /etc/patroni/patroni.yml list"
```

## 📂 Plan des Scripts du Module 3

À créer sous `/opt/keybuzz-installer/scripts/03_postgresql_ha/` :

- `03_pg_01_reset_cluster.sh` (optionnel)
- `03_pg_02_install_patroni_cluster.sh`
- `03_pg_02b_normalize_systemd.sh` (optionnel si non inclus dans 02)
- `03_pg_03_install_haproxy_db_lb.sh`
- `03_pg_04_install_pgbouncer.sh`
- `03_pg_05_install_pgvector.sh`
- `03_pg_06_diagnostics.sh`
- `03_pg_07_failover_tests.sh`
- `03_pg_apply_all.sh` → lance les étapes dans le bon ordre (sauf reset/failover qui restent manuels)

## 📝 Checklist d'Installation

- [ ] Module 2 appliqué sur tous les serveurs DB et HAProxy
- [ ] Credentials créés dans `/opt/keybuzz-installer/credentials/postgres.env`
- [ ] Volumes XFS préparés sur chaque nœud DB
- [ ] Cluster Patroni installé (3 nœuds)
- [ ] HAProxy configuré sur haproxy-01/02
- [ ] LB Hetzner 10.0.0.10 configuré
- [ ] PgBouncer installé et configuré
- [ ] pgvector installé
- [ ] Tests de connectivité réussis
- [ ] Tests de failover réussis

---

**Dernière mise à jour** : 18 novembre 2025
