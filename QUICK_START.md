# 🚀 Démarrage rapide - Installation KeyBuzz

## Vue d'ensemble

Ce guide vous permet de démarrer rapidement l'installation de l'infrastructure KeyBuzz.

## Prérequis

- ✅ Accès SSH à install-01 (91.98.128.153)
- ✅ Clé SSH configurée avec passphrase
- ✅ Dépôt GitHub `keybuzzio/Infra` accessible

## Étapes rapides

### 1. Se connecter à install-01

```powershell
# Depuis Windows
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1
```

### 2. Initialiser install-01

Une fois connecté sur install-01 :

```bash
# Option A : Si le dépôt est déjà cloné localement
cd /opt/keybuzz-installer
chmod +x scripts/00_init_install01.sh
./scripts/00_init_install01.sh

# Option B : Télécharger et exécuter depuis GitHub
curl -o /tmp/init.sh https://raw.githubusercontent.com/keybuzzio/Infra/main/scripts/00_init_install01.sh
chmod +x /tmp/init.sh
/tmp/init.sh
```

### 3. Configurer ADMIN_IP

```bash
cd /opt/keybuzz-installer
nano scripts/02_base_os_and_security/base_os.sh
```

Chercher et remplacer :
```bash
ADMIN_IP="XXX.YYY.ZZZ.TTT"  # Remplacer par votre IP publique
```

### 4. Vérifier la configuration

```bash
cd /opt/keybuzz-installer
chmod +x scripts/verify_setup.sh
./scripts/verify_setup.sh
```

### 5. Lancer le Module 2

⚠️ **IMPORTANT** : Ce module doit être appliqué sur TOUS les serveurs en premier.

```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv
```

**Durée** : ~10-15 minutes pour 52 serveurs

## Structure des modules

```
Module 1  : Inventaire (servers.tsv)
Module 2  : Base OS & Sécurité ⚠️ OBLIGATOIRE EN PREMIER
Module 3  : PostgreSQL HA
Module 4  : Redis HA
Module 5  : RabbitMQ HA
Module 6  : MinIO
Module 7  : MariaDB Galera
Module 8  : ProxySQL
Module 9  : K3s HA
Module 10 : Load Balancers
```

## Commandes utiles

### Vérifier l'état d'un serveur

```bash
ssh root@10.0.0.120 "docker --version && swapon --summary"
```

### Vérifier le Module 2

```bash
ssh root@10.0.0.120 "ufw status | head -10 && docker ps"
```

### Parser l'inventaire

```bash
cd /opt/keybuzz-installer
./scripts/01_inventory/parse_servers_tsv.sh servers.tsv
```

## Documentation complète

- `INSTALLATION_START.md` - Guide détaillé d'installation
- `docs/02_base_os_and_security.md` - Documentation Module 2
- `README.md` - Documentation générale

## Support

En cas de problème, vérifier :
1. Les logs du script : messages d'erreur affichés
2. La connexion SSH : `ssh root@<IP> "hostname"`
3. Les permissions : `ls -la scripts/**/*.sh`


