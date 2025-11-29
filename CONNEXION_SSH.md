# Guide de connexion SSH à install-01

## Informations du serveur

D'après `servers.tsv` :
- **Hostname** : install-01
- **IP Publique** : 91.98.128.153
- **IP Privée** : 10.0.0.20
- **FQDN** : install-01.keybuzz.io
- **User SSH** : root

## Connexion depuis Windows

### Option 1 : PowerShell / CMD

```powershell
ssh root@91.98.128.153
```

### Option 2 : Utiliser une clé SSH

Si vous avez une clé SSH :

```powershell
ssh -i C:\chemin\vers\votre\cle_ssh root@91.98.128.153
```

### Option 3 : Utiliser PuTTY

1. Ouvrir PuTTY
2. Host Name : `91.98.128.153`
3. Port : `22`
4. Connection type : `SSH`
5. Cliquer sur "Open"

## Première connexion

Lors de la première connexion, vous devrez accepter la clé du serveur :

```
The authenticity of host '91.98.128.153' can't be established.
Are you sure you want to continue connecting (yes/no)?
```

Tapez `yes` et appuyez sur Entrée.

### ⚠️ Erreur "REMOTE HOST IDENTIFICATION HAS CHANGED"

Si vous voyez cette erreur, c'est que la clé d'hôte a changé. Solution :

**Dans PowerShell** :
```powershell
ssh-keygen -R 91.98.128.153
```

**Dans Git Bash** :
```bash
ssh-keygen -R 91.98.128.153
```

Puis reconnectez-vous. Voir `FIX_SSH_HOST_KEY.md` pour plus de détails.

## Après connexion

Une fois connecté sur install-01, vous pouvez :

1. **Vérifier l'environnement** :
```bash
whoami
hostname
ip addr show
```

2. **Créer le répertoire de travail** :
```bash
mkdir -p /opt/keybuzz-installer
cd /opt/keybuzz-installer
```

3. **Cloner le dépôt GitHub** (méthode recommandée) :
```bash
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer
```

**OU transférer manuellement depuis Windows** :
```powershell
# Depuis PowerShell, dans le dossier Infra
scp -r * root@91.98.128.153:/opt/keybuzz-installer/
```

4. **Vérifier que les fichiers sont bien présents** :
```bash
cd /opt/keybuzz-installer
ls -la
```

## Prochaines étapes

Une fois le dépôt cloné ou les fichiers transférés :

1. **Rendre les scripts exécutables** :
```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
chmod +x *.sh
```

2. **Éditer base_os.sh pour mettre votre IP admin** :
```bash
nano base_os.sh
# Chercher ADMIN_IP="XXX.YYY.ZZZ.TTT" et remplacer par votre IP
```

3. **Lancer l'installation du Module 2** :
```bash
./apply_base_os_to_all.sh /opt/keybuzz-installer/servers.tsv
```

## Dépannage

### Problème de connexion

- Vérifier que le serveur est accessible : `ping 91.98.128.153`
- Vérifier que le port 22 est ouvert
- Vérifier vos clés SSH

### Permission denied

- Vérifier que vous utilisez la bonne clé SSH
- Vérifier que root peut se connecter (selon la config SSH du serveur)

### Timeout

- Vérifier votre connexion internet
- Vérifier que le firewall n'bloque pas SSH

