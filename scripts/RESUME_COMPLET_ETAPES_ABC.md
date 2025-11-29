# Résumé Complet des Étapes A, B et C - Installation KeyBuzz

**Date :** 2025-11-21  
**Objectif :** Installation complète depuis zéro avec validation de chaque étape

---

## ✅ ÉTAPE A : Nettoyage Complet

### Statut : 🔄 EN COURS

### Script utilisé :
- **Fichier :** `00_cleanup_complete_installation.sh`
- **Localisation :** `/opt/keybuzz-installer/scripts/`
- **Log :** `/opt/keybuzz-installer/logs/cleanup.log`

### Commandes exécutées :
```bash
cd /opt/keybuzz-installer/scripts
echo 'OUI' | timeout 600 bash 00_cleanup_complete_installation.sh /opt/keybuzz-installer/servers.tsv 2>&1 | tee /opt/keybuzz-installer/logs/cleanup.log
```

### Actions effectuées sur chaque serveur (47 serveurs) :

#### 1. Arrêt et suppression des conteneurs Docker
```bash
docker stop $(docker ps -q) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true
```

#### 2. Suppression des images Docker
```bash
docker images --format "{{.Repository}}:{{.Tag}}" | grep -vE "^<none>|^REPOSITORY" | xargs -r docker rmi -f 2>/dev/null || true
```

#### 3. Nettoyage des volumes et réseaux Docker
```bash
docker volume prune -f
docker network prune -f
```

#### 4. Formatage des volumes XFS
- **Détection automatique** du périphérique (généralement `/dev/sdb`, `/dev/sdc`, etc.)
- **Démontage** si monté : `umount ${MOUNT_PATH}`
- **Suppression fstab** : `sed -i "#${MOUNT_PATH}#d" /etc/fstab`
- **Formatage XFS** : `mkfs.xfs -f ${DEVICE}`
- **⚠️ ATTENTION : Toutes les données sont supprimées**

#### 5. Nettoyage des fichiers de configuration
```bash
rm -rf /opt/keybuzz/*
rm -rf /etc/patroni
rm -rf /etc/redis
rm -rf /etc/rabbitmq
rm -rf /etc/mariadb
rm -rf /etc/minio
rm -rf /etc/haproxy
rm -rf /etc/pgbouncer
rm -rf /etc/proxysql
```

#### 6. Désactivation des services systemd
```bash
systemctl stop patroni-docker redis-docker rabbitmq-docker mariadb-docker haproxy-redis haproxy-rabbitmq pgbouncer proxysql
systemctl disable patroni-docker redis-docker rabbitmq-docker mariadb-docker haproxy-redis haproxy-rabbitmq pgbouncer proxysql
rm -f /etc/systemd/system/*patroni*.service
rm -f /etc/systemd/system/*redis*.service
rm -f /etc/systemd/system/*rabbitmq*.service
rm -f /etc/systemd/system/*mariadb*.service
rm -f /etc/systemd/system/*haproxy*.service
rm -f /etc/systemd/system/*pgbouncer*.service
rm -f /etc/systemd/system/*proxysql*.service
systemctl daemon-reload
```

### Serveurs exclus du nettoyage :
- `install-01` (serveur de contrôle, credentials conservés)
- `backn8n.keybuzz.io` (serveur de backup)

### Résultat attendu :
- ✅ 47 serveurs nettoyés
- ✅ Tous les volumes XFS formatés
- ✅ Tous les conteneurs Docker supprimés
- ✅ Tous les fichiers de configuration nettoyés
- ✅ Credentials conservés sur install-01

### Corrections appliquées pendant le développement :
1. ✅ Correction détection clé SSH (fallback si absente)
2. ✅ Correction extraction configuration volumes depuis NOTES (remplacement BASH_REMATCH par sed)
3. ✅ Ajout timeout pour éviter les blocages

---

## ✅ ÉTAPE B : Amélioration des Scripts

### Statut : ✅ TERMINÉ

### Scripts créés/améliorés :

#### 1. `00_cleanup_complete_installation.sh`

**Améliorations :**
- ✅ Détection automatique des volumes depuis `servers.tsv` (colonne NOTES)
- ✅ Formatage XFS avec vérification du périphérique
- ✅ Conservation des credentials (ne supprime pas `/opt/keybuzz-installer/credentials/`)
- ✅ Gestion des erreurs (continue même si un serveur échoue)
- ✅ Logs détaillés pour chaque serveur
- ✅ Support de l'authentification SSH par défaut si clé absente

**Fonctionnalités :**
- Détection automatique du périphérique de volume (évite de formater le disque système)
- Vérification que le volume n'est pas le disque système (`lsblk`)
- Formatage sécurisé avec `mkfs.xfs -f`
- Nettoyage complet mais préservation des credentials

#### 2. `00_install_module_by_module.sh`

**Améliorations :**
- ✅ Création automatique de TOUS les dossiers nécessaires avant installation
- ✅ Copie automatique des credentials sur install-01 ET sur tous les serveurs concernés
- ✅ Vérification de l'existence des fichiers avant utilisation
- ✅ Gestion des erreurs avec retry (3 tentatives par module)
- ✅ Logs détaillés par module (`/opt/keybuzz-installer/logs/module_N_install.log`)
- ✅ Validation automatique après chaque module (exécution des tests si disponibles)
- ✅ Documentation automatique des erreurs dans `ERROR_LOG`

**Fonctionnalités principales :**

##### a) Préparation des dossiers (`prepare_directories`)
- Crée tous les dossiers nécessaires sur install-01
- Crée les dossiers spécifiques selon le rôle sur chaque serveur
- Permissions correctes (700 pour credentials, 755 pour le reste)

##### b) Copie des credentials (`copy_credentials_to_servers`)
- Identifie automatiquement les serveurs qui ont besoin des credentials
- Copie les fichiers `.env` sur install-01 ET sur tous les serveurs concernés
- Permissions 600 sur les fichiers credentials

##### c) Installation avec retry (`install_module`)
- 3 tentatives maximum par module
- Analyse automatique des erreurs :
  - "No such file or directory" → Recréation des dossiers
  - "unbound variable" → Documentation dans ERROR_LOG
  - "Permission denied" → Documentation dans ERROR_LOG
- Logs séparés par module

##### d) Validation automatique
- Exécute les scripts de test si disponibles (`*test*.sh`)
- Logs de test séparés (`module_N_test.log`)

#### 3. Gestion des Credentials

**Système complet :**

1. **Génération automatique**
   - Scripts `*00*credentials*.sh` dans chaque module
   - Génération si fichier absent
   - Réutilisation si fichier existant (mode non-interactif avec `--yes`)

2. **Stockage centralisé**
   - Sur install-01 : `/opt/keybuzz-installer/credentials/*.env`
   - Sur chaque serveur : `/opt/keybuzz-installer/credentials/*.env`
   - Permissions : 600 (lecture/écriture propriétaire uniquement)

3. **Copie automatique**
   - Identifie les serveurs concernés selon le module
   - Copie via `scp` avec clé SSH
   - Vérifie l'accessibilité SSH avant copie

4. **Conservation lors du nettoyage**
   - Le script de nettoyage NE SUPPRIME PAS `/opt/keybuzz-installer/credentials/`
   - Les credentials sont préservés pour la réinstallation

### Documentation créée :

1. **`INSTALLATION_DETAILED_LOG.md`**
   - Journal détaillé de chaque module
   - Checklist de validation
   - Notes importantes

2. **`INSTALLATION_PROGRESS.md`**
   - Progression en temps réel
   - Statut de chaque module
   - Erreurs rencontrées

3. **`INSTALLATION_STEP_BY_STEP.md`**
   - Guide étape par étape
   - Commandes à exécuter
   - Checklist de validation

4. **`CORRECTIONS_ET_ERREURS.md`** (existant, mis à jour)
   - Toutes les erreurs rencontrées
   - Corrections appliquées
   - Historique des corrections

---

## 🔄 ÉTAPE C : Installation Module par Module

### Statut : ⏳ EN ATTENTE (nettoyage en cours)

### Commande à exécuter après nettoyage :
```bash
cd /opt/keybuzz-installer/scripts
bash 00_install_module_by_module.sh --start-from-module=2
```

### Ordre d'installation :

#### Module 2 : Base OS and Security
- **Script :** `02_base_os_and_security/apply_base_os_to_all.sh`
- **Actions :** Configuration de base, UFW, outils de base
- **Validation :** Accès SSH, UFW configuré

#### Module 3 : PostgreSQL HA
- **Script :** `03_postgresql_ha/03_pg_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Installation cluster Patroni (3 nœuds)
  3. Configuration HAProxy
  4. Installation PgBouncer
  5. Installation pgvector
- **Validation :** Cluster opérationnel, failover testé

#### Module 4 : Redis HA
- **Script :** `04_redis_ha/04_redis_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Préparation nœuds
  3. Déploiement Redis master/replica
  4. Déploiement Sentinel (3 instances)
  5. Configuration HAProxy + Watcher Sentinel
  6. Configuration LB healthcheck
- **Validation :** Redis opérationnel, Sentinel opérationnel, Watcher fonctionnel, failover testé
- **⚠️ Points critiques :** Watcher Sentinel INDISPENSABLE (corrigé)

#### Module 5 : RabbitMQ HA
- **Script :** `05_rabbitmq_ha/05_rmq_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials (Erlang Cookie)
  2. Préparation nœuds
  3. Déploiement cluster quorum (3 nœuds)
  4. Configuration HAProxy
- **Validation :** Cluster opérationnel, failover testé

#### Module 6 : MinIO
- **Script :** `06_minio/06_minio_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Préparation nœuds
  3. Installation mono-nœud (puis cluster)
  4. Configuration client mc
- **Validation :** MinIO opérationnel, client configuré

#### Module 7 : MariaDB Galera HA
- **Script :** `07_mariadb_galera/07_maria_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Préparation nœuds
  3. Déploiement cluster Galera (3 nœuds)
  4. Configuration LB
- **Validation :** Cluster opérationnel, failover testé

#### Module 8 : ProxySQL Advanced
- **Script :** `08_proxysql_advanced/08_proxysql_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Préparation nœuds
  3. Déploiement ProxySQL (2 instances)
  4. Configuration backends MariaDB
  5. Configuration monitoring
- **Validation :** ProxySQL opérationnel, backends configurés

#### Module 9 : K3s HA Core
- **Script :** `09_k3s_ha/09_k3s_apply_all.sh`
- **Sous-étapes :**
  1. Configuration UFW pour K3s
  2. Installation 3 masters
  3. Ajout des workers
  4. Bootstrap des addons
  5. Ingress NGINX DaemonSet (hostNetwork)
- **Validation :** Cluster opérationnel, Ingress fonctionnel
- **⚠️ Points critiques :** DaemonSet + hostNetwork (solution validée)

#### Module 10 : KeyBuzz API & Front
- **Script :** `10_keybuzz/10_keybuzz_apply_all.sh`
- **Sous-étapes :**
  1. Déploiement en DaemonSet (hostNetwork)
  2. Configuration Ingress
  3. Tests de connectivité
- **Validation :** API et Front accessibles
- **⚠️ Points critiques :** DaemonSet + hostNetwork

#### Module 11 : n8n
- **Script :** `11_n8n/11_n8n_apply_all.sh`
- **Sous-étapes :**
  1. Génération credentials
  2. Déploiement en DaemonSet (hostNetwork)
  3. Configuration Ingress
  4. Tests de connectivité
- **Validation :** n8n accessible, connexions DB/Redis OK
- **⚠️ Points critiques :** DaemonSet + hostNetwork

### Processus de validation pour chaque module :

1. **Installation**
   - Exécution du script avec `--yes` (non-interactif)
   - Retry automatique en cas d'erreur (3 tentatives)
   - Logs détaillés

2. **Vérification**
   - Services démarrés
   - Healthchecks OK
   - Credentials copiés

3. **Tests**
   - Exécution des scripts de test si disponibles
   - Tests de failover pour les services HA
   - Logs de test séparés

4. **Documentation**
   - Erreurs documentées dans `CORRECTIONS_ET_ERREURS.md`
   - Progression mise à jour dans `INSTALLATION_PROGRESS.md`

---

## 📋 Checklist Globale

### Préparation
- [x] Scripts créés et améliorés
- [x] Documentation créée
- [x] Scripts copiés sur install-01
- [x] Nettoyage lancé

### Nettoyage
- [ ] Nettoyage terminé (47 serveurs)
- [ ] Volumes formatés
- [ ] Credentials conservés
- [ ] Logs vérifiés

### Installation
- [ ] Module 2 installé et validé
- [ ] Module 3 installé et validé
- [ ] Module 4 installé et validé
- [ ] Module 5 installé et validé
- [ ] Module 6 installé et validé
- [ ] Module 7 installé et validé
- [ ] Module 8 installé et validé
- [ ] Module 9 installé et validé
- [ ] Module 10 installé et validé
- [ ] Module 11 installé et validé

### Validation Finale
- [ ] Tests complets exécutés (`00_test_complet_infrastructure.sh`)
- [ ] Tous les failovers testés
- [ ] Documentation complète
- [ ] Master script mis à jour

---

## 📝 Notes Importantes

1. **Aucune erreur n'est "petite"** - Toutes doivent être corrigées pour la production
2. **Le watcher Sentinel est INDISPENSABLE** - Ne jamais le rendre optionnel
3. **Documenter toutes les corrections** - Pour éviter de retomber sur les mêmes problèmes
4. **Tester tous les failovers** - Avant de considérer l'installation comme complète
5. **Credentials toujours sauvegardés** - Sur install-01 ET sur les serveurs concernés
6. **DaemonSet + hostNetwork** - Solution validée pour contourner VXLAN bloqué

---

## 🔍 Fichiers de Logs

- **Nettoyage :** `/opt/keybuzz-installer/logs/cleanup.log`
- **Installation globale :** `/opt/keybuzz-installer/logs/module_by_module_install.log`
- **Erreurs :** `/opt/keybuzz-installer/logs/module_by_module_errors.log`
- **Par module :** `/opt/keybuzz-installer/logs/module_N_install.log`
- **Tests par module :** `/opt/keybuzz-installer/logs/module_N_test.log`

---

**Dernière mise à jour :** $(date '+%Y-%m-%d %H:%M:%S')

