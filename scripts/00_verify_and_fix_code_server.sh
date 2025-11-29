#!/usr/bin/env bash
#
# 00_verify_and_fix_code_server.sh - Vérifier et corriger l'installation de code-server
#

set -euo pipefail

CODE_SERVER_DIR="/opt/code-server"
CODE_SERVER_DATA="/opt/code-server-data"

echo "=============================================================="
echo " [KeyBuzz] Vérification et correction Code-Server"
echo "=============================================================="
echo ""

# Vérifier si code-server existe
echo "[1] Vérification de l'installation..."
if [ -f "${CODE_SERVER_DIR}/code-server" ]; then
    if [ -x "${CODE_SERVER_DIR}/code-server" ]; then
        echo "  [OK] Code-server trouvé et exécutable"
        VERSION=$("${CODE_SERVER_DIR}/code-server" --version 2>&1 || echo "erreur")
        echo "  Version: ${VERSION}"
    else
        echo "  [INFO] Code-server trouvé mais non exécutable, correction..."
        chmod +x "${CODE_SERVER_DIR}/code-server"
        echo "  [OK] Permissions corrigées"
    fi
else
    echo "  [ERREUR] Code-server non trouvé dans ${CODE_SERVER_DIR}"
    echo "  Vérification du contenu de /opt/code-server..."
    ls -la "${CODE_SERVER_DIR}/" 2>/dev/null || echo "  Dossier vide ou inexistant"
    
    # Vérifier si l'extraction a été faite dans /tmp
    cd /tmp
    if [ -d "code-server-4.106.2-linux-amd64" ]; then
        echo "  [INFO] Dossier d'extraction trouvé dans /tmp, copie vers /opt/code-server..."
        mkdir -p "${CODE_SERVER_DIR}"
        cp -r code-server-4.106.2-linux-amd64/* "${CODE_SERVER_DIR}/"
        chmod +x "${CODE_SERVER_DIR}/code-server"
        echo "  [OK] Installation complétée"
    else
        echo "  [ERREUR] Aucune installation trouvée"
        echo "  Exécutez d'abord : bash 00_fix_code_server_download.sh"
        exit 1
    fi
fi

# Vérifier la configuration
echo ""
echo "[2] Vérification de la configuration..."
if [ ! -f "${CODE_SERVER_DATA}/config.yaml" ]; then
    echo "  [INFO] Configuration manquante, création..."
    mkdir -p "${CODE_SERVER_DATA}/workspace"
    PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    cat > "${CODE_SERVER_DATA}/config.yaml" <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${PASSWORD}
cert: false
EOF
    chmod 600 "${CODE_SERVER_DATA}/config.yaml"
    echo "  [OK] Configuration créée"
    echo "  Mot de passe: ${PASSWORD}"
else
    echo "  [OK] Configuration existante"
    PASSWORD=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "")
fi

# Vérifier le service systemd
echo ""
echo "[3] Vérification du service systemd..."
if [ -f /etc/systemd/system/code-server.service ]; then
    echo "  [OK] Service systemd existe"
    
    # Vérifier que le chemin dans le service est correct
    if grep -q "${CODE_SERVER_DIR}/code-server" /etc/systemd/system/code-server.service; then
        echo "  [OK] Chemin de l'exécutable correct dans le service"
    else
        echo "  [INFO] Correction du chemin dans le service..."
        # Mettre à jour le service
        sed -i "s|ExecStart=.*|ExecStart=${CODE_SERVER_DIR}/code-server --config ${CODE_SERVER_DATA}/config.yaml ${CODE_SERVER_DATA}/workspace|" \
            /etc/systemd/system/code-server.service
        systemctl daemon-reload
        echo "  [OK] Service mis à jour"
    fi
else
    echo "  [INFO] Service systemd manquant, création..."
    PASSWORD_FOR_SERVICE=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "")
    cat > /etc/systemd/system/code-server.service <<EOF
[Unit]
Description=Code Server (VS Code Server)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${CODE_SERVER_DATA}/workspace
ExecStart=${CODE_SERVER_DIR}/code-server --config ${CODE_SERVER_DATA}/config.yaml ${CODE_SERVER_DATA}/workspace
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable code-server
    echo "  [OK] Service créé et activé"
fi

# Tester l'exécution directe
echo ""
echo "[4] Test d'exécution directe..."
if "${CODE_SERVER_DIR}/code-server" --version >/dev/null 2>&1; then
    echo "  [OK] Code-server s'exécute correctement"
else
    echo "  [ERREUR] Code-server ne s'exécute pas"
    echo "  Vérification des dépendances..."
    ldd "${CODE_SERVER_DIR}/code-server" 2>&1 | head -5 || echo "  Impossible de vérifier les dépendances"
    exit 1
fi

# Redémarrer le service
echo ""
echo "[5] Redémarrage du service..."
systemctl daemon-reload
systemctl restart code-server

sleep 3

if systemctl is-active --quiet code-server; then
    echo "  [OK] Service actif"
else
    echo "  [ERREUR] Service non actif"
    echo "  Logs récents :"
    journalctl -u code-server --no-pager -n 10
    exit 1
fi

# Afficher les informations
PUBLIC_IP=$(hostname -I | awk '{print $1}' || echo "91.98.128.153")
if [ -z "${PASSWORD}" ]; then
    PASSWORD=$(grep "^password:" "${CODE_SERVER_DATA}/config.yaml" | awk '{print $2}' || echo "non trouvé")
fi

echo ""
echo "=============================================================="
echo " [OK] Code-Server opérationnel"
echo "=============================================================="
echo ""
echo "📋 Informations de connexion :"
echo "   URL: http://${PUBLIC_IP}:8080"
echo "   Mot de passe: ${PASSWORD}"
echo ""
echo "🔧 Commandes utiles :"
echo "   systemctl status code-server    # Statut"
echo "   journalctl -u code-server -f    # Logs en temps réel"
echo ""

