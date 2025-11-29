# Guide : Accès aux fichiers avec Code-Server

## 📋 Question : Aurais-je accès à mes fichiers locaux Windows ?

**Réponse courte** : Code-Server fonctionne sur install-01, donc vous aurez accès aux fichiers **sur le serveur**, pas directement aux fichiers Windows locaux. Mais il existe plusieurs solutions pour synchroniser.

---

## ✅ Solution 1 : Cloner le dépôt Git (Recommandé)

### Avantages
- ✅ Synchronisation automatique via Git
- ✅ Historique des modifications
- ✅ Collaboration possible
- ✅ Pas de transfert manuel

### Configuration

1. **Dans Code-Server** (une fois installé) :
   ```bash
   # Ouvrir un terminal dans Code-Server (Ctrl+`)
   cd /opt/code-server-data/workspace
   
   # Cloner le dépôt
   git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
   
   # Ou si le dépôt existe déjà sur install-01
   cd /opt/keybuzz-installer
   git pull
   ```

2. **Travailler normalement** :
   - Éditer les fichiers dans Code-Server
   - Faire `git add`, `git commit`, `git push` depuis Code-Server
   - Faire `git pull` depuis Windows pour récupérer les changements

---

## ✅ Solution 2 : Utiliser SCP/SFTP pour transférer des fichiers

### Depuis Windows vers install-01

```powershell
# Transférer un fichier
scp -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" `
    "chemin\vers\fichier.sh" `
    root@91.98.128.153:/opt/keybuzz-installer/scripts/

# Transférer un dossier
scp -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" `
    -r "chemin\vers\dossier" `
    root@91.98.128.153:/opt/keybuzz-installer/
```

### Depuis install-01 vers Windows

Dans Code-Server, ouvrir un terminal et utiliser :
```bash
# Depuis install-01
scp -i /root/.ssh/keybuzz_infra fichier.sh user@windows-ip:/chemin/
```

---

## ✅ Solution 3 : Utiliser l'extension SFTP de Code-Server

Code-Server supporte les extensions VS Code, y compris l'extension SFTP.

1. **Installer l'extension SFTP** dans Code-Server :
   - Ouvrir Code-Server
   - Aller dans Extensions (Ctrl+Shift+X)
   - Chercher "SFTP" et installer

2. **Configurer la synchronisation** :
   - Créer un fichier `.vscode/sftp.json` dans votre workspace
   - Configurer la connexion vers Windows (si Windows expose un serveur SFTP)

---

## ✅ Solution 4 : Montage réseau (Avancé)

### Option A : Samba/CIFS

Sur install-01, monter un partage Windows :

```bash
# Installer cifs-utils
apt-get install -y cifs-utils

# Créer le point de montage
mkdir -p /mnt/windows-share

# Monter le partage (depuis Windows, partager un dossier)
mount -t cifs //windows-ip/partage /mnt/windows-share \
    -o username=user,password=pass,uid=0,gid=0
```

### Option B : SSHFS (Recommandé si Windows a un serveur SSH)

```bash
# Installer sshfs
apt-get install -y sshfs

# Créer le point de montage
mkdir -p /mnt/windows-files

# Monter via SSHFS
sshfs user@windows-ip:/chemin /mnt/windows-files
```

---

## 🎯 Recommandation pour votre workflow

### Workflow recommandé :

1. **Développement principal sur Code-Server** (install-01)
   - Cloner le dépôt Git sur install-01
   - Travailler directement dans Code-Server
   - Tester les scripts directement sur le serveur

2. **Synchronisation via Git**
   - `git push` depuis Code-Server
   - `git pull` depuis Windows si besoin

3. **Pour les fichiers locaux spécifiques**
   - Utiliser SCP pour transférer ponctuellement
   - Ou utiliser un dossier partagé Git

---

## 📁 Structure recommandée sur install-01

```
/opt/code-server-data/workspace/
├── keybuzz-installer/          # Dépôt Git cloné
│   ├── scripts/
│   ├── docs/
│   └── ...
└── .vscode/                    # Configuration Code-Server
    └── settings.json
```

**OU** utiliser le répertoire existant :

```
/opt/keybuzz-installer/         # Dépôt existant
├── scripts/
├── docs/
└── ...
```

Puis dans Code-Server, ouvrir ce dossier directement.

---

## 🔧 Configuration Code-Server pour ouvrir le bon dossier

Une fois Code-Server installé :

1. **Ouvrir Code-Server** : `http://91.98.128.153:8080`
2. **Ouvrir un dossier** : File → Open Folder
3. **Naviguer vers** : `/opt/keybuzz-installer` (ou `/opt/code-server-data/workspace/keybuzz-installer`)

---

## 💡 Astuce : Lier les deux répertoires

Si vous voulez que Code-Server utilise directement `/opt/keybuzz-installer` :

```bash
# Créer un lien symbolique
ln -s /opt/keybuzz-installer /opt/code-server-data/workspace/keybuzz-installer

# Ou modifier le service systemd pour pointer vers /opt/keybuzz-installer
nano /etc/systemd/system/code-server.service
# Changer WorkingDirectory vers /opt/keybuzz-installer
```

---

## 📝 Résumé

| Besoin | Solution | Complexité |
|--------|----------|------------|
| **Synchronisation automatique** | Git (push/pull) | ⭐ Simple |
| **Transfert ponctuel** | SCP/SFTP | ⭐ Simple |
| **Accès direct aux fichiers Windows** | Montage réseau (Samba/SSHFS) | ⭐⭐⭐ Avancé |
| **Extension VS Code** | Extension SFTP | ⭐⭐ Moyen |

**Recommandation** : Utiliser Git pour la synchronisation principale, et SCP pour les transferts ponctuels.

