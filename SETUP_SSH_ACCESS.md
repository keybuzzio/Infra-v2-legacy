# Configuration de l'accès SSH pour install-01

## Vue d'ensemble

Pour automatiser l'installation de l'infrastructure KeyBuzz, il faut configurer l'accès SSH vers `install-01` (91.98.128.153).

## Option 1 : Clé SSH dédiée (Recommandé)

### Sur votre machine Windows

1. **Générer une clé SSH** (si vous avez Git Bash ou WSL) :

```bash
# Dans Git Bash ou WSL
cd ~/.ssh
ssh-keygen -t ed25519 -f keybuzz_infra -N "" -C "keybuzz-infra-automation"
```

2. **Afficher la clé publique** :

```bash
cat ~/.ssh/keybuzz_infra.pub
```

3. **Copier la clé publique** (tout le contenu de la sortie)

### Sur install-01

1. **Se connecter** (avec votre méthode actuelle) :

```bash
ssh root@91.98.128.153
```

2. **Créer le dossier .ssh** :

```bash
mkdir -p ~/.ssh
chmod 700 ~/.ssh
```

3. **Ajouter la clé publique** :

```bash
nano ~/.ssh/authorized_keys
# Coller la clé publique à la fin du fichier
# Sauvegarder (Ctrl+O, Enter, Ctrl+X)
chmod 600 ~/.ssh/authorized_keys
```

4. **Tester la connexion** (depuis votre machine) :

```bash
ssh -i ~/.ssh/keybuzz_infra root@91.98.128.153
```

## Option 2 : Utiliser votre clé PuTTY existante

### Convertir .ppk en OpenSSH

1. **Installer PuTTYgen** (si pas déjà installé) :
   - Télécharger depuis : https://www.putty.org/

2. **Ouvrir PuTTYgen** :
   - Load votre fichier `.ppk`
   - Entrer votre passphrase
   - Menu : Conversions → Export OpenSSH key
   - Sauvegarder comme `keybuzz_infra` (sans extension)

3. **Placer la clé** :

```bash
# Dans Git Bash ou WSL
mkdir -p ~/.ssh
mv keybuzz_infra ~/.ssh/
chmod 600 ~/.ssh/keybuzz_infra
```

4. **Extraire la clé publique** :

```bash
# Dans PuTTYgen : bouton "Save public key"
# OU depuis la ligne de commande :
ssh-keygen -y -f ~/.ssh/keybuzz_infra > ~/.ssh/keybuzz_infra.pub
```

5. **Déposer la clé publique sur install-01** (même procédure que Option 1)

6. **Tester** :

```bash
ssh -i ~/.ssh/keybuzz_infra root@91.98.128.153
```

## Option 3 : Utiliser Pageant (PuTTY Agent) avec WSL/Git Bash

Si vous utilisez PuTTY avec Pageant :

1. **Démarrer Pageant** et charger votre clé `.ppk`

2. **Dans WSL/Git Bash**, configurer le forwarding :

```bash
# Installer socat si nécessaire
sudo apt install socat  # Dans WSL

# Créer un script pour utiliser Pageant
cat > ~/.ssh/use_pageant.sh << 'EOF'
#!/bin/bash
export SSH_AUTH_SOCK=$(wslpath -u "$(wslvar USERPROFILE)")/.ssh/pageant.sock
socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork EXEC:"/mnt/c/Program\ Files/PuTTY/pageant.exe -c",nofork &
EOF

chmod +x ~/.ssh/use_pageant.sh
```

3. **Utiliser** :

```bash
source ~/.ssh/use_pageant.sh
ssh root@91.98.128.153
```

## Configuration pour les scripts

Une fois l'accès SSH configuré, les scripts utiliseront automatiquement :

- La clé `~/.ssh/keybuzz_infra` si elle existe
- Sinon, la clé par défaut (`~/.ssh/id_rsa` ou `~/.ssh/id_ed25519`)

### Test de connexion

```bash
# Test simple
ssh root@91.98.128.153 "hostname && whoami"

# Test avec clé spécifique
ssh -i ~/.ssh/keybuzz_infra root@91.98.128.153 "hostname && whoami"
```

## Dépannage

### Erreur : "Permission denied (publickey)"

- Vérifier que la clé publique est bien dans `~/.ssh/authorized_keys` sur install-01
- Vérifier les permissions : `chmod 600 ~/.ssh/authorized_keys`
- Vérifier les permissions du dossier : `chmod 700 ~/.ssh`

### Erreur : "Host key verification failed"

```bash
ssh-keygen -R 91.98.128.153
ssh root@91.98.128.153
# Accepter la clé du serveur
```

### Erreur : "Too many authentication failures"

```bash
ssh -o IdentitiesOnly=yes -i ~/.ssh/keybuzz_infra root@91.98.128.153
```

## Sécurité

⚠️ **Important** :
- Ne jamais partager votre clé privée
- Utiliser une clé dédiée pour l'automatisation (sans passphrase uniquement si nécessaire)
- Limiter l'accès SSH par IP si possible (firewall)
- Désactiver l'authentification par mot de passe sur install-01

## Prochaines étapes

Une fois l'accès SSH configuré :

1. Tester la connexion
2. Cloner le dépôt sur install-01
3. Lancer les scripts d'installation


