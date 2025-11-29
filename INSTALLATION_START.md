# Guide de démarrage de l'installation KeyBuzz

## Étape 1 : Connexion à install-01

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1
```

Ou directement :
```powershell
ssh -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" root@91.98.128.153
```

## Étape 2 : Initialisation de install-01

Une fois connecté sur install-01 :

```bash
# Télécharger le script d'initialisation
curl -o /tmp/init.sh https://raw.githubusercontent.com/keybuzzio/Infra/main/scripts/00_init_install01.sh

# OU si le dépôt est déjà cloné localement
cd /opt/keybuzz-installer
chmod +x scripts/00_init_install01.sh
./scripts/00_init_install01.sh
```

Le script va :
- ✅ Mettre à jour le système
- ✅ Installer les paquets de base (git, curl, etc.)
- ✅ Créer `/opt/keybuzz-installer`
- ✅ Cloner le dépôt GitHub `keybuzzio/Infra`
- ✅ Configurer les permissions des scripts

## Étape 3 : Configuration avant installation

### 3.1. Éditer base_os.sh

```bash
cd /opt/keybuzz-installer
nano scripts/02_base_os_and_security/base_os.sh
```

Chercher la ligne :
```bash
ADMIN_IP="XXX.YYY.ZZZ.TTT"
```

Remplacer par votre IP publique d'administration.

### 3.2. Vérifier servers.tsv

```bash
cd /opt/keybuzz-installer
cat servers.tsv | head -5
```

Vérifier que le fichier contient bien tous les serveurs.

## Étape 4 : Lancer le Module 2 (Base OS & Sécurité)

⚠️ **IMPORTANT** : Le Module 2 doit être appliqué sur TOUS les serveurs avant tout autre module.

```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security

# Vérifier les scripts
ls -la

# Lancer l'installation sur tous les serveurs
./apply_base_os_to_all.sh ../../servers.tsv
```

Ce script va :
- ✅ Lire `servers.tsv`
- ✅ Se connecter à chaque serveur via SSH
- ✅ Transférer et exécuter `base_os.sh` sur chaque serveur
- ✅ Appliquer la configuration Base OS & Sécurité

**Durée estimée** : 10-15 minutes pour 52 serveurs

## Étape 5 : Vérification

Après l'installation du Module 2, vérifier sur quelques serveurs :

```bash
# Tester sur un serveur DB
ssh root@10.0.0.120 "docker --version && swapon --summary && ufw status | head -5"

# Tester sur un serveur K3s
ssh root@10.0.0.100 "docker --version && swapon --summary"
```

## Prochaines étapes

Une fois le Module 2 terminé :

1. ✅ Module 3 : PostgreSQL HA
2. ✅ Module 4 : Redis HA
3. ✅ Module 5 : RabbitMQ HA
4. ✅ Module 6 : MinIO
5. ✅ Module 7 : MariaDB Galera
6. ✅ Module 8 : ProxySQL
7. ✅ Module 9 : K3s HA
8. ✅ Module 10 : Load Balancers

## Dépannage

### Erreur : "Permission denied"

- Vérifier que les clés SSH sont bien déposées sur tous les serveurs
- Vérifier les permissions : `chmod 600 ~/.ssh/authorized_keys`

### Erreur : "Connection refused"

- Vérifier que le serveur est accessible : `ping <IP>`
- Vérifier que SSH est actif : `systemctl status sshd`

### Erreur : "Swap is enabled"

- Le script devrait désactiver le swap automatiquement
- Vérifier manuellement : `swapon --summary`

## Support

Pour toute question, consulter :
- `docs/02_base_os_and_security.md` - Documentation complète du Module 2
- `README.md` - Documentation générale


