# 🔑 Génération et Ajout d'une Nouvelle Clé SSH

## 📋 Instructions Manuelles

### Étape 1 : Générer la Clé SSH

Ouvrez PowerShell et exécutez :

```powershell
# Aller dans le répertoire du projet
cd "C:\Users\ludov\Mon Drive\keybuzzio"

# Exécuter le script de génération
powershell -ExecutionPolicy Bypass -File Infra\scripts\11_support_chatwoot\Generate-SSHKey.ps1
```

**OU** générez manuellement :

```powershell
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$keyName = "keybuzz_install01_$timestamp"
$privateKeyPath = "$env:USERPROFILE\.ssh\$keyName"

ssh-keygen -t ed25519 -f $privateKeyPath -N '""' -C "keybuzz-install01-$timestamp"

# Afficher la clé publique
Get-Content "$privateKeyPath.pub"
```

### Étape 2 : Copier la Clé Publique

La clé publique sera affichée. Elle ressemble à :
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... keybuzz-install01-20241127
```

**COPIEZ TOUTE LA LIGNE** (de `ssh-ed25519` jusqu'à la fin).

### Étape 3 : Ajouter la Clé sur install-01

**Si vous êtes connecté sur install-01**, exécutez :

```bash
# 1. Ajouter la clé publique
echo "VOTRE_CLE_PUBLIQUE_COPIEE_ICI" >> ~/.ssh/authorized_keys

# 2. Vérifier les permissions
chmod 600 ~/.ssh/authorized_keys
chmod 700 ~/.ssh

# 3. Vérifier que la clé a été ajoutée
tail -1 ~/.ssh/authorized_keys
```

**OU depuis votre machine Windows** (si vous avez encore accès SSH) :

```powershell
# Remplacer le chemin par le chemin réel de votre clé publique
Get-Content "$env:USERPROFILE\.ssh\keybuzz_install01_*.pub" | ssh root@install-01 "cat >> ~/.ssh/authorized_keys"
```

### Étape 4 : Tester la Connexion

```powershell
# Trouver le nom exact de votre clé
Get-ChildItem "$env:USERPROFILE\.ssh\keybuzz_install01_*.pub" | Select-Object -First 1 | ForEach-Object {
    $privateKey = $_.FullName -replace '\.pub$', ''
    Write-Host "Test de connexion avec: $privateKey"
    ssh -i $privateKey root@install-01 "echo 'Connexion OK' && hostname"
}
```

## 📝 Emplacement des Fichiers

- **Clé privée** : `C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS`
- **Clé publique** : `C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS.pub`

## ⚠️ Important

- **NE PARTAGEZ JAMAIS** la clé privée
- Seule la **clé publique** doit être ajoutée sur install-01
- La clé privée reste sur votre machine Windows

## 🔍 Vérification

Après avoir ajouté la clé, testez :

```bash
# Depuis install-01, vérifier que la clé est présente
cat ~/.ssh/authorized_keys | grep keybuzz-install01
```

## 🚀 Utilisation

Une fois la clé ajoutée, vous pouvez vous connecter avec :

```powershell
ssh -i "C:\Users\ludov\.ssh\keybuzz_install01_YYYYMMDD_HHMMSS" root@install-01
```


