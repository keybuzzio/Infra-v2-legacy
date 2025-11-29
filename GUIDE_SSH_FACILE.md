# Guide de connexion SSH facile à install-01

## 🎯 Objectif

Se connecter facilement à install-01 **SANS passphrase** et sans configuration complexe.

## ✅ Solution actuelle (Recommandée)

Une nouvelle clé SSH **sans passphrase** a été créée et configurée. Vous pouvez maintenant vous connecter très facilement !

### Méthode 1 : Utilisation directe avec SSH config (Le plus simple)

```powershell
# Connexion interactive
ssh install-01

# Exécuter une commande
ssh install-01 "hostname && whoami"
```

C'est tout ! Plus besoin de passphrase, plus besoin de ssh-agent. La configuration SSH est déjà faite dans `C:\Users\ludov\.ssh\config`.

### Méthode 2 : Utilisation avec le script PowerShell

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts"
.\connect_install01_simple.ps1
```

Ou pour exécuter une commande :

```powershell
.\connect_install01_simple.ps1 "hostname && whoami"
```

### Méthode 3 : Utilisation directe avec la clé

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio"
ssh -i "SSH\keybuzz_auto" root@91.98.128.153 "commande"
```

## 📋 Détails techniques

### Clés SSH disponibles

1. **`keybuzz_infra`** (ancienne clé avec passphrase)
   - Utilisée avec Putty pour vos connexions manuelles
   - Toujours fonctionnelle sur le serveur
   - **Vous pouvez continuer à l'utiliser normalement**

2. **`keybuzz_auto`** (nouvelle clé sans passphrase) ⭐
   - Utilisée pour les connexions automatiques
   - Pas de passphrase nécessaire
   - Configurée dans `~/.ssh/config`

### Configuration SSH

Le fichier `C:\Users\ludov\.ssh\config` est configuré pour utiliser automatiquement la nouvelle clé :

```
Host install-01
    HostName 91.98.128.153
    User root
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentityFile "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_auto"
```

## 🚀 Utilisation quotidienne

### Pour vous (connexions manuelles)

Vous pouvez continuer à utiliser **Putty avec l'ancienne clé** (`keybuzz_infra`) comme d'habitude. Rien ne change de votre côté.

### Pour les scripts automatiques

Les scripts et les connexions automatiques utilisent maintenant la nouvelle clé sans passphrase, donc tout est transparent.

## 🛠️ Dépannage

### "Permission denied (publickey)"

Vérifiez que la clé publique est bien sur le serveur :
```bash
# Sur install-01
cat ~/.ssh/authorized_keys
```

Vous devriez voir les deux clés :
- L'ancienne clé `keybuzz_infra`
- La nouvelle clé `keybuzz-auto-20251123`

### "Could not resolve hostname install-01"

Vérifiez que le fichier `~/.ssh/config` existe et contient la bonne configuration.

### La connexion ne fonctionne pas

Testez directement :
```powershell
ssh -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_auto" root@91.98.128.153 "hostname"
```

## 📝 Scripts disponibles

1. **`connect_install01_simple.ps1`** ⭐ - Connexion simple (recommandé)
2. **`connect_install01_quick.ps1`** - Ancien script avec ssh-agent (plus nécessaire)
3. **`setup_ssh_once.ps1`** - Configuration ssh-agent (plus nécessaire)

## ✨ Avantages de la nouvelle solution

- ✅ **Pas de passphrase** à entrer
- ✅ **Pas de ssh-agent** à configurer
- ✅ **Connexion instantanée** avec `ssh install-01`
- ✅ **L'ancienne clé fonctionne toujours** pour vos connexions Putty
- ✅ **Simple et fiable**

## 🔒 Sécurité

- La nouvelle clé est stockée localement sur votre machine
- Elle est protégée par les permissions du système de fichiers Windows
- L'ancienne clé avec passphrase reste disponible pour une sécurité renforcée si nécessaire
