# Processus d'Installation KeyBuzz - Guide Complet

## Vue d'ensemble

Ce document décrit le processus d'installation complet de l'infrastructure KeyBuzz, étape par étape, en partant de zéro.

**Important** : Ce guide ne contient que les procédures qui ont été testées et validées.

## Prérequis

### 1. Infrastructure serveurs

- ✅ 49 serveurs Ubuntu 24.04 LTS configurés
- ✅ Réseau privé 10.0.0.0/16 fonctionnel
- ✅ Serveur `install-01` (10.0.0.20) accessible via SSH
- ✅ Fichier `servers.tsv` correctement rempli

### 2. Accès SSH

- ✅ Clé SSH configurée pour accès root sans mot de passe
- ✅ Clé SSH déposée sur tous les serveurs
- ✅ Test de connectivité SSH réussi

### 3. Configuration initiale

- ✅ Dépôt GitHub cloné sur `install-01` : `/opt/keybuzz-installer`
- ✅ `ADMIN_IP` configuré dans `base_os.sh` (91.98.128.153)

## Processus d'Installation

### Étape 1 : Préparation install-01

```bash
# Se connecter sur install-01
ssh root@91.98.128.153

# Cloner le dépôt (si pas déjà fait)
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer

# Vérifier la configuration
./scripts/01_inventory/parse_servers_tsv.sh servers.tsv
```

### Étape 2 : Module 2 - Base OS & Sécurité ⚠️ OBLIGATOIRE

**Ce module DOIT être appliqué en premier sur TOUS les serveurs.**

```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security

# Vérifier que ADMIN_IP est configuré
grep ADMIN_IP base_os.sh

# Lancer l'installation sur tous les serveurs
./apply_base_os_to_all.sh ../../servers.tsv
```

**Durée estimée** : 10-15 minutes pour 49 serveurs

**Ce que fait ce module** :
- ✅ Mise à jour OS (Ubuntu 24.04)
- ✅ Installation Docker
- ✅ Désactivation du swap
- ✅ Configuration UFW (firewall)
- ✅ Durcissement SSH
- ✅ Configuration DNS (1.1.1.1, 8.8.8.8)
- ✅ Optimisations kernel/sysctl
- ✅ Configuration journald

**Vérification** :
```bash
# Vérifier le statut
./check_module2_status.sh

# Ou en mode surveillance
./check_module2_status.sh --watch --interval 30
```

**Logs** : `/tmp/module2_final_complet.log`

### Étape 3 : Modules suivants (À implémenter)

Une fois le Module 2 terminé, les modules suivants peuvent être lancés dans l'ordre :

1. **Module 3** : PostgreSQL HA (Patroni RAFT)
2. **Module 4** : Redis HA (Sentinel)
3. **Module 5** : RabbitMQ HA (Quorum)
4. **Module 6** : MinIO (S3)
5. **Module 7** : MariaDB Galera (ERPNext)
6. **Module 8** : ProxySQL
7. **Module 9** : K3s HA
8. **Module 10** : Load Balancers

## Utilisation du Script Maître

Le script maître `00_master_install.sh` orchestre l'installation complète :

```bash
cd /opt/keybuzz-installer/scripts

# Installation complète (tous les modules)
./00_master_install.sh

# Ignorer le Module 2 (si déjà appliqué)
./00_master_install.sh --skip-module-2

# Lancer uniquement un module spécifique
./00_master_install.sh --module 2

# Aide
./00_master_install.sh --help
```

## Ordre d'Installation Validé

1. ✅ **Module 2** : Base OS & Sécurité (OBLIGATOIRE EN PREMIER)
   - ✅ Testé et validé
   - ✅ Fonctionne sur tous les serveurs
   - ✅ Scripts : `base_os.sh`, `apply_base_os_to_all.sh`

2. ⏳ **Module 3** : PostgreSQL HA
   - ⏳ À implémenter

3. ⏳ **Module 4** : Redis HA
   - ⏳ À implémenter

4. ⏳ **Module 5** : RabbitMQ HA
   - ⏳ À implémenter

5. ⏳ **Module 6** : MinIO
   - ⏳ À implémenter

6. ⏳ **Module 7** : MariaDB Galera
   - ⏳ À implémenter

7. ⏳ **Module 8** : ProxySQL
   - ⏳ À implémenter

8. ⏳ **Module 9** : K3s HA
   - ⏳ À implémenter

9. ⏳ **Module 10** : Load Balancers
   - ⏳ À implémenter

## Bonnes Pratiques Validées

### 1. Toujours désactiver le SWAP

✅ **Validé** : Le Module 2 désactive automatiquement le swap sur tous les serveurs.

### 2. DNS fixe

✅ **Validé** : Le Module 2 configure 1.1.1.1 et 8.8.8.8 avec `chattr +i` pour éviter l'écrasement.

### 3. UFW dans le bon ordre

✅ **Validé** : Le Module 2 configure UFW dans l'ordre correct :
1. Autoriser 10.0.0.0/16
2. Autoriser SSH depuis ADMIN_IP
3. Activer UFW
4. Ouvrir les ports spécifiques au rôle

### 4. Module 2 AVANT tout autre module

✅ **Validé** : Le Module 2 doit être appliqué avant tout autre module. C'est obligatoire.

## Dépannage

### Module 2 ne se termine pas

```bash
# Vérifier le statut
./check_module2_status.sh

# Vérifier les logs
tail -f /tmp/module2_final_complet.log

# Vérifier les processus
ps aux | grep apply_base_os_to_all
```

### Erreur SSH sur un serveur

Le script continue même en cas d'erreur sur un serveur. Vérifier :
- Clé SSH déposée sur le serveur
- Connectivité réseau 10.0.0.0/16
- Serveur accessible depuis install-01

### Relancer le Module 2

Le script est idempotent, vous pouvez le relancer :
```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv
```

## Logs et Suivi

Tous les logs sont disponibles dans :
- Module 2 : `/tmp/module2_final_complet.log`
- Script maître : `/opt/keybuzz-installer/logs/`

## Prochaines Étapes

Une fois le Module 2 terminé :

1. ✅ Vérifier que tous les serveurs ont été traités
2. ⏳ Implémenter le Module 3 (PostgreSQL HA)
3. ⏳ Implémenter les modules suivants dans l'ordre
4. ⏳ Configurer les applications KeyBuzz sur K3s

## Support

Pour toute question :
- Consulter la documentation dans `docs/`
- Vérifier les logs dans `/opt/keybuzz-installer/logs/`
- Vérifier le statut avec `./check_module2_status.sh`


