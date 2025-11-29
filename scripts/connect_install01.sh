#!/usr/bin/env bash
#
# connect_install01.sh - Script principal pour se connecter et exécuter sur install-01
#
# Usage:
#   ./connect_install01.sh "commande"
#   ./connect_install01.sh  # Session interactive
#
# Ce script utilise le passphrase stocké pour automatiser la connexion

set -euo pipefail

INSTALL_01_IP="91.98.128.153"
SSH_USER="root"

# Chemin du fichier passphrase (adaptable selon l'environnement)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PASSPHRASE_FILE="${PROJECT_ROOT}/SSH/passphrase.txt"

# Si le fichier n'existe pas au chemin relatif, essayer le chemin absolu Windows
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
    PASSPHRASE_FILE="${HOME}/Mon Drive/keybuzzio/SSH/passphrase.txt"
fi

# Lire le passphrase
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
    echo "❌ Fichier passphrase introuvable"
    echo "   Cherché dans : ${PASSPHRASE_FILE}"
    exit 1
fi

PASSPHRASE=$(cat "${PASSPHRASE_FILE}" | tr -d '\r\n')

# Détecter la clé SSH
SSH_KEY=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY="${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

# Vérifier si sshpass est disponible
if ! command -v sshpass >/dev/null 2>&1; then
    echo "⚠️  sshpass n'est pas installé"
    echo "   Installation recommandée pour automatisation"
    echo "   Sur Windows : installer via WSL ou Git Bash"
    echo ""
    echo "   Connexion manuelle (vous devrez entrer le passphrase) :"
    SSH_CMD="ssh"
    if [[ -n "${SSH_KEY}" ]]; then
        SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
    fi
    SSH_CMD="${SSH_CMD} -o StrictHostKeyChecking=accept-new"
    SSH_CMD="${SSH_CMD} ${SSH_USER}@${INSTALL_01_IP}"
    
    if [[ $# -gt 0 ]]; then
        eval "${SSH_CMD} \"$*\""
    else
        eval "${SSH_CMD}"
    fi
    exit 0
fi

# Construire la commande SSH avec sshpass
SSH_CMD="sshpass -p '${PASSPHRASE}' ssh"
if [[ -n "${SSH_KEY}" ]]; then
    SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
fi
SSH_CMD="${SSH_CMD} -o StrictHostKeyChecking=accept-new"
SSH_CMD="${SSH_CMD} ${SSH_USER}@${INSTALL_01_IP}"

# Exécuter la commande ou ouvrir une session interactive
if [[ $# -gt 0 ]]; then
    echo "🔌 Connexion à install-01 et exécution de la commande..."
    eval "${SSH_CMD} \"$*\""
else
    echo "🔌 Connexion interactive à install-01..."
    eval "${SSH_CMD}"
fi


