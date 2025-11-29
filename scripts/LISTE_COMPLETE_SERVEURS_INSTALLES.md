# Liste Complète des Serveurs Installés avec IPs Internes

**Date** : 2025-11-21  
**Source** : `Infra/servers.tsv`  
**Statut** : ✅ Tous les serveurs installés (Modules 2-9)

---

## 📊 Résumé

- **Total serveurs installés** : **26 serveurs**
- **Modules installés** : Modules 2 à 9
- **Tous les serveurs** : ✅ Installés et opérationnels

---

## 🖥️ Liste Détaillée par Module

### Module 2 : Base OS & Sécurité
**Tous les serveurs** (26 serveurs au total)

### Module 3 : PostgreSQL HA (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 1 | db-master-01 | **10.0.0.120** | 195.201.122.106 | PostgreSQL Primary |
| 2 | db-slave-01 | **10.0.0.121** | 91.98.169.31 | PostgreSQL Replica |
| 3 | db-slave-02 | **10.0.0.122** | 65.21.251.198 | PostgreSQL Replica |

**Endpoint** : `10.0.0.10:5432` (via HAProxy + LB Hetzner)

---

### Module 4 : Redis HA (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 4 | redis-01 | **10.0.0.123** | 49.12.231.193 | Redis Master |
| 5 | redis-02 | **10.0.0.124** | 23.88.48.163 | Redis Replica |
| 6 | redis-03 | **10.0.0.125** | 91.98.167.166 | Redis Replica |

**Endpoint** : `10.0.0.10:6379` (via HAProxy + LB Hetzner)

---

### Module 5 : RabbitMQ HA (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 7 | queue-01 | **10.0.0.126** | 23.88.105.16 | RabbitMQ Node 1 |
| 8 | queue-02 | **10.0.0.127** | 91.98.167.159 | RabbitMQ Node 2 |
| 9 | queue-03 | **10.0.0.128** | 91.98.68.35 | RabbitMQ Node 3 |

**Endpoint** : `10.0.0.10:5672` (via HAProxy + LB Hetzner)

---

### Module 6 : MinIO S3 (1 serveur)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 10 | minio-01 | **10.0.0.134** | 116.203.144.185 | MinIO S3 |

**Endpoints** :
- S3 API : `http://10.0.0.134:9000`
- Console Web : `http://10.0.0.134:9001`

---

### Module 7 : MariaDB Galera HA (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 11 | maria-01 | **10.0.0.170** | 91.98.35.206 | MariaDB Galera Node 1 |
| 12 | maria-02 | **10.0.0.171** | 46.224.43.75 | MariaDB Galera Node 2 |
| 13 | maria-03 | **10.0.0.172** | 49.13.66.233 | MariaDB Galera Node 3 |

**Endpoint** : `10.0.0.20:3306` (via ProxySQL + LB interne)

---

### Module 8 : ProxySQL Advanced (2 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 14 | proxysql-01 | **10.0.0.173** | 46.224.64.206 | ProxySQL 1 |
| 15 | proxysql-02 | **10.0.0.174** | 188.245.194.27 | ProxySQL 2 |

**Endpoint** : `10.0.0.20:3306` (LB interne pour MariaDB)

---

### Module 9 : K3s HA Core (8 serveurs)

#### Masters (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 16 | k3s-master-01 | **10.0.0.100** | 91.98.124.228 | K3s Master 1 |
| 17 | k3s-master-02 | **10.0.0.101** | 91.98.117.26 | K3s Master 2 |
| 18 | k3s-master-03 | **10.0.0.102** | 91.98.165.238 | K3s Master 3 |

#### Workers (5 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 19 | k3s-worker-01 | **10.0.0.110** | 116.203.135.192 | K3s Worker 1 |
| 20 | k3s-worker-02 | **10.0.0.111** | 91.99.164.62 | K3s Worker 2 |
| 21 | k3s-worker-03 | **10.0.0.112** | 157.90.119.183 | K3s Worker 3 |
| 22 | k3s-worker-04 | **10.0.0.113** | 91.98.200.38 | K3s Worker 4 |
| 23 | k3s-worker-05 | **10.0.0.114** | 188.245.45.242 | K3s Worker 5 |

**Endpoint API** : `https://10.0.0.100:6443` (ou via LB)

---

### Infrastructure (3 serveurs)

| # | Hostname | IP Privée | IP Publique | Rôle |
|---|----------|-----------|-------------|------|
| 24 | haproxy-01 | **10.0.0.11** | 159.69.159.32 | HAProxy 1 |
| 25 | haproxy-02 | **10.0.0.12** | 91.98.164.223 | HAProxy 2 |
| 26 | install-01 | **10.0.0.20** | 91.98.128.153 | Orchestration |

---

## 🔗 Endpoints Principaux

### Load Balancers

- **LB Interne Hetzner** : `10.0.0.10`
  - PostgreSQL : `10.0.0.10:5432` (write), `10.0.0.10:5433` (read)
  - Redis : `10.0.0.10:6379`
  - RabbitMQ : `10.0.0.10:5672`

- **LB Interne MariaDB** : `10.0.0.20`
  - MariaDB : `10.0.0.20:3306` (via ProxySQL)

- **LB Publics Hetzner** : `10.0.0.5`, `10.0.0.6`
  - Ingress K3s : Ports 80, 443

### Services Directs

- **MinIO S3** : `10.0.0.134:9000` (API), `10.0.0.134:9001` (Console)
- **K3s API** : `10.0.0.100:6443` (ou via LB)

---

## 📋 Répartition par Pool

- **k3s-masters** : 3 serveurs (10.0.0.100-102)
- **k3s-workers** : 5 serveurs (10.0.0.110-114)
- **db-pool** : 3 serveurs PostgreSQL (10.0.0.120-122) + 3 serveurs MariaDB (10.0.0.170-172)
- **redis-pool** : 3 serveurs (10.0.0.123-125)
- **queue-pool** : 3 serveurs (10.0.0.126-128)
- **haproxy-pool** : 2 serveurs HAProxy (10.0.0.11-12) + 2 serveurs ProxySQL (10.0.0.173-174)
- **storage** : 1 serveur MinIO (10.0.0.134)
- **management** : 1 serveur install-01 (10.0.0.20)

---

## ✅ Validation

Tous les serveurs listés ci-dessus ont été :
- ✅ Installés avec le Module 2 (Base OS & Sécurité)
- ✅ Configurés selon leur module respectif (3-9)
- ✅ Testés et validés
- ✅ Failover testé (pour les services HA)

---

**Document généré le** : 2025-11-21  
**Source** : `Infra/servers.tsv`  
**Statut** : ✅ Complet et vérifié

