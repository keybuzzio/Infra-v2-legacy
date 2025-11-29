# Installation KeyBuzz - Système de Checkpoints

Ce document permet de suivre l'avancement de l'installation et de créer des checkpoints après chaque module validé.

## 📋 Checkpoints

### ✅ Checkpoint 0 : Préparation initiale
- [ ] Archive décompressée dans `/tmp/keybuzz-installer`
- [ ] Structure de répertoires créée dans `/opt/keybuzz-installer`
- [ ] Fichiers copiés depuis `/tmp` vers `/opt`
- [ ] Permissions configurées
- [ ] Prérequis vérifiés (SSH, Docker, etc.)
- [ ] `servers.tsv` vérifié et configuré
- [ ] Credentials préparés (si nécessaire)

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 1 : Module 1 - Inventaire & Réseau
- [ ] `servers.tsv` validé
- [ ] Tous les serveurs accessibles via SSH
- [ ] Réseau privé 10.0.0.0/16 fonctionnel
- [ ] Inventaire parsé et validé

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 2 : Module 2 - Base OS & Sécurité
- [ ] Module 2 appliqué sur tous les serveurs
- [ ] Validation Module 2 réussie (15/15 points)
- [ ] Docker installé et fonctionnel partout
- [ ] Swap désactivé partout
- [ ] UFW configuré et activé
- [ ] SSH durci
- [ ] DNS configuré
- [ ] Rapport de validation généré

**Date de validation** : _______________
**Validé par** : _______________
**Rapport** : `scripts/02_base_os_and_security/module2_validation_report_*.txt`

---

### ✅ Checkpoint 3 : Module 3 - PostgreSQL HA
- [ ] Credentials PostgreSQL créés
- [ ] Volumes XFS préparés
- [ ] Cluster Patroni RAFT installé (3 nœuds)
- [ ] HAProxy configuré sur haproxy-01/02
- [ ] LB Hetzner 10.0.0.10 configuré
- [ ] PgBouncer installé et configuré
- [ ] pgvector installé
- [ ] Tests de connectivité réussis
- [ ] Tests de failover réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 4 : Module 4 - Redis HA
- [ ] Cluster Redis installé (3 nœuds)
- [ ] Sentinel configuré
- [ ] HAProxy intégré
- [ ] Tests de connectivité réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 5 : Module 5 - RabbitMQ HA
- [ ] Cluster RabbitMQ Quorum installé
- [ ] HAProxy intégré
- [ ] Tests de connectivité réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 6 : Module 6 - MinIO
- [ ] MinIO installé et configuré
- [ ] Buckets créés
- [ ] Tests de connectivité réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 7 : Module 7 - MariaDB Galera
- [ ] Cluster MariaDB Galera installé (3 nœuds)
- [ ] ProxySQL configuré
- [ ] Tests de connectivité réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 8 : Module 8 - ProxySQL
- [ ] ProxySQL installé et configuré
- [ ] Intégration avec MariaDB validée

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 9 : Module 9 - K3s HA
- [ ] K3s masters installés (3 nœuds)
- [ ] K3s workers joints
- [ ] Cluster opérationnel
- [ ] Tests kubectl réussis

**Date de validation** : _______________
**Validé par** : _______________

---

### ✅ Checkpoint 10 : Module 10 - Load Balancers
- [ ] LB Hetzner configurés
- [ ] Health checks fonctionnels
- [ ] Routing validé

**Date de validation** : _______________
**Validé par** : _______________

---

## 📝 Notes de validation

Utilisez cette section pour noter les problèmes rencontrés et leurs solutions :

### Checkpoint 2 (Module 2)
- **Problèmes** : 
- **Solutions** : 

### Checkpoint 3 (Module 3)
- **Problèmes** : 
- **Solutions** : 

---

## 🔄 Procédure de réinstallation depuis un checkpoint

Si vous devez repartir depuis un checkpoint :

1. Restaurer l'archive complète dans `/tmp/keybuzz-installer`
2. Suivre les étapes jusqu'au checkpoint précédent
3. Vérifier que tous les points du checkpoint précédent sont validés
4. Continuer avec le module suivant

---

**Dernière mise à jour** : 18 novembre 2025


