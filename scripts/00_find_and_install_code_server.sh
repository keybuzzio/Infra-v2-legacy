#!/usr/bin/env bash
#
# 00_find_and_install_code_server.sh - Trouver et installer code-server correctement
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Recherche et installation Code-Server"
echo "=============================================================="
echo ""

cd /tmp

# Chercher l'exécutable code-server
echo "[1] Recherche de l'exécutable code-server..."
if [ -d "code-server-4.106.2-linux-amd64" ]; then
    echo "  Recherche dans l'archive extraite..."
    
    # Chercher dans différents emplacements possibles
    CODE_SERVER_BIN=$(find code-server-4.106.2-linux-amd64 -name "code-server" -type f 2>/dev/null | head -1)
    
    if [ -n "${CODE_SERVER_BIN}" ]; then
        echo "  [OK] Trouvé : ${CODE_SERVER_BIN}"
        ls -lh "${CODE_SERVER_BIN}"
    else
        echo "  [ERREUR] Exécutable non trouvé"
        echo "  Contenu de l'archive :"
        find code-server-4.106.2-linux-amd64 -type f -name "*code*" | head -10
        exit 1
    fi
else
    echo "  [ERREUR] Archive non extraite"
    exit 1
fi

# Vérifier si c'est un script ou un binaire
echo ""
echo "[2] Vérification du type de fichier..."
FILE_TYPE=$(head -1 "${CODE_SERVER_BIN}" | cut -c1-2)
if [ "${FILE_TYPE}" = "#!" ]; then
    echo "  [INFO] C'est un script shell"
    head -5 "${CODE_SERVER_BIN}"
else
    echo "  [INFO] C'est un binaire"
fi

# Installer dans /opt/code-server
echo ""
echo "[3] Installation dans /opt/code-server..."

# Option 1: Copier toute l'archive
echo "  Option 1: Copie complète de l'archive..."
mkdir -p /opt/code-server
cp -r code-server-4.106.2-linux-amd64/* /opt/code-server/

# Vérifier où se trouve maintenant l'exécutable
CODE_SERVER_INSTALLED=$(find /opt/code-server -name "code-server" -type f 2>/dev/null | head -1)

if [ -n "${CODE_SERVER_INSTALLED}" ]; then
    echo "  [OK] Exécutable installé : ${CODE_SERVER_INSTALLED}"
    chmod +x "${CODE_SERVER_INSTALLED}"
    
    # Créer un lien symbolique à la racine pour faciliter l'accès
    if [ "${CODE_SERVER_INSTALLED}" != "/opt/code-server/code-server" ]; then
        echo "  Création d'un lien symbolique..."
        ln -sf "${CODE_SERVER_INSTALLED}" /opt/code-server/code-server
    fi
    
    # Tester l'exécution
    echo ""
    echo "[4] Test d'exécution..."
    if /opt/code-server/code-server --version 2>&1; then
        echo "  [OK] Code-server fonctionne"
    else
        echo "  [ERREUR] Code-server ne s'exécute pas"
        echo "  Vérification des dépendances..."
        if command -v ldd >/dev/null 2>&1; then
            ldd "${CODE_SERVER_INSTALLED}" 2>&1 | head -10 || echo "  Pas un binaire ELF"
        fi
        exit 1
    fi
else
    echo "  [ERREUR] Exécutable non trouvé après installation"
    echo "  Contenu de /opt/code-server :"
    ls -la /opt/code-server/ | head -20
    exit 1
fi

# Vérifier/créer la configuration
echo ""
echo "[5] Vérification de la configuration..."
mkdir -p /opt/code-server-data/workspace

if [ ! -f /opt/code-server-data/config.yaml ]; then
    echo "  Création de la configuration..."
    PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
    cat > /opt/code-server-data/config.yaml <<EOF
bind-addr: 0.0.0.0:8080
auth: password
password: ${PASSWORD}
cert: false
EOF
    chmod 600 /opt/code-server-data/config.yaml
    echo "  [OK] Configuration créée"
    echo "  Mot de passe: ${PASSWORD}"
else
    echo "  [OK] Configuration existante"
    PASSWORD=$(grep "^password:" /opt/code-server-data/config.yaml | awk '{print $2}' || echo "")
fi

# Mettre à jour le service systemd
echo ""
echo "[6] Mise à jour du service systemd..."

# Trouver le chemin exact de l'exécutable
FINAL_CODE_SERVER_PATH="/opt/code-server/code-server"
if [ ! -f "${FINAL_CODE_SERVER_PATH}" ]; then
    FINAL_CODE_SERVER_PATH=$(find /opt/code-server -name "code-server" -type f 2>/dev/null | head -1)
fi

cat > /etc/systemd/system/code-server.service <<EOF
[Unit]
Description=Code Server (VS Code Server)
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/code-server-data/workspace
ExecStart=${FINAL_CODE_SERVER_PATH} --config /opt/code-server-data/config.yaml /opt/code-server-data/workspace
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable code-server

echo "  [OK] Service mis à jour"
echo "  Chemin utilisé: ${FINAL_CODE_SERVER_PATH}"

# Redémarrer le service
echo ""
echo "[7] Démarrage du service..."
systemctl restart code-server

sleep 3

if systemctl is-active --quiet code-server; then
    echo "  [OK] Service actif"
else
    echo "  [ERREUR] Service non actif"
    echo "  Logs :"
    journalctl -u code-server --no-pager -n 15
    exit 1
fi

# Afficher les informations
PUBLIC_IP=$(hostname -I | awk '{print $1}' || echo "91.98.128.153")
if [ -z "${PASSWORD}" ]; then
    PASSWORD=$(grep "^password:" /opt/code-server-data/config.yaml | awk '{print $2}' || echo "non trouvé")
fi

echo ""
echo "=============================================================="
echo " [OK] Code-Server installé et opérationnel"
echo "=============================================================="
echo ""
echo "📋 Informations de connexion :"
echo "   URL: http://${PUBLIC_IP}:8080"
echo "   Mot de passe: ${PASSWORD}"
echo ""
echo "🔧 Commandes utiles :"
echo "   systemctl status code-server"
echo "   journalctl -u code-server -f"
echo ""

