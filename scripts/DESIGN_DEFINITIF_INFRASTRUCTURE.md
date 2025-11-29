# Design Définitif Infrastructure KeyBuzz

**Date** : 2025-11-21  
**Statut** : ✅ Design définitif à appliquer strictement  
**Version** : 1.0

---

## ⚠️ RÈGLE FONDAMENTALE

**Tu n'as pas à "choisir" : tu dois appliquer exactement ce qui est écrit dans ce document.**

---

## A. Rôles des Load Balancers Hetzner internes

### LB 10.0.0.10

**Configuration** : Load Balancer Hetzner privé **sans IP publique**

**Rôle** : Distribuer le trafic interne vers :
- haproxy-01 (10.0.0.11)
- haproxy-02 (10.0.0.12)

**Services exposés sur 10.0.0.10** :
- `10.0.0.10:5432` → PostgreSQL (via HAProxy)
- `10.0.0.10:6432` → PgBouncer (via HAProxy, si utilisé)
- `10.0.0.10:6379` → Redis HA (via HAProxy)
- `10.0.0.10:5672` → RabbitMQ AMQP (via HAProxy)

**⚠️ RÈGLE CRITIQUE** : Tu ne dois **jamais** binder `10.0.0.10` directement dans HAProxy.

**Configuration HAProxy** :
- HAProxy écoute sur `0.0.0.0:5432`, `0.0.0.0:6432`, `0.0.0.0:6379`, `0.0.0.0:5672`
- Le LB Hetzner envoie les connexions vers `10.0.0.11` et `10.0.0.12`

### LB 10.0.0.20

**Configuration** : Load Balancer Hetzner privé **sans IP publique**

**Rôle** : Distribuer vers :
- proxysql-01 (10.0.0.173)
- proxysql-02 (10.0.0.174)

**Services exposés sur 10.0.0.20** :
- `10.0.0.20:3306` → ProxySQL (MariaDB Galera ERPNext)

**⚠️ RÈGLE CRITIQUE** : ProxySQL ne doit **jamais** écouter sur `10.0.0.20` :
- Il écoute sur `0.0.0.0:3306` localement
- Le LB Hetzner se charge de l'IP `10.0.0.20`

---

## B. MinIO : Cluster 3 nœuds DÉFINITIF

### 1. Nœuds MinIO

**Transformation** :
- **minio-01** : conservé (10.0.0.134)
- **connect-01** → **minio-02** (10.0.0.131)
- **connect-02** → **minio-03** (10.0.0.132)

**⚠️ IMPORTANT** : `k3s-worker-05` ne doit **pas** être utilisé pour MinIO. Il reste dans le pool `k3s-workers` pour les workloads applicatifs.

### 2. Installation MinIO Distributed

**Configuration sur chaque nœud MinIO** :
- Volume data : `/opt/keybuzz/minio/data`
- Même `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD`
- Même `MINIO_VOLUMES` :

```bash
MINIO_VOLUMES="http://minio-01.keybuzz.io/data http://minio-02.keybuzz.io/data http://minio-03.keybuzz.io/data"
```

**Commande Docker sur chaque nœud** :

```bash
docker run -d --name minio \
  -p 9000:9000 -p 9001:9001 \
  -v /opt/keybuzz/minio/data:/data \
  -e MINIO_ROOT_USER=$MINIO_ROOT_USER \
  -e MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD \
  --restart always \
  minio/minio:RELEASE.XYZ \
  server $MINIO_VOLUMES --console-address ":9001"
```

**DNS** : Tu dois configurer le DNS pour que :
- `minio-01.keybuzz.io` → 10.0.0.134
- `minio-02.keybuzz.io` → 10.0.0.131
- `minio-03.keybuzz.io` → 10.0.0.132

**Point d'entrée** : `http://s3.keybuzz.io:9000` qui pointe vers minio-01 (ou un LB MinIO dédié si ajouté plus tard).

---

## C. Redis HA : Architecture Définitive

### Cluster Redis Existant

- redis-01, redis-02, redis-03
- Redis + Sentinel déjà installés

### Objectif

**Tous les clients Redis de KeyBuzz doivent toujours parler au master via** :
- `10.0.0.10:6379` → HAProxy → master Redis

### Configuration HAProxy

Sur **haproxy-01** et **haproxy-02**, tu dois créer un backend unique `redis-master` :

```haproxy
backend be_redis_master
    mode tcp
    option tcp-check
    server redis-master 127.0.0.1:6380 check
```

### Script de Mise à Jour du Master

**Fichier** : `/usr/local/bin/redis-update-master.sh`

**Fonctionnalités** :
1. Interroge Sentinel (sur redis-01) :
   ```bash
   redis-cli -h redis-01 -p 26379 SENTINEL get-master-addr-by-name keybuzz-master
   ```
2. Récupère IP:PORT du master
3. Met à jour dans HAProxy la ligne :
   ```haproxy
   server redis-master <IP_MASTER>:6379 check
   ```
4. Recharge HAProxy (sans downtime) :
   ```bash
   systemctl reload haproxy
   ```

**Exécution** :
- Au boot
- À intervalles réguliers (cron toutes les 15s/30s)
- Ou via hook Sentinel (notif script) si tu veux être plus précis

### Résultat

- `10.0.0.10:6379` pointe toujours sur le master Redis
- Pas de round-robin, pas de writes sur replicas
- Failover automatique et propre
- C'est la meilleure solution pour éviter les bugs subtils en prod

---

## D. RabbitMQ Quorum : Architecture Figée

### Configuration

**3 nœuds** : queue-01, queue-02, queue-03

**Cluster quorum** : Configuré (OK)

**LB** : `10.0.0.10:5672` → HAProxy → les 3 nœuds

### Configuration HAProxy

Tu dois garder la configuration HAProxy suivante :

```haproxy
backend be_rabbitmq
    mode tcp
    option tcp-check
    balance roundrobin
    server queue-01 10.0.0.126:5672 check
    server queue-02 10.0.0.127:5672 check
    server queue-03 10.0.0.128:5672 check
```

**Justification** : Le cluster quorum RabbitMQ gère nativement le leader et la cohérence → ce schéma est correct et suffisamment optimisé pour KeyBuzz.

---

## E. K3s : 3 Masters + 5 Workers, Ingress en DaemonSet, Apps en Deployments

### Architecture

**Masters** : 3 masters (k3s-master-01..03)  
**Workers** : 5 workers (k3s-worker-01..05)

### Installation K3s

**Masters** : Mode HA (cluster-init + join)  
**Workers** : Join via LB public K3s (10.0.0.5/6 sur port 6443)

### Ingress NGINX

**Déploiement** : DaemonSet avec `hostNetwork: true`

**Écoute** : Ports 80/443 de chaque node

**LB Hetzner publics** : `10.0.0.5` / `10.0.0.6` pointent vers tous les nodes (masters + workers) sur 80/443

### Applications KeyBuzz

**Toutes les applications** (API, Front, Chatwoot, n8n, Workplace, Backoffice, LLM, Superset, connecteurs, etc.) doivent être :

- ✅ **Deployments K8s standards**
- ✅ **Exposés en ClusterIP**
- ✅ **Derrière l'ingress NGINX**
- ✅ **Avec HPA activé pour scaler**

**⚠️ RÈGLE CRITIQUE** : Tu ne dois **pas** utiliser DaemonSet + hostNetwork pour les apps.

---

## F. Images Docker : Versions Figées

### Règle Fondamentale

**Tu dois supprimer tous les tags `latest` dans les scripts d'installation et les remplacer par des versions précises.**

### Fichier de Référence

**Fichier** : `/opt/keybuzz-installer/versions.yaml`

**Rôle** : Centraliser les versions, que tous les scripts vont lire

### Versions Figées

```yaml
postgres_image: "postgres:16.4-alpine"
patroni_image: "zalando/patroni:3.3.0"
redis_image: "redis:7.2.5-alpine"
rabbitmq_image: "rabbitmq:3.13.2-management"
minio_image: "minio/minio:RELEASE.2024-10-02T10-00Z"
haproxy_image: "haproxy:2.8.5"
mariadb_galera_image: "bitnami/mariadb-galera:10.11.6"
proxysql_image: "proxysql/proxysql:2.6.4"
```

**Tous les scripts d'install doivent utiliser ces tags-là.**

---

## G. Réinstallation & Tests

### Processus

1. Mettre à jour `servers.tsv`
2. Rejouer les modules d'installation depuis zéro :
   - Base OS → DB → Redis → RabbitMQ → MinIO → MariaDB → K3s
3. Exécuter tous les scripts de test (failover, diag, perf) après chaque couche
4. Valider que tout passe **100% green** avant de déployer les apps K3s

---

## H. Gestion des Secrets & Credentials (Présent & Futur Vault)

### H.1. Emplacement CENTRAL des credentials (présent)

**Répertoire** : `/opt/keybuzz-installer/credentials/`

**Fichiers .env par grande brique** :
- `/opt/keybuzz-installer/credentials/postgres.env`
- `/opt/keybuzz-installer/credentials/redis.env`
- `/opt/keybuzz-installer/credentials/rabbitmq.env`
- `/opt/keybuzz-installer/credentials/minio.env`
- `/opt/keybuzz-installer/credentials/mariadb.env`
- `/opt/keybuzz-installer/credentials/proxysql.env`
- `/opt/keybuzz-installer/credentials/k3s.env`
- `/opt/keybuzz-installer/credentials/mail.env`
- `/opt/keybuzz-installer/credentials/marketplaces.env` (global, pas les tenants)
- `/opt/keybuzz-installer/credentials/stripe.env`

**⚠️ TU NE DOIS JAMAIS METTRE DE SECRETS DANS** :
- `servers.tsv`
- Les scripts `*.sh`
- Les manifests K8s `*.yaml`
- Le repo Git

**Permissions** :
```bash
chown root:root /opt/keybuzz-installer/credentials/*.env
chmod 600 /opt/keybuzz-installer/credentials/*.env
```

**Utilisation dans les scripts** :
```bash
# Dans un script d'installation Postgres
source /opt/keybuzz-installer/credentials/postgres.env
```

### H.2. Distribution des secrets vers les autres serveurs

**Principe** :
- `install-01` est la seule machine qui détient tous les `.env` complets
- Les autres serveurs ne reçoivent que les secrets strictement nécessaires à leur rôle

**Méthode** : Passer les valeurs directement comme `-e VAR=...` au `docker run`

**Exemple MinIO** :
```bash
source /opt/keybuzz-installer/credentials/minio.env
ssh root@minio-01 "
  docker run -d --name minio \
    -p 9000:9000 -p 9001:9001 \
    -v /opt/keybuzz/minio/data:/data \
    -e MINIO_ROOT_USER='$MINIO_ROOT_USER' \
    -e MINIO_ROOT_PASSWORD='$MINIO_ROOT_PASSWORD' \
    --restart always \
    minio/minio:RELEASE.XYZ \
    server $MINIO_VOLUMES --console-address ':9001'
"
```

### H.3. Préparation MIGRATION Vault (futur)

**Standardisation des noms de variables** :

```
POSTGRES_SUPERUSER, POSTGRES_SUPERPASS, POSTGRES_APP_USER, etc.
REDIS_PASSWORD
RABBITMQ_USER, RABBITMQ_PASSWORD
MINIO_ROOT_USER, MINIO_ROOT_PASSWORD
MARIADB_ROOT_PASSWORD, MARIADB_APP_USER, MARIADB_APP_PASSWORD
PROXYSQL_ADMIN_USER, PROXYSQL_ADMIN_PASSWORD
K3S_TOKEN
MAIL_SMTP_USER, MAIL_SMTP_PASSWORD
STRIPE_SECRET_KEY, etc.
```

**Hiérarchie Vault à venir** :

**Secrets globaux** :
- `secret/keybuzz/global/postgres`
- `secret/keybuzz/global/redis`
- `secret/keybuzz/global/rabbitmq`
- `secret/keybuzz/global/minio`
- `secret/keybuzz/global/mariadb`
- `secret/keybuzz/global/proxysql`
- `secret/keybuzz/global/mail`
- `secret/keybuzz/global/stripe`

**Tenants** :
- `secret/keybuzz/tenant_<TENANT_ID>/marketplaces`
- `secret/keybuzz/tenant_<TENANT_ID>/erpnext`
- `secret/keybuzz/tenant_<TENANT_ID>/api_keys`

**Structure dans les scripts** :
```bash
# === Credentials section ===
source /opt/keybuzz-installer/credentials/postgres.env
# === Fin section credentials ===
```

Plus tard, remplacer ce bloc par `vault kv get` sera trivial.

### H.4. Règles strictes à respecter

**Tu ne dois jamais écrire un mot de passe, token, clé API ou secret** :
- En clair dans un script `.sh`
- Dans un fichier `.yaml`
- Dans `servers.tsv`
- Dans un dépôt Git

**Tu ne dois jamais** :
- Laisser un `.env` lisible par un autre utilisateur que root
- Renvoyer des credentials dans les logs d'installation

**Tu dois** :
- Documenter dans les logs que les creds ont été chargés (ex. "Chargement credentials Postgres OK")
- **Jamais** leur valeur

---

**Document généré le** : 2025-11-21  
**Statut** : ✅ Design définitif à appliquer strictement

