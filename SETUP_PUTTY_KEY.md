# Utiliser votre clé PuTTY (.ppk) avec les scripts KeyBuzz

## Vue d'ensemble

Si vous utilisez PuTTY avec un fichier `.ppk` protégé par passphrase, voici comment l'utiliser avec les scripts d'automatisation KeyBuzz.

## Option 1 : Convertir .ppk en OpenSSH (Recommandé)

### Étape 1 : Installer PuTTYgen

Si vous n'avez pas PuTTYgen :
- Télécharger PuTTY : https://www.putty.org/
- PuTTYgen est inclus dans l'installation

### Étape 2 : Convertir la clé

1. **Ouvrir PuTTYgen** :
   - Démarrer PuTTYgen depuis le menu Démarrer
   - Ou : `puttygen.exe` depuis la ligne de commande

2. **Charger votre clé .ppk** :
   - Cliquer sur "Load"
   - Sélectionner votre fichier `.ppk`
   - Entrer votre passphrase quand demandé

3. **Exporter en format OpenSSH** :
   - Menu : Conversions → Export OpenSSH key
   - Sauvegarder comme `keybuzz_infra` (sans extension)
   - **Important** : Ne pas entrer de passphrase lors de l'export (pour l'automatisation)
   - OU garder la passphrase si vous préférez (mais il faudra l'entrer à chaque fois)

4. **Sauvegarder la clé publique** :
   - Cliquer sur "Save public key"
   - Sauvegarder comme `keybuzz_infra.pub`

### Étape 3 : Placer les clés

**Dans Git Bash ou WSL** :

```bash
# Créer le dossier .ssh s'il n'existe pas
mkdir -p ~/.ssh

# Copier la clé privée (depuis Windows vers WSL/Git Bash)
# Si vous êtes dans WSL :
cp /mnt/c/Users/VOTRE_USER/Downloads/keybuzz_infra ~/.ssh/
# OU si vous êtes dans Git Bash :
cp /c/Users/VOTRE_USER/Downloads/keybuzz_infra ~/.ssh/

# Copier la clé publique
cp /mnt/c/Users/VOTRE_USER/Downloads/keybuzz_infra.pub ~/.ssh/

# Définir les bonnes permissions
chmod 600 ~/.ssh/keybuzz_infra
chmod 644 ~/.ssh/keybuzz_infra.pub
```

### Étape 4 : Déposer la clé publique sur install-01

```bash
# Afficher la clé publique
cat ~/.ssh/keybuzz_infra.pub

# Se connecter sur install-01 (avec votre méthode actuelle)
ssh root@91.98.128.153

# Sur install-01, ajouter la clé
mkdir -p ~/.ssh
chmod 700 ~/.ssh
nano ~/.ssh/authorized_keys
# Coller la clé publique à la fin
chmod 600 ~/.ssh/authorized_keys
```

### Étape 5 : Tester

```bash
# Test de connexion
ssh -i ~/.ssh/keybuzz_infra root@91.98.128.153 "hostname && whoami"
```

## Option 2 : Utiliser Pageant (Agent PuTTY)

Si vous préférez garder votre clé .ppk avec passphrase :

### Étape 1 : Démarrer Pageant

1. Démarrer Pageant (depuis le menu Démarrer)
2. Cliquer sur l'icône Pageant dans la barre des tâches
3. Cliquer sur "Add Key"
4. Sélectionner votre fichier `.ppk`
5. Entrer votre passphrase

### Étape 2 : Configurer WSL/Git Bash pour utiliser Pageant

**Dans WSL** :

```bash
# Installer socat
sudo apt install socat

# Créer un script pour utiliser Pageant
cat > ~/.ssh/use_pageant.sh << 'EOF'
#!/bin/bash
export SSH_AUTH_SOCK=$(wslpath -u "$(wslvar USERPROFILE)")/.ssh/pageant.sock
socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"/mnt/c/Program\ Files/PuTTY/pageant.exe -c",nofork &
EOF

chmod +x ~/.ssh/use_pageant.sh
```

**Dans Git Bash** :

```bash
# Créer un script similaire
cat > ~/.ssh/use_pageant.sh << 'EOF'
#!/bin/bash
export SSH_AUTH_SOCK=$HOME/.ssh/pageant.sock
socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"/c/Program\ Files/PuTTY/pageant.exe -c",nofork &
EOF

chmod +x ~/.ssh/use_pageant.sh
```

### Étape 3 : Utiliser

```bash
# Démarrer le forwarding vers Pageant
source ~/.ssh/use_pageant.sh

# Tester
ssh root@91.98.128.153 "hostname && whoami"
```

## Option 3 : Utiliser directement PuTTY depuis les scripts

Si vous préférez utiliser PuTTY directement, vous pouvez créer un wrapper :

```bash
# Créer un script wrapper
cat > ~/.ssh/putty_ssh.sh << 'EOF'
#!/bin/bash
# Wrapper pour utiliser PuTTY depuis les scripts
# Usage: putty_ssh.sh user@host command

HOST="${1%%@*}"
USER="${1#*@}"
HOST="${1##*@}"
COMMAND="${2}"

# Utiliser plink (inclus avec PuTTY)
plink.exe -ssh -i "C:\path\to\your\key.ppk" "${USER}@${HOST}" "${COMMAND}"
EOF

chmod +x ~/.ssh/putty_ssh.sh
```

## Recommandation

**Pour l'automatisation**, je recommande **Option 1** (conversion en OpenSSH sans passphrase) car :
- ✅ Plus simple à utiliser dans les scripts
- ✅ Pas besoin d'entrer de passphrase à chaque fois
- ✅ Compatible avec tous les outils (scp, rsync, etc.)
- ⚠️ La clé sans passphrase doit être protégée (permissions 600, jamais partagée)

**Pour la sécurité**, vous pouvez :
- Créer une clé dédiée uniquement pour l'automatisation
- Limiter l'accès par IP dans le firewall
- Utiliser une clé différente de votre clé personnelle

## Dépannage

### Erreur : "Could not open private key"

- Vérifier les permissions : `chmod 600 ~/.ssh/keybuzz_infra`
- Vérifier que la clé est bien au format OpenSSH (pas .ppk)

### Erreur : "Permission denied"

- Vérifier que la clé publique est dans `~/.ssh/authorized_keys` sur install-01
- Vérifier les permissions : `chmod 600 ~/.ssh/authorized_keys`

### Erreur : "Too many authentication failures"

```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/keybuzz_infra root@91.98.128.153
```

## Prochaines étapes

Une fois la clé configurée :

1. Tester la connexion : `./scripts/test_ssh_connection.sh`
2. Cloner le dépôt sur install-01
3. Lancer les scripts d'installation


