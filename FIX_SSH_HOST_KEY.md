# Résolution du problème de clé d'hôte SSH

## Problème

L'erreur indique que la clé d'hôte SSH a changé pour `91.98.128.153` (install-01). C'est normal si :
- Le serveur a été réinstallé
- C'est la première connexion avec cette IP
- La clé d'hôte a été régénérée

## Solution rapide

### Option 1 : Supprimer l'ancienne clé (Recommandé)

**Dans PowerShell ou CMD** :

```powershell
# Supprimer l'ancienne entrée pour cette IP
ssh-keygen -R 91.98.128.153

# OU supprimer manuellement la ligne dans known_hosts
notepad C:\Users\ludov\.ssh\known_hosts
# Supprimer la ligne 3 (ou celle contenant 91.98.128.153)
```

**Dans Git Bash** :

```bash
# Supprimer l'ancienne entrée
ssh-keygen -R 91.98.128.153

# OU éditer manuellement
nano ~/.ssh/known_hosts
# Supprimer la ligne contenant 91.98.128.153
```

### Option 2 : Accepter la nouvelle clé automatiquement

**Dans PowerShell** :

```powershell
# Se connecter en acceptant automatiquement la nouvelle clé
ssh -o StrictHostKeyChecking=accept-new root@91.98.128.153
```

**Dans Git Bash** :

```bash
ssh -o StrictHostKeyChecking=accept-new root@91.98.128.153
```

## Configuration SSH pour Cursor/VS Code

### Étape 1 : Nettoyer known_hosts

```powershell
# Dans PowerShell
ssh-keygen -R 91.98.128.153
```

### Étape 2 : Configurer SSH config pour Cursor

Créer ou éditer `C:\Users\ludov\.ssh\config` :

```
Host install-01
    HostName 91.98.128.153
    User root
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentityFile ~/.ssh/keybuzz_infra
    # OU si vous utilisez une autre clé :
    # IdentityFile ~/.ssh/id_rsa
```

### Étape 3 : Tester la connexion

```powershell
# Tester depuis PowerShell
ssh install-01 "hostname && whoami"
```

### Étape 4 : Reconnecter dans Cursor

1. Dans Cursor, appuyer sur `F1` ou `Ctrl+Shift+P`
2. Taper : `Remote-SSH: Connect to Host`
3. Sélectionner `install-01`
4. Accepter la nouvelle clé quand demandé

## Solution permanente : Accepter automatiquement les nouvelles clés

Pour éviter ce problème à l'avenir, ajouter dans `~/.ssh/config` :

```
Host install-01
    HostName 91.98.128.153
    User root
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
```

## Vérification

Après avoir nettoyé known_hosts, tester :

```powershell
# Dans PowerShell
ssh root@91.98.128.153 "hostname"
```

Vous devriez voir un message demandant d'accepter la clé :
```
The authenticity of host '91.98.128.153' can't be established.
ED25519 key fingerprint is SHA256:spbV2lsuLxR+bwGcBs/HYv/xIU5accoLEZa4jeaeChw.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Tapez `yes` pour accepter.

## Dépannage supplémentaire

### Si le problème persiste

1. **Vérifier que vous vous connectez au bon serveur** :
```powershell
ping 91.98.128.153
```

2. **Vérifier les permissions de known_hosts** :
```powershell
# Dans PowerShell
icacls C:\Users\ludov\.ssh\known_hosts
```

3. **Supprimer complètement known_hosts** (si nécessaire) :
```powershell
# ATTENTION : Cela supprimera toutes les clés d'hôtes connues
Remove-Item C:\Users\ludov\.ssh\known_hosts
```

4. **Vérifier la configuration SSH** :
```powershell
ssh -v root@91.98.128.153
```

## Pour Cursor Remote SSH spécifiquement

Si Cursor continue d'avoir des problèmes :

1. **Fermer toutes les fenêtres Cursor**
2. **Nettoyer known_hosts** :
```powershell
ssh-keygen -R 91.98.128.153
```
3. **Ouvrir Cursor**
4. **Se connecter via Remote-SSH** :
   - `F1` → `Remote-SSH: Connect to Host` → `install-01`
5. **Accepter la clé** quand demandé

## Configuration recommandée pour Cursor

Créer `C:\Users\ludov\.ssh\config` avec :

```
Host install-01
    HostName 91.98.128.153
    User root
    Port 22
    StrictHostKeyChecking accept-new
    UserKnownHostsFile ~/.ssh/known_hosts
    IdentityFile ~/.ssh/keybuzz_infra
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

Puis dans Cursor :
- `F1` → `Remote-SSH: Open SSH Configuration File`
- Sélectionner `C:\Users\ludov\.ssh\config`
- Vérifier que la configuration est correcte


