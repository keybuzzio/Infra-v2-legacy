# Récapitulatif Technique - Module 3 : PostgreSQL HA

**Date de création** : 18 novembre 2025  
**Statut** : ⏳ Scripts créés, prêt pour installation

## Résumé Exécutif

Le Module 3 installe et configure un cluster PostgreSQL 16 en haute disponibilité pour KeyBuzz avec :

- **PostgreSQL 16** + Patroni RAFT (3 nœuds)
- **HAProxy** sur haproxy-01/02 pour load balancing
- **PgBouncer** pour pooling de connexions (SCRAM)
- **pgvector** pour les embeddings
- **LB Hetzner** 10.0.0.10 pour accès unifié

## Scripts Créés

### 1. `03_pg_00_setup_credentials.sh`
- Configuration des credentials PostgreSQL
- Génération automatique ou interactive des mots de passe
- Création du fichier `credentials/postgres.env`

### 2. `03_pg_02_install_patroni_cluster.sh`
- Installation du cluster Patroni RAFT sur 3 nœuds
- Configuration automatique de `patroni.yml` pour chaque nœud
- Création des services systemd
- Démarrage séquentiel du cluster

### 3. `03_pg_03_install_haproxy_db_lb.sh`
- Installation HAProxy sur haproxy-01/02
- Configuration pour router vers le Patroni primary
- Health checks via API Patroni (port 8008)
- Service systemd avec redémarrage automatique

### 4. `03_pg_04_install_pgbouncer.sh`
- Installation PgBouncer sur haproxy-01/02
- Configuration SCRAM-SHA-256
- Pooling de connexions (transaction mode)
- Service systemd avec redémarrage automatique

### 5. `03_pg_05_install_pgvector.sh`
- Installation de l'extension pgvector
- Vérification de l'installation
- Tests de fonctionnement

### 6. `03_pg_06_diagnostics.sh`
- Tests de connectivité
- Tests Patroni cluster
- Tests HAProxy
- Tests PgBouncer
- Tests PostgreSQL
- Rapport de diagnostic complet

### 7. `03_pg_apply_all.sh`
- Script wrapper principal
- Lance tous les scripts dans le bon ordre
- Gestion des erreurs
- Rapport de progression

## Architecture Déployée

### Nœuds DB
- **db-master-01** (10.0.0.120) - Patroni + PostgreSQL 16
- **db-slave-01** (10.0.0.121) - Patroni + PostgreSQL 16 (réplica)
- **db-slave-02** (10.0.0.122) - Patroni + PostgreSQL 16 (réplica)

### Load Balancers
- **haproxy-01** (10.0.0.11) - HAProxy + PgBouncer
- **haproxy-02** (10.0.0.12) - HAProxy + PgBouncer
- **lb-haproxy** (10.0.0.10) - LB Hetzner (cible haproxy-01/02)

### Flux de Connexion

```
Application
    ↓
10.0.0.10:5432 (LB Hetzner)
    ↓
haproxy-01/02:5432 (HAProxy)
    ↓
db-*:5432 (Patroni Primary)
    ↓
PostgreSQL 16
```

**Via PgBouncer** :
```
Application
    ↓
10.0.0.10:6432 (LB Hetzner)
    ↓
haproxy-01/02:6432 (PgBouncer)
    ↓
10.0.0.10:5432 (HAProxy)
    ↓
db-*:5432 (Patroni Primary)
```

## Points de Validation

### ✅ Prérequis
- [ ] Module 2 appliqué sur tous les serveurs DB et HAProxy
- [ ] Docker installé et fonctionnel
- [ ] Swap désactivé
- [ ] UFW configuré
- [ ] Volumes XFS préparés (recommandé)

### ✅ Installation
- [ ] Credentials configurés
- [ ] Cluster Patroni installé (3 nœuds)
- [ ] HAProxy installé (2 nœuds)
- [ ] PgBouncer installé (2 nœuds)
- [ ] pgvector installé
- [ ] Tests de diagnostic réussis

### ✅ Fonctionnement
- [ ] Cluster Patroni opérationnel (1 primary + 2 replicas)
- [ ] HAProxy route vers le primary
- [ ] PgBouncer fonctionne correctement
- [ ] Connexions via LB 10.0.0.10 réussies
- [ ] Extension pgvector disponible

## Utilisation

### Installation Complète

```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
./03_pg_apply_all.sh ../../servers.tsv
```

### Installation Étape par Étape

```bash
# 1. Credentials
./03_pg_00_setup_credentials.sh

# 2. Cluster Patroni
./03_pg_02_install_patroni_cluster.sh ../../servers.tsv

# 3. HAProxy
./03_pg_03_install_haproxy_db_lb.sh ../../servers.tsv

# 4. PgBouncer
./03_pg_04_install_pgbouncer.sh ../../servers.tsv

# 5. pgvector
./03_pg_05_install_pgvector.sh

# 6. Diagnostics
./03_pg_06_diagnostics.sh ../../servers.tsv
```

### Via Script Maître

```bash
cd /opt/keybuzz-installer/scripts
./00_master_install.sh --module 3
```

## Conformité avec KeyBuzz

Le Module 3 respecte **100%** des exigences KeyBuzz :

- ✅ PostgreSQL 16 avec Patroni RAFT
- ✅ 3 nœuds pour haute disponibilité
- ✅ HAProxy pour load balancing
- ✅ PgBouncer pour pooling
- ✅ pgvector pour embeddings
- ✅ Accès via LB Hetzner 10.0.0.10
- ✅ Configuration idempotente et reproductible
- ✅ Services systemd avec redémarrage automatique

## Prochaines Étapes

Une fois le Module 3 validé :

1. ✅ Module 4 : Redis HA
2. ✅ Module 5 : RabbitMQ HA
3. ✅ Module 6 : MinIO
4. ✅ Module 7 : MariaDB Galera
5. ✅ Module 8 : ProxySQL
6. ✅ Module 9 : K3s HA
7. ✅ Module 10 : Load Balancers

## Notes Importantes

- **Image Docker Patroni** : Le script utilise `zulfiqarh/patroni-pg16-raft:latest`
  - Vérifier que cette image inclut pgvector ou utiliser une image alternative
- **LB Hetzner** : La configuration du LB Hetzner (10.0.0.10) doit être faite manuellement dans l'interface Hetzner
- **Volumes XFS** : Recommandé mais pas obligatoire (le script vérifie et avertit)

---

**Dernière mise à jour** : 18 novembre 2025  
**Statut** : ✅ Scripts créés et prêts pour installation


