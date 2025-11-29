# Rapport de Correction - Cluster Patroni PostgreSQL

**Date** : 2025-11-23  
**Problème** : Cluster Patroni RAFT ne bootstrappe pas automatiquement  
**Statut** : 🔄 **EN COURS DE CORRECTION**

---

## 🔍 Diagnostic du Problème

### État Actuel du Cluster

- **Tous les nœuds (3/3)** : État **"stopped"** et **"uninitialized"**
- **Aucun Leader** élu
- **Cluster "unlocked"** (attente bootstrap)
- **Logs en boucle** : "waiting for leader to bootstrap"

### Configuration Patroni

- **Version Patroni installée** : 4.1.0
- **Version Patroni dans script** : 3.3.0 (04_postgres16_patroni_raft_FIXED.sh)
- **Scope** : keybuzz-pg
- **Namespace** : /db/
- **Configuration RAFT** : Correcte (3 nœuds, ports 7000)

### Containers et Services

- ✅ **Containers Patroni** : Actifs (pas de crash)
- ✅ **Connectivité réseau** : OK (ports 7000 et 8008 accessibles)
- ✅ **Services systemd** : Actifs

### Causes Probables Identifiées

1. **Incompatibilité de version** : Patroni 4.1.0 vs 3.3.0 (changements dans RAFT)
2. **Bootstrap RAFT manquant** : Le bootstrap automatique ne se déclenche pas
3. **Configuration bootstrap** : Peut-être un problème dans la section `bootstrap` du fichier Patroni

---

## 🔧 Actions de Correction Effectuées

### Étape 1 : Nettoyage Complet (Déjà Effectué)

1. ✅ Arrêt de tous les containers Patroni
2. ✅ Nettoyage des répertoires RAFT (`/opt/keybuzz/postgres/raft/*`)
3. ✅ Nettoyage des données PostgreSQL (`/opt/keybuzz/postgres/data/*`)
4. ✅ Correction des permissions (chown 999:999)
5. ✅ Redémarrage simultané des 3 nœuds

**Résultat** : ❌ Problème persiste

### Étape 2 : Investigation Approfondie (En Cours)

1. ✅ Vérification de la configuration Patroni complète
2. ✅ Vérification de la version Patroni installée
3. ✅ Analyse des logs détaillés
4. ✅ Vérification de la connectivité RAFT entre nœuds

**Résultat** : Configuration correcte, mais bootstrap ne se déclenche pas

### Étape 3 : Solution Proposée

**Option A : Réinstallation Complète avec Script Existant**

Utiliser le script d'installation existant `04_postgres16_patroni_raft_FIXED.sh` pour refaire une installation propre du cluster.

**Option B : Correction Manuelle de la Configuration**

Modifier la configuration Patroni pour forcer le bootstrap ou utiliser une méthode manuelle.

**Option C : Downgrade Patroni vers 3.3.0**

Forcer l'utilisation de Patroni 3.3.0 comme dans le script original.

---

## 📋 Plan de Correction

### Phase 1 : Vérification Préalable

1. ✅ Vérifier que tous les nœuds sont accessibles
2. ✅ Vérifier que Docker est installé et fonctionnel
3. ✅ Vérifier que les volumes XFS sont montés
4. ✅ Vérifier que les credentials sont configurés

### Phase 2 : Réinstallation Complète

1. **Arrêter tous les containers Patroni**
2. **Supprimer tous les containers Patroni**
3. **Nettoyer complètement** :
   - `/opt/keybuzz/postgres/raft/*`
   - `/opt/keybuzz/postgres/data/*`
   - `/opt/keybuzz/postgres/archive/*`
4. **Nettoyer les images Docker Patroni**
5. **Exécuter le script d'installation complet** : `04_postgres16_patroni_raft_FIXED.sh`

### Phase 3 : Vérification Post-Installation

1. ✅ Vérifier que les 3 containers sont démarrés
2. ✅ Vérifier le statut du cluster (`patronictl list`)
3. ✅ Vérifier qu'un Leader est élu
4. ✅ Vérifier que PostgreSQL est accessible
5. ✅ Tester la connectivité depuis HAProxy

---

## 📝 Commandes de Correction

### Réinstallation Complète

```bash
# Sur install-01
cd /opt/keybuzz-installer/scripts/03_postgresql_ha

# Exécuter le script d'installation complet
./04_postgres16_patroni_raft_FIXED.sh ../../servers.tsv
```

### Vérification Post-Installation

```bash
# Vérifier le statut du cluster
ssh root@10.0.0.120
docker exec patroni patronictl -c /etc/patroni/patroni.yml list

# Vérifier PostgreSQL
docker exec patroni pg_isready -U postgres

# Vérifier les logs
docker logs patroni --tail 50
```

---

## 📊 Tests de Validation

### Tests à Effectuer Après Correction

1. ✅ **Statut Cluster** : `patronictl list` doit montrer 1 Leader et 2 Replicas
2. ✅ **PostgreSQL Accessible** : `pg_isready` doit retourner "accepting connections"
3. ✅ **HAProxy Connectivité** : Port 5432 doit être accessible depuis haproxy-01
4. ✅ **PgBouncer Connectivité** : Port 6432 doit être accessible depuis haproxy-01
5. ✅ **Tests de Failover** : Arrêter le Leader et vérifier qu'un nouveau Leader est élu

---

## 🔄 Prochaines Étapes

1. ✅ **Exécuter la réinstallation complète** avec le script existant
2. ✅ **Vérifier que le cluster bootstrappe correctement**
3. ✅ **Documenter les résultats** dans ce rapport
4. ✅ **Mettre à jour** `GUIDE_COMPLET_INSTALLATION_KEYBUZZ.md` avec les corrections

---

## 📚 Références

- **Script d'installation** : `Infra/scripts/03_postgresql_ha/04_postgres16_patroni_raft_FIXED.sh`
- **Document de référence** : `Infra/GUIDE_COMPLET_INSTALLATION_KEYBUZZ.md`
- **Rapport technique** : `Infra/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`
- **Documentation Patroni** : https://patroni.readthedocs.io/

---

**Statut Final** : ⏳ **EN COURS**

**Prochaine Action** : Exécuter la réinstallation complète avec le script existant













