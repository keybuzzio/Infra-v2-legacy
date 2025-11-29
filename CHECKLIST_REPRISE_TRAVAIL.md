# ✅ Checklist : Reprendre le travail après cette conversation

## 🎯 Objectif

Cette checklist vous permet de reprendre le travail rapidement dans une nouvelle conversation.

---

## 📋 Étape 1 : Vérifier l'état actuel

### Code-Server sur install-01

```bash
# Se connecter à install-01
ssh root@91.98.128.153

# Vérifier le service
systemctl status code-server

# Si actif, récupérer le mot de passe
cat /opt/code-server-data/config.yaml | grep "^password:"

# Tester l'accès
# Ouvrir dans le navigateur : http://91.98.128.153:8080
```

**Résultat attendu** :
- ✅ Service `code-server` actif
- ✅ Accès web fonctionnel
- ✅ Mot de passe récupérable

**Si problème** :
- Voir : `Infra/scripts/00_verify_and_fix_code_server.sh`

---

## 📋 Étape 2 : Vérifier les fichiers

### Sur Windows

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio"

# Vérifier les guides créés
ls Infra/GUIDE_*.md
ls Infra/SOLUTION_*.md
ls Infra/RECAP_*.md

# Vérifier les scripts
ls Infra/scripts/00_*code*.sh
ls Infra/scripts/setup_git*.ps1

# Vérifier .gitignore
Test-Path .gitignore
```

**Résultat attendu** :
- ✅ Tous les guides présents
- ✅ Tous les scripts présents
- ✅ `.gitignore` présent

### Sur install-01

```bash
# Vérifier les scripts
ls -la /opt/keybuzz-installer/scripts/00_*code*.sh

# Vérifier Code-Server
ls -la /opt/code-server/bin/code-server
ls -la /opt/code-server-data/config.yaml
```

**Résultat attendu** :
- ✅ Scripts présents
- ✅ Code-Server installé
- ✅ Configuration présente

---

## 📋 Étape 3 : Synchronisation GitHub (Si pas encore fait)

### Sur Windows

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio"

# Vérifier si Git est initialisé
git status

# Si pas initialisé, utiliser le script
.\Infra\scripts\setup_git_repository.ps1

# OU manuellement
git init
git remote add origin https://github.com/keybuzzio/Infra.git
git add Infra/
git add .gitignore
git commit -m "Initial commit: Infrastructure KeyBuzz"
git push -u origin main
```

**Résultat attendu** :
- ✅ Dépôt Git initialisé
- ✅ Remote GitHub configuré
- ✅ Fichiers poussés sur GitHub

### Sur install-01

```bash
cd /opt

# Si le dossier existe déjà, le sauvegarder
if [ -d "keybuzz-installer" ]; then
    mv keybuzz-installer keybuzz-installer.backup.$(date +%Y%m%d_%H%M%S)
fi

# Cloner le dépôt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer

cd keybuzz-installer
ls -la
```

**Résultat attendu** :
- ✅ Dépôt cloné
- ✅ Tous les fichiers présents

---

## 📋 Étape 4 : Configuration Cursor Remote SSH (Optionnel mais recommandé)

### Dans Cursor (Windows)

1. **Installer l'extension** :
   - Extensions (Ctrl+Shift+X)
   - Chercher "Remote - SSH"
   - Installer

2. **Configurer SSH** :
   - Créer/modifier `C:\Users\ludov\.ssh\config` :
   ```
   Host install-01
       HostName 91.98.128.153
       User root
       IdentityFile C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra
       StrictHostKeyChecking accept-new
   ```

3. **Se connecter** :
   - `F1` → "Remote-SSH: Connect to Host"
   - Sélectionner "install-01"
   - Entrer la passphrase SSH

4. **Ouvrir le dossier** :
   - File → Open Folder
   - `/opt/keybuzz-installer`

**Résultat attendu** :
- ✅ Cursor connecté à install-01
- ✅ IA Cursor disponible
- ✅ Accès aux fichiers

---

## 📋 Étape 5 : Vérifier l'état de l'infrastructure

### Modules installés

Consulter les rapports d'installation :
- `Infra/scripts/RAPPORT_TECHNIQUE_COMPLET_KEYBUZZ_INFRASTRUCTURE.md`
- `Infra/scripts/POINT_TECHNIQUE_COMPLET_ETAT_INFRASTRUCTURE.md`

### Dernier module complété

D'après la conversation :
- ✅ Modules 1-9 validés
- ⏳ Module 10 (Load Balancers Hetzner) : En attente
- ⏳ Tests de failover : En attente

---

## 📋 Étape 6 : Reprendre le travail

### Options

1. **Continuer l'installation infrastructure** :
   - Module 10 : Load Balancers Hetzner
   - Tests de failover complets

2. **Corriger les problèmes restants** :
   - Vérifier haproxy-01 (disaster recovery)
   - Bootstraper Patroni si nécessaire
   - Vérifier Redis Sentinel

3. **Nouveau développement** :
   - Utiliser Code-Server ou Cursor Remote SSH
   - Synchroniser via Git

---

## 🔍 Commandes de diagnostic rapide

### Vérifier Code-Server

```bash
# Statut
systemctl status code-server

# Logs
journalctl -u code-server -n 50

# Test d'accès
curl -I http://localhost:8080
```

### Vérifier Git

```bash
# Sur Windows
cd "C:\Users\ludov\Mon Drive\keybuzzio"
git status
git remote -v

# Sur install-01
cd /opt/keybuzz-installer
git status
git remote -v
```

### Vérifier SSH

```bash
# Depuis Windows
ssh root@91.98.128.153 "echo 'SSH OK'"
```

---

## 📚 Fichiers de référence

### Guides principaux

1. **`Infra/RECAP_CONVERSATION_CODE_SERVER_GITHUB.md`**
   - Récapitulatif complet de cette conversation

2. **`Infra/GUIDE_SYNCHRONISATION_GITHUB.md`**
   - Guide complet synchronisation Git

3. **`Infra/GUIDE_IA_SUR_INSTALL01.md`**
   - Guide utilisation IA sur install-01

4. **`Infra/SOLUTION_AUTHENTIFICATION_AUTOMATIQUE.md`**
   - Solutions authentification automatique

5. **`Infra/GUIDE_ACCES_FICHIERS_CODE_SERVER.md`**
   - Guide accès fichiers Code-Server

### Scripts utiles

- `Infra/scripts/00_verify_and_fix_code_server.sh` - Vérifier Code-Server
- `Infra/scripts/setup_git_repository.ps1` - Configurer Git
- `Infra/scripts/00_find_and_install_code_server.sh` - Réinstaller Code-Server

---

## ✅ Checklist complète

### Avant de reprendre

- [ ] Code-Server actif sur install-01
- [ ] Accès Code-Server fonctionnel (navigateur)
- [ ] Tous les guides présents sur Windows
- [ ] Tous les scripts présents sur install-01
- [ ] Git initialisé (Windows et install-01)
- [ ] Dépôt GitHub configuré
- [ ] Cursor Remote SSH configuré (optionnel)

### Pour reprendre le travail

- [ ] Lire `RECAP_CONVERSATION_CODE_SERVER_GITHUB.md`
- [ ] Vérifier l'état avec cette checklist
- [ ] Consulter les guides selon le besoin
- [ ] Reprendre depuis le dernier module complété

---

## 🚨 Problèmes courants et solutions

### Code-Server ne démarre pas

```bash
# Vérifier et corriger
cd /opt/keybuzz-installer/scripts
bash 00_verify_and_fix_code_server.sh
```

### Git non synchronisé

```bash
# Sur install-01
cd /opt/keybuzz-installer
git pull origin main

# Sur Windows
cd "C:\Users\ludov\Mon Drive\keybuzzio"
git pull origin main
```

### Cursor Remote SSH ne se connecte pas

- Vérifier la config SSH : `C:\Users\ludov\.ssh\config`
- Tester SSH manuellement : `ssh root@91.98.128.153`
- Vérifier le chemin de la clé SSH

---

**Fin de la checklist**








