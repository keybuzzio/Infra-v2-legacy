# Solutions d'authentification automatique pour install-01

## 🎯 Objectif

Permettre une connexion SSH automatique et fiable vers `install-01` sans intervention manuelle, accessible depuis n'importe quel ordinateur.

---

## ✅ Solution 1 : SSH Agent avec démarrage automatique (Recommandé - Simple)

### Avantages
- ✅ Simple à configurer
- ✅ Sécurisé (passphrase stockée en mémoire)
- ✅ Fonctionne avec tous les outils SSH
- ✅ Compatible Windows/Linux/Mac

### Configuration Windows

#### Étape 1 : Configurer ssh-agent pour démarrer automatiquement

```powershell
# Démarrer le service ssh-agent
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

#### Étape 2 : Créer un script PowerShell pour charger automatiquement la clé

Créer le fichier : `C:\Users\ludov\Mon Drive\keybuzzio\Infra\scripts\setup_ssh_agent.ps1`

```powershell
# setup_ssh_agent.ps1 - Configuration automatique de ssh-agent
$SSH_KEY = "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra"
$PASSPHRASE_FILE = "C:\Users\ludov\Mon Drive\keybuzzio\SSH\passphrase.txt"

# Vérifier si ssh-agent est actif
$agent = Get-Service ssh-agent -ErrorAction SilentlyContinue
if ($agent -and $agent.Status -ne 'Running') {
    Start-Service ssh-agent
}

# Lire la passphrase
$passphrase = Get-Content $PASSPHRASE_FILE -Raw | ForEach-Object { $_.Trim() }

# Charger la clé dans ssh-agent
$securePassphrase = ConvertTo-SecureString $passphrase -AsPlainText -Force
$keyContent = Get-Content $SSH_KEY -Raw

# Utiliser ssh-add avec la passphrase
$process = Start-Process -FilePath "ssh-add" -ArgumentList "`"$SSH_KEY`"" -NoNewWindow -Wait -PassThru -RedirectStandardInput (New-TemporaryFile).FullName

# Méthode alternative : utiliser expect ou un script bash
Write-Host "Pour charger la clé automatiquement, exécutez :" -ForegroundColor Yellow
Write-Host "ssh-add `"$SSH_KEY`"" -ForegroundColor Cyan
Write-Host "Entrez la passphrase une fois, elle sera mémorisée jusqu'au redémarrage"
```

#### Étape 3 : Créer un script bash (Git Bash/WSL) pour automatiser complètement

Créer le fichier : `Infra/scripts/setup_ssh_agent_auto.sh`

```bash
#!/usr/bin/env bash
# setup_ssh_agent_auto.sh - Configuration automatique de ssh-agent avec passphrase

SSH_KEY="$HOME/.ssh/keybuzz_infra"
PASSPHRASE_FILE="C:/Users/ludov/Mon Drive/keybuzzio/SSH/passphrase.txt"

# Démarrer ssh-agent si nécessaire
if [ -z "$SSH_AUTH_SOCK" ]; then
    eval "$(ssh-agent -s)"
fi

# Lire la passphrase
PASSPHRASE=$(cat "$PASSPHRASE_FILE" | tr -d '\r\n')

# Charger la clé avec expect ou sshpass
if command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$PASSPHRASE" ssh-add "$SSH_KEY" <<< "$PASSPHRASE"
else
    echo "Installation de sshpass requise :"
    echo "  WSL: sudo apt-get install sshpass"
    echo "  Git Bash: pas disponible, utilisez expect ou méthode manuelle"
    ssh-add "$SSH_KEY"
fi
```

#### Étape 4 : Tester

```powershell
# Depuis PowerShell
ssh root@91.98.128.153 "hostname && echo 'Connexion OK'"
```

---

## ✅ Solution 2 : Clé SSH dédiée sans passphrase (Simple mais moins sécurisé)

### Avantages
- ✅ Très simple
- ✅ Aucune intervention nécessaire
- ⚠️ Moins sécurisé (clé sans passphrase)

### Configuration

#### Étape 1 : Générer une clé dédiée pour l'automatisation

```bash
# Dans Git Bash ou WSL
cd ~/.ssh
ssh-keygen -t ed25519 -f keybuzz_auto -N "" -C "keybuzz-automation-no-passphrase"
```

#### Étape 2 : Copier la clé publique sur install-01

```bash
# Afficher la clé publique
cat ~/.ssh/keybuzz_auto.pub

# Se connecter manuellement à install-01 (une fois)
ssh root@91.98.128.153

# Sur install-01, ajouter la clé
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "COLLER_LA_CLE_PUBLIQUE_ICI" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

#### Étape 3 : Configurer SSH config

Créer/modifier `C:\Users\ludov\.ssh\config` :

```
Host install-01
    HostName 91.98.128.153
    User root
    IdentityFile C:\Users\ludov\.ssh\keybuzz_auto
    StrictHostKeyChecking accept-new
```

#### Étape 4 : Tester

```powershell
ssh install-01 "hostname && echo 'Connexion OK'"
```

---

## 🚀 Solution 3 : Code-Server (VS Code Server) - LA PLUS ROBUSTE

### Avantages
- ✅ **IDE web complet** accessible depuis n'importe où
- ✅ **Aucun problème d'authentification SSH** (accès via navigateur)
- ✅ **Interface graphique** pour éditer les fichiers
- ✅ **Terminal intégré** dans le navigateur
- ✅ **Extensions VS Code** disponibles
- ✅ **Multi-utilisateurs** possible
- ✅ **Persistant** (fonctionne même après redémarrage)

### Installation sur install-01

#### Étape 1 : Script d'installation automatique

Créer le fichier : `Infra/scripts/00_install_code_server.sh`

```bash
#!/usr/bin/env bash
# 00_install_code_server.sh - Installation de code-server sur install-01
# Usage: Exécuter directement sur install-01

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Installation Code-Server (VS Code Server)"
echo "=============================================================="
echo ""

# Variables
CODE_SERVER_VERSION="4.24.0"
CODE_SERVER_DIR="/opt/code-server"
CODE_SERVER_DATA="/opt/code-server-data"
CODE_SERVER_PORT="8080"
CODE_SERVER_PASSWORD=""

# Générer un mot de passe aléatoire si non fourni
if [ -z "$CODE_SERVER_PASSWORD" ]; then
    CODE_SERVER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
fi

echo "[1] Téléchargement de code-server..."
cd /tmp
wget -q "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
tar -xzf "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
mv "code-server-${CODE_SERVER_VERSION}-linux-amd64" "${CODE_SERVER_DIR}"

echo "[2] Configuration..."
mkdir -p "${CODE_SERVER_DATA}"
mkdir -p "${CODE_SERVER_DATA}/workspace"

# Créer le fichier de configuration
cat > "${CODE_SERVER_DATA}/config.yaml" <<EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF

# Créer le service systemd
cat > /etc/systemd/system/code-server.service <<EOF
[Unit]
Description=Code Server (VS Code Server)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${CODE_SERVER_DATA}/workspace
Environment="PASSWORD=${CODE_SERVER_PASSWORD}"
ExecStart=${CODE_SERVER_DIR}/code-server --config ${CODE_SERVER_DATA}/config.yaml ${CODE_SERVER_DATA}/workspace
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "[3] Démarrage du service..."
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

echo "[4] Vérification..."
sleep 3
if systemctl is-active --quiet code-server; then
    echo "  [OK] Code-server actif"
else
    echo "  [FAIL] Code-server non actif"
    systemctl status code-server
    exit 1
fi

echo ""
echo "=============================================================="
echo " [OK] Code-Server installé et démarré"
echo "=============================================================="
echo ""
echo "📋 Informations de connexion :"
echo "   URL: http://91.98.128.153:${CODE_SERVER_PORT}"
echo "   Mot de passe: ${CODE_SERVER_PASSWORD}"
echo ""
echo "💾 Le mot de passe est sauvegardé dans :"
echo "   ${CODE_SERVER_DATA}/config.yaml"
echo ""
echo "🔧 Commandes utiles :"
echo "   systemctl status code-server    # Statut"
echo "   systemctl restart code-server   # Redémarrer"
echo "   journalctl -u code-server -f    # Logs"
echo ""
echo "📁 Workspace : ${CODE_SERVER_DATA}/workspace"
echo "   Vous pouvez y cloner le dépôt KeyBuzz :"
echo "   cd ${CODE_SERVER_DATA}/workspace"
echo "   git clone https://github.com/keybuzzio/Infra.git keybuzz-installer"
echo ""
```

#### Étape 2 : Exécuter l'installation

**Option A : Depuis Windows (avec connexion manuelle une fois)**

```powershell
# Se connecter manuellement à install-01
ssh root@91.98.128.153

# Sur install-01, exécuter :
cd /opt/keybuzz-installer/scripts
bash 00_install_code_server.sh
```

**Option B : Transférer le script et l'exécuter**

```powershell
# Transférer le script
scp -i "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra" `
    "Infra\scripts\00_install_code_server.sh" `
    root@91.98.128.153:/tmp/

# Se connecter et exécuter
ssh root@91.98.128.153 "bash /tmp/00_install_code_server.sh"
```

#### Étape 3 : Accéder à Code-Server

1. **Ouvrir le navigateur** : `http://91.98.128.153:8080`
2. **Entrer le mot de passe** affiché dans le terminal
3. **Vous avez maintenant un IDE complet** sur install-01 !

#### Étape 4 : Configurer le workspace

Dans Code-Server :
1. Ouvrir un terminal intégré (Ctrl+`)
2. Cloner le dépôt :
   ```bash
   cd /opt/code-server-data/workspace
   git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
   ```
3. Ouvrir le dossier `keybuzz-installer`

#### Étape 5 : Sécuriser l'accès (Optionnel mais recommandé)

**A. Avec Nginx reverse proxy + SSL**

```bash
# Sur install-01
apt-get install -y nginx certbot python3-certbot-nginx

# Configurer Nginx
cat > /etc/nginx/sites-available/code-server <<EOF
server {
    listen 80;
    server_name code.keybuzz.io;  # Ou votre domaine

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -s /etc/nginx/sites-available/code-server /etc/nginx/sites-enabled/
nginx -t
systemctl reload nginx

# Obtenir un certificat SSL
certbot --nginx -d code.keybuzz.io
```

**B. Avec firewall (UFW)**

```bash
# Autoriser uniquement votre IP
ufw allow from VOTRE_IP to any port 8080
```

---

## 📊 Comparaison des solutions

| Critère | Solution 1 (ssh-agent) | Solution 2 (clé sans pass) | Solution 3 (code-server) |
|---------|------------------------|---------------------------|-------------------------|
| **Simplicité** | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐ |
| **Sécurité** | ⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐⭐ |
| **Robustesse** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Accessibilité** | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **IDE intégré** | ❌ | ❌ | ✅ |
| **Multi-ordinateurs** | ⚠️ (config requise) | ⚠️ (config requise) | ✅ (navigateur) |
| **Persistance** | ⚠️ (redémarrage) | ✅ | ✅ |

---

## 🎯 Recommandation

**Pour votre cas d'usage, je recommande la Solution 3 (Code-Server)** car :

1. ✅ **Aucun problème d'authentification SSH** - accès via navigateur
2. ✅ **IDE complet** - comme Cursor/VS Code directement sur le serveur
3. ✅ **Accessible depuis n'importe où** - juste un navigateur
4. ✅ **Persistant** - fonctionne même après redémarrage
5. ✅ **Terminal intégré** - exécuter tous les scripts directement
6. ✅ **Multi-utilisateurs** - vous pouvez partager l'accès si besoin

---

## 🚀 Prochaines étapes

1. **Choisir une solution** (recommandé : Solution 3)
2. **Suivre les instructions** de la solution choisie
3. **Tester la connexion**
4. **Configurer le workspace** avec vos scripts KeyBuzz

---

## 📝 Notes importantes

- **Solution 1** : Nécessite de recharger la clé après chaque redémarrage Windows
- **Solution 2** : Moins sécurisé, mais très pratique pour l'automatisation
- **Solution 3** : La plus robuste, mais nécessite un port ouvert (8080 par défaut)

---

## 🔧 Dépannage

### Solution 1 : ssh-agent ne démarre pas
```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
```

### Solution 2 : Clé refusée
```bash
# Vérifier les permissions sur install-01
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

### Solution 3 : Code-server inaccessible
```bash
# Vérifier le service
systemctl status code-server

# Vérifier le firewall
ufw status
ufw allow 8080

# Vérifier les logs
journalctl -u code-server -f
```

