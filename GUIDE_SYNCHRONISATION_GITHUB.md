# Guide complet : Synchronisation GitHub entre Windows et install-01

## 🎯 Objectif

Synchroniser tous vos fichiers d'infrastructure entre votre ordinateur Windows et le serveur `install-01` via GitHub, pour pouvoir travailler depuis install-01 directement.

---

## 📁 Structure du dépôt GitHub

### Dépôt recommandé : `keybuzzio/Infra`

**Structure à envoyer sur GitHub :**

```
keybuzzio/Infra/
├── Infra/                    # ✅ Dossier principal (TOUT envoyer)
│   ├── docs/                 # ✅ Documentation
│   ├── scripts/              # ✅ Tous les scripts
│   ├── servers.tsv           # ✅ Inventaire serveurs
│   ├── *.md                  # ✅ Tous les guides
│   └── ...
├── Context/                  # ⚠️ À décider (contient Context.txt)
│   └── Context.txt           # ⚠️ Fichier volumineux (13k lignes)
└── .gitignore                # ✅ Fichier d'exclusion
```

### ⚠️ Fichiers à NE PAS envoyer (sécurité)

- `SSH/` - Clés SSH privées et passphrases (NE JAMAIS envoyer)
- `keybuzz-installer/credentials/` - Fichiers de credentials
- `keybuzz-installer/logs/` - Logs (trop volumineux)
- `*.env` - Fichiers d'environnement avec secrets
- `*.key`, `*.pem` - Clés privées

---

## 📝 Étape 1 : Créer le fichier .gitignore

Créez un fichier `.gitignore` à la racine de votre projet :

```bash
# Fichiers sensibles - NE JAMAIS COMMITER
SSH/
**/credentials/
**/*.env
**/*.key
**/*.pem
**/passphrase.txt
**/id_rsa
**/id_ed25519
**/*.ppk

# Logs
**/logs/
*.log

# Archives
*.tar.gz
*.zip
*.tar

# Fichiers temporaires
**/tmp/
**/temp/
**/.DS_Store
**/Thumbs.db

# Anciens dossiers (optionnel)
keybuzz-installer/backups/
keybuzz-installer/wgkeys/

# Fichiers système
**/.vscode/
**/.idea/
**/*.swp
**/*.swo
**/*~
```

---

## 🚀 Étape 2 : Initialiser le dépôt Git sur Windows

### 2.1. Naviguer vers le dossier Infra

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio"
```

### 2.2. Initialiser Git (si pas déjà fait)

```powershell
# Vérifier si Git est déjà initialisé
if (Test-Path ".git") {
    Write-Host "Git déjà initialisé"
} else {
    git init
    Write-Host "Git initialisé"
}
```

### 2.3. Créer le fichier .gitignore

Créez le fichier `.gitignore` à la racine avec le contenu ci-dessus.

### 2.4. Ajouter le remote GitHub

```powershell
# Vérifier si le remote existe
git remote -v

# Si le remote n'existe pas, l'ajouter
git remote add origin https://github.com/keybuzzio/Infra.git

# OU si vous utilisez SSH
git remote add origin git@github.com:keybuzzio/Infra.git
```

### 2.5. Ajouter tous les fichiers (sauf ceux dans .gitignore)

```powershell
# Ajouter tous les fichiers
git add Infra/
git add Context/  # Si vous voulez inclure Context.txt
git add .gitignore

# Vérifier ce qui sera commité
git status
```

### 2.6. Premier commit

```powershell
git commit -m "Initial commit: Infrastructure KeyBuzz complète

- Scripts d'installation et configuration
- Documentation complète
- Inventaire serveurs (servers.tsv)
- Guides d'installation"
```

### 2.7. Créer la branche main (si nécessaire)

```powershell
git branch -M main
```

### 2.8. Push vers GitHub

```powershell
# Push vers GitHub
git push -u origin main
```

**Note** : Vous devrez vous authentifier :
- **Token GitHub** (recommandé) : Créez un Personal Access Token sur GitHub
- **SSH** : Si vous avez configuré une clé SSH GitHub

---

## 📥 Étape 3 : Cloner sur install-01

### 3.1. Se connecter à install-01

```bash
# Depuis Windows (PowerShell)
ssh root@91.98.128.153

# OU depuis Code-Server (navigateur)
# http://91.98.128.153:8080
```

### 3.2. Installer Git (si nécessaire)

```bash
apt-get update
apt-get install -y git
```

### 3.3. Configurer Git

```bash
git config --global user.name "KeyBuzz Infrastructure"
git config --global user.email "infra@keybuzz.io"
```

### 3.4. Cloner le dépôt

```bash
cd /opt

# Si le dossier existe déjà, le sauvegarder
if [ -d "keybuzz-installer" ]; then
    mv keybuzz-installer keybuzz-installer.backup.$(date +%Y%m%d_%H%M%S)
fi

# Cloner le dépôt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer

# OU avec SSH (si configuré)
# git clone git@github.com:keybuzzio/Infra.git keybuzz-installer

cd keybuzz-installer
```

### 3.5. Vérifier la structure

```bash
ls -la
# Vous devriez voir : docs/, scripts/, servers.tsv, README.md, etc.

# Vérifier que les scripts sont présents
ls -la scripts/
```

---

## 🔄 Étape 4 : Workflow de synchronisation

### 4.1. Depuis Windows : Modifier et pousser

```powershell
# 1. Modifier vos fichiers dans "C:\Users\ludov\Mon Drive\keybuzzio\Infra\"

# 2. Vérifier les changements
cd "C:\Users\ludov\Mon Drive\keybuzzio"
git status

# 3. Ajouter les fichiers modifiés
git add Infra/scripts/00_nouveau_script.sh
git add Infra/docs/nouveau_guide.md

# 4. Commit
git commit -m "[Module X] Description des changements

- Détail 1
- Détail 2"

# 5. Push vers GitHub
git push origin main
```

### 4.2. Sur install-01 : Récupérer les changements

```bash
# Dans Code-Server ou SSH
cd /opt/keybuzz-installer

# Récupérer les derniers changements
git pull origin main

# Vérifier les changements
git log --oneline -5
```

### 4.3. Depuis install-01 : Modifier et pousser

```bash
# 1. Modifier un fichier (dans Code-Server ou SSH)
cd /opt/keybuzz-installer
nano scripts/00_nouveau_script.sh

# 2. Commit
git add scripts/00_nouveau_script.sh
git commit -m "[Module X] Modification depuis install-01

- Correction bug
- Amélioration performance"

# 3. Push vers GitHub
git push origin main
```

### 4.4. Depuis Windows : Récupérer les changements d'install-01

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio"
git pull origin main
```

---

## 🔐 Étape 5 : Authentification GitHub

### Option 1 : Personal Access Token (Recommandé)

1. **Créer un token sur GitHub** :
   - GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
   - Generate new token (classic)
   - Permissions : `repo` (accès complet)
   - Copier le token

2. **Utiliser le token** :
   ```bash
   # Lors du push, utiliser le token comme mot de passe
   # Username : votre nom d'utilisateur GitHub
   # Password : le token
   ```

3. **Configurer Git Credential Helper** (Windows) :
   ```powershell
   git config --global credential.helper wincred
   ```

### Option 2 : Clé SSH GitHub

1. **Générer une clé SSH sur install-01** :
   ```bash
   ssh-keygen -t ed25519 -C "infra@keybuzz.io"
   cat ~/.ssh/id_ed25519.pub
   ```

2. **Ajouter la clé sur GitHub** :
   - GitHub → Settings → SSH and GPG keys → New SSH key
   - Coller le contenu de `~/.ssh/id_ed25519.pub`

3. **Utiliser SSH pour cloner** :
   ```bash
   git clone git@github.com:keybuzzio/Infra.git keybuzz-installer
   ```

---

## 📋 Checklist de synchronisation

### ✅ Avant de pousser sur GitHub

- [ ] Vérifier que `.gitignore` exclut les fichiers sensibles
- [ ] Vérifier qu'aucun fichier `.env`, `.key`, ou `passphrase.txt` n'est inclus
- [ ] Tester que les scripts fonctionnent localement
- [ ] Vérifier `git status` pour voir ce qui sera commité

### ✅ Après avoir cloné sur install-01

- [ ] Vérifier que tous les scripts sont présents
- [ ] Vérifier que `servers.tsv` est présent
- [ ] Rendre les scripts exécutables : `chmod +x scripts/**/*.sh`
- [ ] Tester un script simple

---

## 🎯 Workflow recommandé

### Scénario 1 : Développement sur Windows

1. Modifier les fichiers sur Windows
2. Tester localement (si possible)
3. Commit + Push vers GitHub
4. Sur install-01 : `git pull`
5. Tester sur install-01

### Scénario 2 : Développement sur install-01 (Code-Server)

1. Ouvrir Code-Server : `http://91.98.128.153:8080`
2. Ouvrir le dossier : `/opt/keybuzz-installer`
3. Modifier les fichiers directement
4. Tester directement sur install-01
5. Commit + Push depuis install-01
6. Sur Windows : `git pull` pour récupérer

### Scénario 3 : Collaboration

1. Avant de modifier : `git pull` pour récupérer les derniers changements
2. Modifier
3. Commit + Push
4. Les autres : `git pull` pour récupérer

---

## 🔧 Commandes Git utiles

### Voir l'état

```bash
git status                    # État des fichiers
git log --oneline -10        # Derniers commits
git diff                      # Différences non commitées
```

### Gérer les branches

```bash
git branch                    # Lister les branches
git checkout -b feature/xxx  # Créer une nouvelle branche
git checkout main            # Revenir sur main
```

### Annuler des changements

```bash
git checkout -- fichier.sh    # Annuler modifications d'un fichier
git reset HEAD fichier.sh     # Désindexer un fichier
git reset --hard HEAD         # ⚠️ Annuler TOUS les changements (dangereux)
```

---

## 📝 Exemples de messages de commit

```
[Module 2] Base OS - Correction UFW
[Module 3] PostgreSQL HA - Script Patroni
[Module 6] MinIO - Fix déploiement distribué
[Module 9] K3s - Configuration HA
[Scripts] Ajout script disaster recovery haproxy-01
[Docs] Mise à jour guide installation complète
[Fix] Correction encodage scripts
```

---

## 🚨 Problèmes courants et solutions

### Erreur : "Permission denied (publickey)"

**Solution** : Configurer une clé SSH GitHub ou utiliser un token

### Erreur : "Updates were rejected"

**Solution** : 
```bash
git pull origin main  # Récupérer d'abord
git push origin main  # Puis pousser
```

### Fichiers sensibles commités par erreur

**Solution** :
```bash
# Supprimer du dépôt (mais garder localement)
git rm --cached fichier_sensible.env
git commit -m "Remove sensitive file"
git push

# Ajouter au .gitignore
echo "fichier_sensible.env" >> .gitignore
```

---

## ✅ Résumé

1. **Créer `.gitignore`** pour exclure les fichiers sensibles
2. **Initialiser Git** sur Windows et pousser vers GitHub
3. **Cloner sur install-01** : `/opt/keybuzz-installer`
4. **Travailler depuis install-01** (Code-Server ou SSH)
5. **Synchroniser** : `git pull` / `git push` régulièrement

**Avantages** :
- ✅ Synchronisation automatique
- ✅ Historique des modifications
- ✅ Travail depuis n'importe où
- ✅ Backup automatique sur GitHub








