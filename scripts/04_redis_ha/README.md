# Module 4 - Redis HA avec Sentinel

**Version** : 1.0  
**Date** : 19 novembre 2025  
**Statut** : ✅ Scripts créés et prêts pour tests

## 📋 Résumé Exécutif

Ce module installe et configure un cluster Redis HA pour KeyBuzz :

- **Redis 7** avec Sentinel (3 nœuds)
- **HAProxy** sur haproxy-01/02 pour load balancing
- **LB Hetzner** 10.0.0.10 pour accès unifié
- **Health-checks** via `/opt/keybuzz/redis-lb/status/STATE`

## 🎯 Objectif et Périmètre

Ce module décrit l'installation complète et reproductible du cluster Redis pour KeyBuzz :

- Redis 7, en HA via Sentinel
- 3 nœuds : redis-01 (master), redis-02/03 (replicas)
- Tous les services Redis en Docker
- Accès depuis les applis via un LB Hetzner interne lb-haproxy :
  - IP privée : 10.0.0.10
  - Qui cible les serveurs haproxy-01 & haproxy-02
- HAProxy (Docker) sur haproxy-01/02 pour router vers le Redis master
- Sentinel pour l'élection automatique du master

Redis est utilisé pour :
- Caches
- Sessions
- Queues légères
- Verrous distribués

## 🧱 Topologie Logique

### Nœuds concernés (d'après servers.tsv)

**Cluster Redis** :
- redis-01 – 10.0.0.123 – ROLE=redis / SUBROLE=master
- redis-02 – 10.0.0.124 – ROLE=redis / SUBROLE=replica
- redis-03 – 10.0.0.125 – ROLE=redis / SUBROLE=replica

**Load balancers internes** :
- haproxy-01 – 10.0.0.11 – ROLE=lb / SUBROLE=internal-haproxy
- haproxy-02 – 10.0.0.12 – ROLE=lb / SUBROLE=internal-haproxy

**LB Hetzner** :
- lb-haproxy – Public IP: 49.13.46.190 – Private IP: 10.0.0.10

C'est ce LB Hetzner (10.0.0.10) qui est contacté par toutes les applis pour Redis.

## 🌐 Flux Réseau & Ports

### Ports sur redis-*

- **6379/tcp** : Redis server (auth obligatoire)
- **26379/tcp** : Redis Sentinel

### Ports sur haproxy-01/02

- **6379/tcp** : frontend Redis HA
- HAProxy détecte le nœud master et lui envoie le trafic

### Ports sur lb-haproxy (10.0.0.10)

- **10.0.0.10:6379** → HAProxy → Redis master

## 🔧 Prérequis

- Module 2 appliqué sur redis-01/02/03 et haproxy-01/02
- Docker installé et fonctionnel
- Swap désactivé
- UFW configuré (ports 6379, 26379)
- Credentials configurés (`/opt/keybuzz-installer/credentials/redis.env`)

## 📂 Scripts du Module 4

### Scripts principaux (dans l'ordre d'exécution)

1. ✅ **`04_redis_00_setup_credentials.sh`** : Configuration des credentials Redis
2. ✅ **`04_redis_01_prepare_nodes.sh`** : Préparation des nœuds Redis (répertoires, redis.conf)
3. ✅ **`04_redis_02_deploy_redis_cluster.sh`** : Déploiement du cluster Redis (master + replicas)
4. ✅ **`04_redis_03_deploy_sentinel.sh`** : Déploiement de Redis Sentinel
5. ✅ **`04_redis_04_configure_haproxy_redis.sh`** : Configuration HAProxy pour Redis (avec watcher Sentinel)
6. ✅ **`04_redis_05_configure_lb_healthcheck.sh`** : Configuration du LB healthcheck
7. ✅ **`04_redis_06_tests.sh`** : Tests et diagnostics
8. ✅ **`04_redis_apply_all.sh`** : Script master qui exécute tous les scripts dans le bon ordre

### Scripts utilitaires

- **`check_redis_status.sh`** : Vérification de l'état du cluster Redis
- **`test_redis_failover_safe.sh`** : Test de failover (sûr et réversible)

## 🚀 Installation

### Installation complète

```bash
cd /opt/keybuzz-installer/scripts/04_redis_ha
./04_redis_apply_all.sh ../../servers.tsv
```

### Installation étape par étape

```bash
# 1. Credentials
./04_redis_00_setup_credentials.sh

# 2. Préparation des nœuds
./04_redis_01_prepare_nodes.sh ../../servers.tsv

# 3. Déploiement Redis
./04_redis_02_deploy_redis_cluster.sh ../../servers.tsv

# 4. Déploiement Sentinel
./04_redis_03_deploy_sentinel.sh ../../servers.tsv

# 5. Configuration HAProxy
./04_redis_04_configure_haproxy_redis.sh ../../servers.tsv

# 6. Configuration LB healthcheck
./04_redis_05_configure_lb_healthcheck.sh

# 7. Tests
./04_redis_06_tests.sh ../../servers.tsv
```

## 📝 Points de Validation

### ✅ Prérequis
- [ ] Module 2 appliqué sur tous les serveurs Redis et HAProxy
- [ ] Docker installé et fonctionnel
- [ ] Swap désactivé
- [ ] UFW configuré

### ✅ Installation
- [ ] Credentials configurés
- [ ] Cluster Redis installé (3 nœuds)
- [ ] Sentinel installé (3 instances)
- [ ] HAProxy configuré (2 instances)
- [ ] Tests réussis

### ✅ Fonctionnement
- [ ] Cluster Redis opérationnel (1 master + 2 replicas)
- [ ] Sentinel surveille le cluster
- [ ] HAProxy route vers le master
- [ ] Connexions via LB 10.0.0.10 réussies
- [ ] Failover automatique fonctionnel

## ✅ Conformité

Tous les scripts sont conformes à :
- **Context.txt** : Utilisation de `kb-redis-master` (pas `mymaster`)
- **Anciens scripts fonctionnels** : Architecture et approche similaire
- **Bonnes pratiques KeyBuzz** : IP privée, network host, sécurité

Voir `CONFORMITY_CHECK.md` pour les détails de conformité.

## 📝 Notes Importantes

1. **Master Name** : Tous les scripts utilisent `kb-redis-master` (conforme à Context.txt)
2. **IP Privée** : Redis et Sentinel bindent sur l'IP privée (sécurité)
3. **Network Host** : Tous les conteneurs utilisent `--network host`
4. **Watcher Sentinel** : HAProxy inclut un watcher qui met à jour automatiquement lors d'un failover

---

**Dernière mise à jour** : 19 novembre 2025  
**Statut** : ✅ Tous les scripts créés et prêts pour tests

