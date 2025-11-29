# Tests Complets Infrastructure KeyBuzz - Guide d'Exécution

**Date de création** : $(date +%Y-%m-%d)  
**Objectif** : Tester l'intégralité de l'infrastructure depuis install-01 avec vérification spéciale de haproxy-01 rebuild

---

## 📋 Contexte

haproxy-01 a été rebuild mais n'a probablement pas été réinstallé. Ce script de test va :
1. Vérifier spécifiquement l'état de haproxy-01
2. Tester tous les modules de l'infrastructure
3. Documenter toutes les erreurs
4. Proposer des actions correctives

---

## 🚀 Exécution des Tests

### Prérequis

1. Se connecter sur install-01 :
```bash
ssh root@91.98.128.153
# ou
ssh root@install-01.keybuzz.io
```

2. Aller dans le répertoire des scripts :
```bash
cd /opt/keybuzz-installer/scripts
```

3. Vérifier que le script est exécutable :
```bash
chmod +x 00_test_complet_infrastructure_haproxy01.sh
```

### Exécution

```bash
./00_test_complet_infrastructure_haproxy01.sh
```

Le script va :
- Créer automatiquement les logs dans `/opt/keybuzz-installer/logs/`
- Tester tous les modules (3 à 9)
- Vérifier spécifiquement haproxy-01
- Documenter toutes les erreurs dans un log séparé

---

## 📊 Modules Testés

### 1. Vérification haproxy-01 (Rebuild)
- ✅ Connectivité SSH
- ✅ Docker installé et fonctionnel
- ✅ Services HAProxy actifs
- ✅ Conteneurs Docker présents
- ✅ Configuration HAProxy présente
- ✅ Ports accessibles (5432, 6432, 6379, 5672, 8404)

### 2. Module 3 - PostgreSQL HA
- ✅ Connectivité PostgreSQL Master
- ✅ Patroni cluster status
- ✅ Réplication active
- ✅ HAProxy PostgreSQL (via 10.0.0.10 ou directement)
- ✅ PgBouncer

### 3. Module 4 - Redis HA
- ✅ Détection du master Redis
- ✅ Connectivité Redis
- ✅ Réplication Redis active
- ✅ HAProxy Redis
- ✅ Sentinel status

### 4. Module 5 - RabbitMQ HA
- ✅ Connectivité RabbitMQ
- ✅ Cluster RabbitMQ formé
- ✅ HAProxy RabbitMQ

### 5. Module 6 - MinIO
- ✅ Connectivité MinIO (port 9000)
- ✅ Console MinIO (port 9001)
- ✅ Conteneur MinIO actif

### 6. Module 7 - MariaDB Galera
- ✅ Connectivité MariaDB
- ✅ Cluster Galera opérationnel

### 7. Module 8 - ProxySQL
- ✅ Connectivité ProxySQL (port 3306)
- ✅ Conteneur ProxySQL actif
- ✅ LB 10.0.0.20 (ProxySQL)

### 8. Module 9 - K3s HA
- ✅ Service K3s actif sur master
- ✅ kubectl fonctionnel
- ✅ Cluster K3s opérationnel (nœuds Ready)
- ✅ Ingress NGINX DaemonSet présent

---

## 📝 Logs Générés

Le script génère automatiquement :

1. **Log principal** : `/opt/keybuzz-installer/logs/test_complet_infrastructure_YYYYMMDD_HHMMSS.log`
   - Contient tous les tests et résultats

2. **Log d'erreurs** : `/opt/keybuzz-installer/logs/test_complet_errors_YYYYMMDD_HHMMSS.log`
   - Contient uniquement les erreurs détectées

---

## 🔧 Actions Correctives

### Si haproxy-01 n'est pas réinstallé

Le script détectera automatiquement si haproxy-01 a besoin d'être réinstallé et affichera les instructions.

**Ordre d'installation** :

1. **Module 2 - Base OS & Sécurité** :
```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv
# Ou pour un seul serveur :
# Filtrer pour haproxy-01 dans le script
```

2. **Module 3 - PostgreSQL HA - HAProxy + PgBouncer** :
```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
./03_pg_03_install_haproxy_db_lb.sh ../../servers.tsv
```

3. **Module 4 - Redis HA - HAProxy Redis** :
```bash
cd /opt/keybuzz-installer/scripts/04_redis_ha
./04_redis_04_configure_haproxy_redis.sh ../../servers.tsv
```

4. **Module 5 - RabbitMQ HA - HAProxy RabbitMQ** :
```bash
cd /opt/keybuzz-installer/scripts/05_rabbitmq_ha
./05_rmq_03_configure_haproxy.sh ../../servers.tsv
```

### Si des erreurs sont détectées

1. Consulter le log d'erreurs :
```bash
tail -f /opt/keybuzz-installer/logs/test_complet_errors_*.log
```

2. Identifier le module en erreur

3. Réinstaller le module concerné selon les scripts disponibles

---

## 🎯 Résultats Attendus

### Tests de Base
- **Taux de réussite** : > 90% attendu
- **Tests critiques** : 100% requis (PostgreSQL, Redis, HAProxy)

### Tests de Failover
- Les tests de failover ne sont PAS inclus dans ce script
- Pour tester les failovers, exécuter : `00_test_complet_avec_failover.sh`

---

## 📚 Scripts de Test Disponibles

1. **00_test_complet_infrastructure_haproxy01.sh** (ce script)
   - Tests complets avec vérification haproxy-01
   - Non destructif
   - ~5-10 minutes

2. **00_test_complet_avec_failover.sh**
   - Tests complets + tests de failover
   - Destructif (arrête temporairement des services)
   - ~15-20 minutes

3. **00_test_complet_infrastructure.sh**
   - Tests complets sans vérification spéciale haproxy-01
   - Non destructif
   - ~5-10 minutes

---

## 🔍 Analyse des Erreurs

Le script documente automatiquement :
- Les erreurs de connectivité
- Les services non démarrés
- Les configurations manquantes
- Les problèmes de réplication
- Les problèmes de cluster

**Principe d'apprentissage** :
- Chaque erreur est documentée avec le contexte
- Les erreurs récurrentes sont identifiées
- Des actions correctives sont proposées

---

## 📞 Support

Si des erreurs persistent :

1. **Vérifier les logs détaillés** :
```bash
cd /opt/keybuzz-installer/logs
ls -lhtr | head -10
```

2. **Vérifier l'état des services** :
```bash
# PostgreSQL
ssh root@10.0.0.120 "docker ps | grep patroni"

# Redis
ssh root@10.0.0.123 "docker ps | grep redis"

# RabbitMQ
ssh root@10.0.0.126 "docker ps | grep rabbitmq"

# HAProxy
ssh root@10.0.0.11 "docker ps | grep haproxy"
```

3. **Consulter la documentation** :
   - `RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`
   - `POINT_TECHNIQUE_COMPLET_ETAT_INFRASTRUCTURE.md`

---

## ✅ Checklist Post-Tests

Après l'exécution des tests, vérifier :

- [ ] Tous les modules critiques sont opérationnels
- [ ] haproxy-01 est correctement réinstallé (si nécessaire)
- [ ] Les logs sont analysés
- [ ] Les erreurs sont corrigées
- [ ] Les tests sont relancés pour validation

---

**Document créé le** : $(date +%Y-%m-%d)  
**Dernière mise à jour** : $(date +%Y-%m-%d)  
**Version** : 1.0

