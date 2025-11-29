# Test Complet Couche 1 - KeyBuzz

**Date** : 2025-11-25  
**Objectif** : Tester exhaustivement tous les composants de la couche 1 (Modules 2-8)

---

## 📋 Vue d'Ensemble

Ce script teste tous les composants de la couche 1 (stateful/data) selon les bonnes pratiques KeyBuzz définies dans les rapports de validation.

### Modules Testés

- ✅ **Module 3** : PostgreSQL HA (Patroni + HAProxy + PgBouncer)
- ✅ **Module 4** : Redis HA (Sentinel + HAProxy)
- ✅ **Module 5** : RabbitMQ HA (Quorum + HAProxy)
- ✅ **Module 6** : MinIO S3 (Cluster 3 Nœuds)
- ✅ **Module 7** : MariaDB Galera HA
- ✅ **Module 8** : ProxySQL Advanced
- ✅ **Load Balancers** : 10.0.0.10 (DB/Redis/Rabbit), 10.0.0.20 (MariaDB)

---

## 🚀 Utilisation

### Test Standard (Sans Failover)

```bash
cd /opt/keybuzz-installer/scripts
./test_couche1_complete.sh
```

### Test Complet (Avec Failover)

```bash
cd /opt/keybuzz-installer/scripts
./test_couche1_complete.sh --failover
```

**⚠️ Attention** : Les tests de failover arrêtent temporairement des services. Tous les services sont redémarrés automatiquement.

---

## 📊 Tests Effectués

### Module 3 : PostgreSQL HA

1. **Conteneurs Patroni** : Vérification 3/3 actifs
2. **Leader Patroni** : Détection du leader actuel
3. **Réplicas Patroni** : Vérification 2/2 en streaming
4. **HAProxy PostgreSQL** : Vérification 2/2 opérationnels
5. **PgBouncer** : Vérification 2/2 opérationnels
6. **Connectivité via LB 10.0.0.10:5432** : Test connexion PostgreSQL
7. **Connectivité via PgBouncer LB 10.0.0.10:6432** : Test connexion PgBouncer

### Module 4 : Redis HA

1. **Conteneurs Redis** : Vérification 3/3 actifs
2. **Master Redis** : Détection du master actuel
3. **Réplicas Redis** : Vérification 2/2 connectés
4. **Redis Sentinel** : Vérification 3/3 opérationnels
5. **HAProxy Redis** : Vérification 2/2 opérationnels
6. **Connectivité via LB 10.0.0.10:6379** : Test PING Redis
7. **Test write/read** : Test SET/GET Redis

### Module 5 : RabbitMQ HA

1. **Conteneurs RabbitMQ** : Vérification 3/3 actifs
2. **Cluster RabbitMQ** : Vérification taille cluster (3/3)
3. **HAProxy RabbitMQ** : Vérification 2/2 opérationnels
4. **Connectivité via LB 10.0.0.10:5672** : Test port AMQP

### Module 6 : MinIO S3

1. **Conteneurs MinIO** : Vérification 3/3 actifs
2. **Connectivité S3 API** : Test ports 9000 (3/3)
3. **Client mc** : Vérification installation et configuration

### Module 7 : MariaDB Galera

1. **Conteneurs MariaDB Galera** : Vérification 3/3 actifs
2. **Cluster Galera** : Vérification taille cluster (3/3)
3. **ProxySQL** : Vérification 2/2 actifs
4. **Connectivité via LB 10.0.0.20:3306** : Test connexion MariaDB

### Module 8 : ProxySQL Advanced

1. **Configuration ProxySQL** : Vérification serveurs Galera configurés (3/3)

### Tests de Failover (Optionnels)

1. **Failover PostgreSQL/Patroni** : Arrêt leader → vérification nouveau leader
2. **Failover Redis Sentinel** : Arrêt master → vérification nouveau master
3. **Résilience RabbitMQ** : Arrêt nœud → vérification accessibilité
4. **Résilience MariaDB Galera** : Arrêt nœud → vérification accessibilité

---

## 📄 Fichiers Générés

### Log Complet

**Fichier** : `/opt/keybuzz-installer/logs/test_couche1_YYYYMMDD_HHMMSS.log`

Contient tous les détails des tests exécutés.

### Rapport Markdown

**Fichier** : `/opt/keybuzz-installer/logs/RAPPORT_TEST_COUCHE1_YYYYMMDD_HHMMSS.md`

Rapport formaté suivant le format des rapports de validation KeyBuzz.

---

## ✅ Critères de Validation

### Validation 100%

- ✅ Tous les conteneurs actifs (3/3 ou 2/2 selon le module)
- ✅ Tous les clusters opérationnels (taille correcte)
- ✅ Toutes les connectivités via LB fonctionnelles
- ✅ Aucun test échoué

### Validation Partielle

- ⚠️ Certains conteneurs manquants mais cluster fonctionnel
- ⚠️ Certaines connectivités échouent mais services principaux OK

---

## 🔧 Prérequis

### Sur install-01

- ✅ Script `test_couche1_complete.sh` exécutable
- ✅ Credentials disponibles dans `/opt/keybuzz-installer/credentials/`
- ✅ Accès SSH à tous les serveurs (clé SSH configurée)
- ✅ Clients installés :
  - `psql` (client PostgreSQL)
  - `redis-cli` (client Redis)
  - `mysql` (client MySQL/MariaDB)
  - `mc` (client MinIO, optionnel)

### Credentials Requis

- `postgres.env` : Credentials PostgreSQL
- `redis.env` : Credentials Redis
- `rabbitmq.env` : Credentials RabbitMQ
- `minio.env` : Credentials MinIO
- `mariadb.env` : Credentials MariaDB
- `proxysql.env` : Credentials ProxySQL

---

## 📊 Format du Rapport

Le rapport généré suit exactement le format des rapports de validation KeyBuzz :

- Résumé exécutif
- Composants testés par module
- Statistiques des tests
- Conclusion avec recommandations

---

## 🎯 Prochaines Étapes

Après validation complète de la couche 1 :

1. ✅ **Couche 1 validée** : Modules 2-8 opérationnels
2. ⏭️ **Module 9** : Installation Kubernetes (Kubespray + Calico IPIP)
3. ⏭️ **Modules 10-16** : Déploiement des applications KeyBuzz

---

**Document créé le** : 2025-11-25  
**Script** : `test_couche1_complete.sh`  
**Statut** : ✅ Prêt à utiliser

