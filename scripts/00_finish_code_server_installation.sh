#!/usr/bin/env bash
#
# 00_finish_code_server_installation.sh - Compléter l'installation de code-server
#
# Ce script vérifie l'état de l'installation et la complète si nécessaire
#

set -euo pipefail

CODE_SERVER_VERSION="4.24.0"
CODE_SERVER_DIR="/opt/code-server"
CODE_SERVER_DATA="/opt/code-server-data"
CODE_SERVER_PORT="8080"

echo "=============================================================="
echo " [KeyBuzz] Complétion installation Code-Server"
echo "=============================================================="
echo ""

# Vérifier l'état actuel
echo "[1] Vérification de l'état actuel..."

if [ -d "${CODE_SERVER_DIR}" ] && [ -f "${CODE_SERVER_DIR}/code-server" ]; then
    echo "  [OK] Code-server extrait dans ${CODE_SERVER_DIR}"
else
    echo "  [INFO] Code-server non extrait, vérification du fichier téléchargé..."
    cd /tmp
    if [ -f "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" ]; then
        echo "  [INFO] Fichier trouvé, extraction..."
        tar -xzf "code-server-${CODE_SERVER_VERSION}-linux-amd64.tar.gz" >/dev/null 2>&1
        mkdir -p "${CODE_SERVER_DIR}"
        cp -r "code-server-${CODE_SERVER_VERSION}-linux-amd64"/* "${CODE_SERVER_DIR}/"
        chmod +x "${CODE_SERVER_DIR}/code-server"
        echo "  [OK] Extraction terminée"
    else
        echo "  [ERREUR] Fichier téléchargé non trouvé dans /tmp"
        echo "  Relancez le script 00_install_code_server.sh"
        exit 1
    fi
fi

echo ""
echo "[2] Configuration..."

# Créer les répertoires
mkdir -p "${CODE_SERVER_DATA}"
mkdir -p "${CODE_SERVER_DATA}/workspace"

# Générer un mot de passe si la config n'existe pas
if [ ! -f "${CODE_SERVER_DATA}/config.yaml" ]; then
    echo "  Génération du mot de passe..."
    CODE_SERVER_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    
    # Créer le fichier de configuration
    cat > "${CODE_SERVER_DATA}/config.yaml" <<EOF
bind-addr: 0.0.0.0:${CODE_SERVER_PORT}
auth: password
password: ${CODE_SERVER_PASSWORD}
cert: false
EOF
    
    chmod 600 "${CODE_SERVER_DATA}/config.yaml"
    echo "  [OK] Configuration créée"
    echo "  Mot de passe: ${CODE_SERVER_PASSWORD}"
else
    echo "  [INFO] Configuration déjà existante"
    CODE_SERVER_PASSWORD=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "")
fi

echo ""
echo "[3] Création du service systemd..."

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

echo "  [OK] Service systemd créé"

echo ""
echo "[4] Configuration du firewall..."

# Autoriser le port 8080
if command -v ufw >/dev/null 2>&1; then
    ufw allow ${CODE_SERVER_PORT}/tcp >/dev/null 2>&1 || true
    echo "  [OK] Port ${CODE_SERVER_PORT} autorisé dans UFW"
fi

echo ""
echo "[5] Démarrage du service..."

systemctl daemon-reload
systemctl enable code-server
systemctl start code-server

echo ""
echo "[6] Vérification..."

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

# Récupérer le mot de passe depuis la config
if [ -z "${CODE_SERVER_PASSWORD}" ]; then
    CODE_SERVER_PASSWORD=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "non trouvé")
fi

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
echo ""

