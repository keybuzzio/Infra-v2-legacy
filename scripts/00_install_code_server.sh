#!/usr/bin/env bash
#
# 00_install_code_server.sh - Installation de code-server (VS Code Server) sur install-01
#
# Ce script installe code-server pour permettre un accès IDE web complet
# sur install-01, accessible depuis n'importe quel navigateur.
#
# Usage:
#   cd /opt/keybuzz-installer/scripts
#   bash 00_install_code_server.sh
#
# IMPORTANT: Ce script DOIT être exécuté directement sur install-01
# Conforme au Context.txt : tous les scripts s'exécutent depuis install-01
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Installation Code-Server (VS Code Server)"
echo "=============================================================="
echo ""

# Variables
# Détecter automatiquement la dernière version stable
CODE_SERVER_VERSION="${CODE_SERVER_VERSION:-}"
CODE_SERVER_DIR="/opt/code-server"
CODE_SERVER_DATA="/opt/code-server-data"
CODE_SERVER_PORT="8080"
CODE_SERVER_PASSWORD=""

# Si la version n'est pas spécifiée, détecter la dernière version
if [ -z "${CODE_SERVER_VERSION}" ]; then
    echo "[0] Détection de la dernière version de code-server..."
    CODE_SERVER_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "4.23.0")
    if [ -z "${CODE_SERVER_VERSION}" ] || [ "${CODE_SERVER_VERSION}" = "null" ]; then
        CODE_SERVER_VERSION="4.23.0"  # Version de fallback
    fi
    echo "  Version détectée : v${CODE_SERVER_VERSION}"
fi

# Vérifier si code-server est déjà installé
if [ -d "${CODE_SERVER_DIR}" ] && systemctl is-active --quiet code-server 2>/dev/null; then
    echo "[INFO] Code-server est déjà installé et actif"
    echo ""
    echo "📋 Informations de connexion actuelles :"
    if [ -f "${CODE_SERVER_DATA}/config.yaml" ]; then
        CURRENT_PASSWORD=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "non trouvé")
        echo "   URL: http://$(hostname -I | awk '{print $1}'):${CODE_SERVER_PORT}"
        echo "   Mot de passe: ${CURRENT_PASSWORD}"
    fi
    echo ""
    echo "Pour réinstaller, arrêtez d'abord le service :"
    echo "   systemctl stop code-server"
    echo "   rm -rf ${CODE_SERVER_DIR} ${CODE_SERVER_DATA}"
    exit 0
fi

echo "[1] Installation des dépendances..."
apt-get update -qq
apt-get install -y -qq curl wget tar openssl >/dev/null 2>&1

echo "[2] Téléchargement de code-server v${CODE_SERVER_VERSION}..."
cd /tmp
if [ -f "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" ]; then
    echo "  [INFO] Fichier déjà présent, réutilisation..."
else
    echo "  Téléchargement en cours (cela peut prendre quelques minutes)..."
    echo "  URL: https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"
    
    # Essayer d'abord avec curl (plus fiable)
    if curl -L --progress-bar --max-time 300 --fail \
        "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" \
        -o "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz"; then
        echo "  [OK] Téléchargement réussi avec curl"
    else
        echo "  [FAIL] Échec du téléchargement avec curl"
        echo "  Tentative avec wget..."
        if wget --progress=bar:force --timeout=60 --tries=3 \
            "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" 2>&1; then
            echo "  [OK] Téléchargement réussi avec wget"
        else
            echo "  [ERREUR] Impossible de télécharger code-server"
            echo "  Version tentée : v${CODE_SERVER_VERSION}"
            echo "  Vérifiez votre connexion Internet ou la version disponible"
            exit 1
        fi
    fi
fi

# Vérifier que le fichier existe et n'est pas vide
if [ ! -f "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" ] || [ ! -s "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" ]; then
    echo "  [ERREUR] Fichier téléchargé invalide ou vide"
    exit 1
fi

echo "[3] Extraction et installation..."
tar -xzf "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" >/dev/null 2>&1
mkdir -p "${CODE_SERVER_DIR}"
cp -r "code-server-${CODE_SERVER_VERSION}-linux-amd64"/* "${CODE_SERVER_DIR}/"
chmod +x "${CODE_SERVER_DIR}/code-server"

echo "[4] Configuration..."
mkdir -p "${CODE_SERVER_DATA}"
mkdir -p "${CODE_SERVER_DATA}/workspace"

# Générer un mot de passe aléatoire
CODE_SERVER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)

# Créer le fichier de configuration
cat > "${CODE_SERVER_DATA}/config.yaml" <<EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF

chmod 600 "${CODE_SERVER_DATA}/config.yaml"

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
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "[5] Configuration du firewall..."
# Autoriser le port 8080
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${CODE_SERVER_PORT}/tcp >/dev/null 2>&1 || true
fi

echo "[6] Démarrage du service..."
systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

echo "[7] Vérification..."
sleep 5
if systemctl is-active --quiet code-server; then
    echo "  [OK] Code-server actif"
else
    echo "  [FAIL] Code-server non actif"
    echo ""
    echo "Logs du service :"
    journalctl -u code-server --no-pager -n 20
    exit 1
fi

# Obtenir l'IP publique
PUBLIC_IP=$(hostname -I | awk '{print $1}' || echo "91.98.128.153")

echo ""
echo "=============================================================="
echo " [OK] Code-Server installé et démarré avec succès"
echo "=============================================================="
echo ""
echo "📋 Informations de connexion :"
echo "   URL: http://${PUBLIC_IP}:${CODE_SERVER_PORT}"
echo "   Mot de passe: ${CODE_SERVER_PASSWORD}"
echo ""
echo "💾 Le mot de passe est sauvegardé dans :"
echo "   ${CODE_SERVER_DATA}/config.yaml"
echo ""
echo "🔧 Commandes utiles :"
echo "   systemctl status code-server    # Statut du service"
echo "   systemctl restart code-server   # Redémarrer"
echo "   journalctl -u code-server -f    # Voir les logs en temps réel"
echo "   cat ${CODE_SERVER_DATA}/config.yaml  # Voir la config"
echo ""
echo "📁 Workspace : ${CODE_SERVER_DATA}/workspace"
echo "   Vous pouvez y cloner le dépôt KeyBuzz :"
echo "   cd ${CODE_SERVER_DATA}/workspace"
echo "   git clone https://github.com/keybuzzio/Infra.git keybuzz-installer"
echo ""
echo "🔒 Sécurité :"
echo "   - Le service écoute sur toutes les interfaces (0.0.0.0)"
echo "   - Protégé par mot de passe"
echo "   - Pour plus de sécurité, configurez un reverse proxy Nginx avec SSL"
echo ""

