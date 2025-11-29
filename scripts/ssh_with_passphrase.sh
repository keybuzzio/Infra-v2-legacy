#!/usr/bin/env bash
#
# ssh_with_passphrase.sh - Connexion SSH avec passphrase automatique
#
# Usage:
#   ./ssh_with_passphrase.sh "commande"
#   ./ssh_with_passphrase.sh
#
# Ce script utilise sshpass pour automatiser la connexion SSH avec passphrase

set -euo pipefail

INSTALL_01_IP="91.98.128.153"
SSH_USER="root"
PASSPHRASE_FILE="${HOME}/Mon Drive/keybuzzio/SSH/passphrase.txt"

# Vérifier si sshpass est installé
if ! command -v sshpass >/dev/null 2>&1; then
    echo "⚠️  sshpass n'est pas installé. Installation..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y sshpass
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install hudochenkov/sshpass/sshpass
    else
        echo "❌ Veuillez installer sshpass manuellement"
        exit 1
    fi
fi

# Lire le passphrase
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
    echo "❌ Fichier passphrase introuvable : ${PASSPHRASE_FILE}"
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

# Construire la commande SSH
SSH_CMD="sshpass -P passphrase -p '${PASSPHRASE}' ssh"
if [[ -n "${SSH_KEY}" ]]; then
    SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
fi
SSH_CMD="${SSH_CMD} -o StrictHostKeyChecking=accept-new"
SSH_CMD="${SSH_CMD} ${SSH_USER}@${INSTALL_01_IP}"

# Si une commande est fournie, l'exécuter
if [[ $# -gt 0 ]]; then
    COMMAND="$*"
    eval "${SSH_CMD} \"${COMMAND}\""
else
    # Sinon, ouvrir une session interactive
    eval "${SSH_CMD}"
fi


