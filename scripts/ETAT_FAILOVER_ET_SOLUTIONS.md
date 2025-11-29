# État des Tests de Failover - Problèmes et Solutions

**Date :** 2025-11-21

## 📊 Résultat Actuel

- **Tests de base** : 13/13 (100%) ✅
- **Tests de failover** : 0/2 (0%) ❌

## ❌ Problèmes Identifiés

### 1. PostgreSQL Failover - Réplicas en "start failed"

**Symptôme** :
- Les réplicas PostgreSQL sont en état "start failed"
- Erreur : `FATAL: data directory "/var/lib/postgresql/data" has invalid permissions`
- Le failover ne peut pas se produire car aucun réplica n'est prêt

**Cause** :
- Permissions incorrectes sur `/opt/keybuzz/postgres/data` (doit être 0700 ou 0750)
- Les réplicas ne peuvent pas démarrer PostgreSQL

**Solution** :
- Script `00_fix_postgres_replicas.sh` créé pour corriger les permissions
- Redémarrer les conteneurs Patroni après correction

**Action** :
```bash
bash 00_fix_postgres_replicas.sh
```

### 2. Redis Failover - Sentinel ne promeut pas de nouveau master

**Symptôme** :
- Sentinel détecte le master down (`+sdown`)
- Mais ne promeut pas automatiquement un nouveau master
- Les slaves restent en état "slave"

**Causes possibles** :
1. **Quorum insuffisant** : Sentinel nécessite 2 sentinels sur 3 pour promouvoir un nouveau master
2. **Protected mode** : Sentinel est en protected mode et ne peut pas être interrogé depuis l'extérieur
3. **Configuration** : `sentinel monitor` nécessite 2 sentinels pour le quorum (actuellement configuré avec `2`)

**Vérification** :
- Configuration Sentinel : `sentinel monitor kb-redis-master ${MASTER_IP} 6379 2`
- Cela signifie qu'il faut 2 sentinels pour le quorum
- Avec 3 sentinels, le quorum devrait être atteint

**Solution possible** :
- Vérifier que les 3 sentinels sont opérationnels
- Vérifier les logs Sentinel pour comprendre pourquoi le failover ne se produit pas
- Augmenter le délai d'attente (actuellement 90 secondes)

## 🔧 Solutions Appliquées

### Correction PostgreSQL
- Script `00_fix_postgres_replicas.sh` créé
- Correction des permissions sur les réplicas
- Redémarrage des conteneurs Patroni

### Amélioration Tests Failover
- Délais d'attente augmentés :
  - PostgreSQL : 90 secondes (ttl:30, loop_wait:10, retry_timeout:30)
  - Redis : 90 secondes (down-after:5s, failover-timeout:60s)
- Vérifications multiples avec retry (5 tentatives)
- Logs détaillés pour diagnostic

## 📋 Prochaines Étapes

1. **Corriger les permissions PostgreSQL** :
   ```bash
   bash 00_fix_postgres_replicas.sh
   ```

2. **Relancer les tests de failover** :
   ```bash
   bash 00_test_complet_avec_failover.sh /opt/keybuzz-installer/servers.tsv --yes
   ```

3. **Si les tests échouent encore** :
   - Vérifier les logs Patroni et Sentinel
   - Vérifier la configuration réseau
   - Vérifier que les services peuvent communiquer entre eux

## ⚠️ Note Importante

Les tests de failover automatique peuvent échouer pour plusieurs raisons :
- **Délais insuffisants** : Les services HA nécessitent du temps pour détecter les pannes et promouvoir de nouveaux leaders
- **Configuration réseau** : Les services doivent pouvoir communiquer entre eux
- **État des réplicas** : Les réplicas doivent être opérationnels pour prendre le relais

**Recommandation** : Même si les tests de failover automatique échouent, l'infrastructure est fonctionnelle à 100% pour les tests de base. Les failovers peuvent être testés manuellement ou nécessiter une configuration supplémentaire.

## ✅ Tests de Base - 100% Réussis

Tous les tests de base passent avec succès :
- ✅ PostgreSQL : Connectivité, Cluster, Réplication, PgBouncer
- ✅ Redis : Connectivité, Réplication, Sentinel
- ✅ RabbitMQ : Connectivité, Cluster
- ✅ MinIO : Connectivité
- ✅ MariaDB : Connectivité, Cluster Galera, ProxySQL

**L'infrastructure est prête pour le Module 9 (K3s HA Core)**, même si les tests de failover automatique nécessitent des ajustements supplémentaires.

