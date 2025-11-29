# Installation Étape par Étape - KeyBuzz Infrastructure

**Date de début :** 2025-11-21  
**Méthode :** Installation module par module avec validation complète

---

## ✅ ÉTAPE A : Nettoyage Complet

### Commande exécutée :
```bash
cd /opt/keybuzz-installer/scripts
bash 00_cleanup_complete_installation.sh /opt/keybuzz-installer/servers.tsv
```

### Actions effectuées :

1. **Arrêt de tous les conteneurs Docker**
   - Sur chaque serveur (sauf install-01 et backn8n)
   - `docker stop $(docker ps -q)`
   - `docker rm $(docker ps -aq)`

2. **Suppression des images Docker**
   - `docker images --format "{{.Repository}}:{{.Tag}}" | xargs -r docker rmi -f`

3. **Nettoyage des volumes Docker**
   - `docker volume prune -f`
   - `docker network prune -f`

4. **Formatage des volumes XFS**
   - Détection automatique du périphérique (généralement /dev/sdb, /dev/sdc)
   - Démontage si monté
   - Suppression de l'entrée fstab
   - Formatage : `mkfs.xfs -f /dev/sdX`
   - **⚠️ TOUTES LES DONNÉES SONT SUPPRIMÉES**

5. **Nettoyage des fichiers de configuration**
   - Suppression de `/opt/keybuzz/*`
   - Suppression de `/etc/patroni`, `/etc/redis`, `/etc/rabbitmq`, etc.

6. **Désactivation des services systemd**
   - Arrêt et désactivation de tous les services
   - Suppression des fichiers de service
   - `systemctl daemon-reload`

### Résultat attendu :
- ✅ Tous les serveurs nettoyés
- ✅ Volumes formatés
- ✅ Credentials conservés sur install-01

**Log :** `/opt/keybuzz-installer/logs/cleanup.log`

---

## ✅ ÉTAPE B : Amélioration des Scripts

### Scripts améliorés :

1. **`00_cleanup_complete_installation.sh`**
   - ✅ Détection automatique des volumes
   - ✅ Formatage XFS sécurisé
   - ✅ Conservation des credentials

2. **`00_install_module_by_module.sh`**
   - ✅ Création automatique des dossiers
   - ✅ Copie automatique des credentials
   - ✅ Vérification des fichiers avant utilisation
   - ✅ Gestion des erreurs avec retry
   - ✅ Logs détaillés

3. **Gestion des credentials**
   - ✅ Génération automatique
   - ✅ Copie sur install-01 ET serveurs
   - ✅ Fichiers .env avec permissions 600

---

## 🔄 ÉTAPE C : Installation Module par Module

### Commande à exécuter :
```bash
cd /opt/keybuzz-installer/scripts
bash 00_install_module_by_module.sh --start-from-module=2
```

### Modules à installer (dans l'ordre) :

#### Module 2 : Base OS and Security
- Configuration de base du système
- Configuration UFW
- Installation des outils de base

#### Module 3 : PostgreSQL HA
- Génération des credentials
- Installation du cluster Patroni (3 nœuds)
- Configuration HAProxy
- Installation PgBouncer
- Installation pgvector

#### Module 4 : Redis HA
- Génération des credentials
- Déploiement Redis master/replica
- Déploiement Sentinel (3 instances)
- Configuration HAProxy + Watcher Sentinel
- Configuration LB healthcheck

#### Module 5 : RabbitMQ HA
- Génération des credentials (Erlang Cookie)
- Déploiement cluster quorum (3 nœuds)
- Configuration HAProxy

#### Module 6 : MinIO
- Génération des credentials
- Installation mono-nœud (puis cluster)
- Configuration client mc

#### Module 7 : MariaDB Galera HA
- Génération des credentials
- Déploiement cluster Galera (3 nœuds)
- Configuration LB

#### Module 8 : ProxySQL Advanced
- Génération des credentials
- Déploiement ProxySQL (2 instances)
- Configuration backends MariaDB
- Configuration monitoring

#### Module 9 : K3s HA Core
- Configuration UFW pour K3s
- Installation 3 masters
- Ajout des workers
- Bootstrap des addons
- Ingress NGINX DaemonSet (hostNetwork)

#### Module 10 : KeyBuzz API & Front
- Déploiement en DaemonSet (hostNetwork)
- Configuration Ingress
- Tests de connectivité

#### Module 11 : n8n
- Génération des credentials
- Déploiement en DaemonSet (hostNetwork)
- Configuration Ingress
- Tests de connectivité

---

## 📋 Checklist de Validation

Pour chaque module :
- [ ] Installation réussie
- [ ] Credentials générés et copiés
- [ ] Services démarrés
- [ ] Healthchecks OK
- [ ] Tests de failover réussis (si applicable)
- [ ] Logs vérifiés
- [ ] Erreurs documentées dans CORRECTIONS_ET_ERREURS.md

---

## 📝 Documentation

Tous les détails sont documentés dans :
- `INSTALLATION_DETAILED_LOG.md` - Journal détaillé
- `INSTALLATION_PROGRESS.md` - Progression en temps réel
- `CORRECTIONS_ET_ERREURS.md` - Toutes les corrections

---

**Prochaine action :** Lancer l'installation module par module

