# Configuration Git pour KeyBuzz Infrastructure

## Dépôt GitHub

Le dépôt officiel est : **https://github.com/keybuzzio/Infra.git**

## Configuration initiale sur install-01

### 1. Se connecter sur install-01

```bash
ssh root@91.98.128.153
```

### 2. Installer Git (si nécessaire)

```bash
apt update
apt install -y git
```

### 3. Configurer Git (première fois)

```bash
git config --global user.name "KeyBuzz Infrastructure"
git config --global user.email "infra@keybuzz.io"
```

### 4. Cloner le dépôt

```bash
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer
```

### 5. Vérifier la structure

```bash
ls -la
# Vous devriez voir : docs/, scripts/, servers.tsv, README.md, etc.
```

## Workflow Git recommandé

### Branches principales

- `main` : Production (infrastructure stable)
- `develop` : Développement (nouvelles fonctionnalités)
- `feature/*` : Nouvelles fonctionnalités
- `hotfix/*` : Correctifs urgents

### Commits

Format recommandé pour les messages de commit :

```
[Module X] Description courte

- Détail 1
- Détail 2
- Détail 3
```

Exemples :
```
[Module 2] Base OS & Sécurité - Script base_os.sh

- Ajout désactivation swap
- Configuration UFW par rôle
- Fix DNS resolv.conf
```

### Push vers GitHub

```bash
# Ajouter les fichiers modifiés
git add .

# Commit avec message descriptif
git commit -m "[Module X] Description"

# Push vers GitHub
git push origin main
```

## Authentification GitHub

### Option 1 : Token d'accès personnel (recommandé)

1. Créer un token sur GitHub : Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Permissions nécessaires : `repo` (accès complet aux dépôts)
3. Utiliser le token comme mot de passe lors du push

### Option 2 : Clé SSH

1. Générer une clé SSH sur install-01 :
```bash
ssh-keygen -t ed25519 -C "infra@keybuzz.io"
cat ~/.ssh/id_ed25519.pub
```

2. Ajouter la clé publique dans GitHub : Settings → SSH and GPG keys → New SSH key

3. Tester la connexion :
```bash
ssh -T git@github.com
```

4. Cloner avec SSH :
```bash
git clone git@github.com:keybuzzio/Infra.git keybuzz-installer
```

## Structure des commits par module

Chaque module doit être commité séparément :

```bash
# Module 2 - Base OS
git add scripts/02_base_os_and_security/ docs/02_base_os_and_security.md
git commit -m "[Module 2] Base OS & Sécurité - Scripts et documentation"

# Module 3 - PostgreSQL
git add scripts/03_postgresql/ docs/03_postgresql_ha.md
git commit -m "[Module 3] PostgreSQL HA - Installation Patroni RAFT"
```

## Tags de version

Pour marquer des versions stables :

```bash
git tag -a v1.0.0 -m "Version 1.0.0 - Infrastructure complète"
git push origin v1.0.0
```

## Récupération des dernières modifications

```bash
cd /opt/keybuzz-installer
git pull origin main
```

## Dépannage

### Erreur : "Permission denied (publickey)"

- Vérifier que la clé SSH est ajoutée dans GitHub
- Tester : `ssh -T git@github.com`

### Erreur : "Repository not found"

- Vérifier que vous avez accès au dépôt `keybuzzio/Infra`
- Vérifier l'URL du dépôt

### Erreur : "Authentication failed"

- Vérifier votre token GitHub ou vos credentials
- Utiliser un token d'accès personnel si nécessaire


