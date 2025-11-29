# Guide de connexion SSH automatisée à install-01

## Configuration actuelle

- **IP** : 91.98.128.153
- **User** : root
- **Clé SSH** : `SSH/keybuzz_infra`
- **Passphrase** : stocké dans `SSH/passphrase.txt`

## Méthode 1 : Utilisation directe (Recommandé pour début)

### Depuis PowerShell

```powershell
# Se connecter
ssh -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" root@91.98.128.153

# Exécuter une commande
ssh -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" root@91.98.128.153 "hostname && whoami"
```

### Utiliser le script PowerShell

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\ssh_install01.ps1 "hostname && whoami"
```

## Méthode 2 : Configuration SSH (Une seule fois)

Créer/modifier `C:\Users\ludov\.ssh\config` :

```
Host install-01
    HostName 91.98.128.153
    User root
    IdentityFile C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra
    StrictHostKeyChecking accept-new
```

Ensuite, utiliser simplement :
```powershell
ssh install-01
ssh install-01 "hostname && whoami"
```

## Méthode 3 : ssh-agent (Automatisation complète)

### Étape 1 : Démarrer ssh-agent

```powershell
# Démarrer ssh-agent
Start-Service ssh-agent

# OU si le service n'existe pas
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

### Étape 2 : Charger la clé avec le passphrase

```powershell
# Lire le passphrase
$passphrase = Get-Content "C:\Users\ludov\Mon Drive\keybuzzio\SSH\passphrase.txt" -Raw

# Charger la clé (vous devrez entrer le passphrase une fois)
ssh-add "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra"
```

### Étape 3 : Utiliser SSH normalement

```powershell
# Plus besoin de spécifier la clé ni le passphrase
ssh root@91.98.128.153 "hostname && whoami"
```

## Méthode 4 : Utiliser WSL avec sshpass

Si vous avez WSL installé :

```powershell
# Dans WSL, installer sshpass
wsl sudo apt-get update && wsl sudo apt-get install -y sshpass

# Utiliser sshpass
$passphrase = Get-Content "C:\Users\ludov\Mon Drive\keybuzzio\SSH\passphrase.txt" -Raw
wsl bash -c "sshpass -p '$passphrase' ssh -i /mnt/c/Users/ludov/Mon\ Drive/keybuzzio/SSH/keybuzz_infra root@91.98.128.153 'hostname && whoami'"
```

## Scripts disponibles

J'ai créé plusieurs scripts pour faciliter la connexion :

1. **`scripts/ssh_install01.ps1`** - Script PowerShell simple
2. **`scripts/auto_ssh_install01.ps1`** - Script avec sshpass (nécessite WSL/Git Bash)
3. **`scripts/connect_install01.sh`** - Script Bash avec sshpass

## Pour les scripts d'automatisation

Quand je dois exécuter des commandes sur install-01, j'utiliserai :

```powershell
# Via le script PowerShell
.\Infra\scripts\ssh_install01.ps1 "commande"

# OU directement
ssh -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" root@91.98.128.153 "commande"
```

## Test de connexion

```powershell
# Test simple
.\Infra\scripts\ssh_install01.ps1 "hostname && whoami && echo 'Connexion réussie!'"
```

## Prochaines étapes

Une fois la connexion SSH fonctionnelle, je pourrai :

1. ✅ Me connecter à install-01
2. ✅ Cloner le dépôt GitHub
3. ✅ Exécuter les scripts d'installation
4. ✅ Configurer l'infrastructure KeyBuzz


