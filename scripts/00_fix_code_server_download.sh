#!/usr/bin/env bash
#
# 00_fix_code_server_download.sh - Corriger le téléchargement de code-server
#
# Ce script vérifie le fichier téléchargé et télécharge la bonne version
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Correction téléchargement Code-Server"
echo "=============================================================="
echo ""

cd /tmp

# Vérifier le fichier actuel
echo "[1] Vérification du fichier téléchargé..."
if [ -f "code-server-4.24.0-linux-amd64.tar.gz" ]; then
    FILE_TYPE=$(file code-server-4.24.0-linux-amd64.tar.gz | grep -o "gzip\|HTML\|text" || echo "unknown")
    FILE_SIZE=$(stat -c%s code-server-4.24.0-linux-amd64.tar.gz 2>/dev/null || echo "0")
    
    echo "  Type: ${FILE_TYPE}"
    echo "  Taille: ${FILE_SIZE} bytes"
    
    if [[ "${FILE_TYPE}" == *"HTML"* ]] || [ "${FILE_SIZE}" -lt 1000000 ]; then
        echo "  [INFO] Fichier invalide, suppression..."
        rm -f code-server-4.24.0-linux-amd64.tar.gz
    fi
fi

# Détecter la dernière version disponible
echo ""
echo "[2] Détection de la dernière version..."
LATEST_VERSION=$(curl -s https://api.github.com/repos/coder/code-server/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' || echo "")

if [ -z "${LATEST_VERSION}" ] || [ "${LATEST_VERSION}" = "null" ]; then
    # Versions de fallback testées
    VERSIONS=("4.23.0" "4.22.1" "4.22.0" "4.21.1")
    LATEST_VERSION=""
    
    for v in "${VERSIONS[@]}"; do
        echo "  Test version v${v}..."
        if curl -s --head "https://github.com/coder/code-server/releases/download/v${v}/code-server-${v}-linux-amd64.tar.gz" | grep -q "200 OK"; then
            LATEST_VERSION="${v}"
            echo "  [OK] Version v${v} disponible"
            break
        fi
    done
fi

if [ -z "${LATEST_VERSION}" ]; then
    echo "  [ERREUR] Impossible de détecter une version"
    echo "  Utilisation de la version 4.23.0 par défaut"
    LATEST_VERSION="4.23.0"
else
    echo "  [OK] Version détectée : v${LATEST_VERSION}"
fi

# Télécharger la bonne version
echo ""
echo "[3] Téléchargement de code-server v${LATEST_VERSION}..."
DOWNLOAD_URL="https://github.com/coder/code-server/releases/download/v${LATEST_VERSION}/code-server-${LATEST_VERSION}-linux-amd64.tar.gz"
OUTPUT_FILE="code-server-${LATEST_VERSION}-linux-amd64.tar.gz"

# Supprimer l'ancien fichier s'il existe
rm -f "${OUTPUT_FILE}"

echo "  URL: ${DOWNLOAD_URL}"
echo "  Téléchargement en cours..."

if curl -L --progress-bar --max-time 300 --fail "${DOWNLOAD_URL}" -o "${OUTPUT_FILE}"; then
    # Vérifier que le fichier existe et a une taille raisonnable (> 1MB)
    FILE_SIZE=$(stat -c%s "${OUTPUT_FILE}" 2>/dev/null || echo "0")
    if [ "${FILE_SIZE}" -gt 1000000 ]; then
        echo "  [OK] Téléchargement réussi (${FILE_SIZE} bytes)"
    else
        echo "  [ERREUR] Le fichier téléchargé est trop petit (${FILE_SIZE} bytes)"
        echo "  Vérification du type de fichier..."
        if command -v file >/dev/null 2>&1; then
            file "${OUTPUT_FILE}"
        else
            echo "  Premiers bytes (hex) :"
            hexdump -C "${OUTPUT_FILE}" | head -3
        fi
        rm -f "${OUTPUT_FILE}"
        exit 1
    fi
else
    echo "  [ERREUR] Échec du téléchargement"
    exit 1
fi

# Extraire
echo ""
echo "[4] Extraction..."
if tar -xzf "${OUTPUT_FILE}" 2>&1; then
    echo "  [OK] Extraction réussie"
else
    echo "  [ERREUR] Échec de l'extraction"
    exit 1
fi

# Installer
echo ""
echo "[5] Installation..."
mkdir -p /opt/code-server
if [ -d "code-server-${LATEST_VERSION}-linux-amd64" ]; then
    cp -r "code-server-${LATEST_VERSION}-linux-amd64"/* /opt/code-server/
    chmod +x /opt/code-server/code-server
    echo "  [OK] Installation terminée"
    
    # Vérifier que code-server est exécutable
    if [ -x /opt/code-server/code-server ]; then
        VERSION_OUTPUT=$(/opt/code-server/code-server --version 2>&1 || echo "erreur")
        echo "  Version installée: ${VERSION_OUTPUT}"
    fi
else
    echo "  [ERREUR] Dossier d'extraction non trouvé"
    exit 1
fi

echo ""
echo "=============================================================="
echo " [OK] Code-Server installé avec succès"
echo "=============================================================="
echo ""
echo "Le service code-server devrait maintenant fonctionner."
echo "Vérifiez avec : systemctl status code-server"
echo ""

