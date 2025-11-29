#!/bin/bash
#
# exec_on_install01.sh - Exécute des commandes sur install-01 avec passphrase automatique
# Utilise sshpass pour automatiser la connexion SSH
#
# Usage:
#   ./exec_on_install01.sh "commande"
#   ./exec_on_install01.sh  # Session interactive

INSTALL_01_IP="91.98.128.153"
SSH_USER="root"

# Trouver le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PASSPHRASE_FILE="${PROJECT_ROOT}/SSH/passphrase.txt"
SSH_KEY="${PROJECT_ROOT}/SSH/keybuzz_infra"

# Vérifier les fichiers
if [[ ! -f "${PASSPHRASE_FILE}" ]]; then
    echo "❌ Fichier passphrase introuvable : ${PASSPHRASE_FILE}"
    exit 1
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "❌ Clé SSH introuvable : ${SSH_KEY}"
    exit 1
fi

# Lire le passphrase
PASSPHRASE=$(cat "${PASSPHRASE_FILE}" | tr -d '\r\n')

# Vérifier si sshpass est disponible
if ! command -v sshpass >/dev/null 2>&1; then
    echo "❌ sshpass n'est pas installé"
    echo "   Installation via apt-get (dans WSL) ou via votre gestionnaire de paquets"
    echo ""
    echo "   Connexion manuelle (vous devrez entrer le passphrase):"
    SSH_CMD="ssh -i ${SSH_KEY} -o StrictHostKeyChecking=accept-new ${SSH_USER}@${INSTALL_01_IP}"
    if [[ $# -gt 0 ]]; then
        eval "${SSH_CMD} \"$*\""
    else
        eval "${SSH_CMD}"
    fi
    exit 0
fi

# Construire la commande SSH avec sshpass
SSH_CMD="sshpass -p '${PASSPHRASE}' ssh"
SSH_CMD="${SSH_CMD} -i ${SSH_KEY}"
SSH_CMD="${SSH_CMD} -o StrictHostKeyChecking=accept-new"
SSH_CMD="${SSH_CMD} ${SSH_USER}@${INSTALL_01_IP}"

# Exécuter la commande ou ouvrir une session interactive
if [[ $# -gt 0 ]]; then
    echo "🔌 Exécution sur install-01 : $*"
    eval "${SSH_CMD} \"$*\""
else
    echo "🔌 Connexion interactive à install-01..."
    eval "${SSH_CMD}"
fi

