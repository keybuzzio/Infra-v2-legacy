#!/usr/bin/env bash
#
# run_on_install01.sh - Exécute un script sur install-01
#
# Usage:
#   ./run_on_install01.sh script.sh
#   ./run_on_install01.sh "commandes"
#
# Transfère et exécute un script sur install-01

set -euo pipefail

INSTALL_01_IP="91.98.128.153"
SSH_USER="root"
REMOTE_DIR="/tmp/keybuzz-scripts"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Créer le répertoire distant
ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
    "${SSH_USER}@${INSTALL_01_IP}" "mkdir -p ${REMOTE_DIR}"

# Si un fichier est fourni, le transférer et l'exécuter
if [[ -f "${1:-}" ]]; then
    SCRIPT_FILE="$1"
    SCRIPT_NAME=$(basename "${SCRIPT_FILE}")
    REMOTE_SCRIPT="${REMOTE_DIR}/${SCRIPT_NAME}"
    
    echo "Transfert de ${SCRIPT_FILE} vers install-01..."
    scp ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
        "${SCRIPT_FILE}" "${SSH_USER}@${INSTALL_01_IP}:${REMOTE_SCRIPT}"
    
    echo "Exécution de ${REMOTE_SCRIPT} sur install-01..."
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${INSTALL_01_IP}" "chmod +x ${REMOTE_SCRIPT} && ${REMOTE_SCRIPT}"
# Sinon, exécuter la commande directement
elif [[ $# -gt 0 ]]; then
    COMMAND="$*"
    echo "Exécution de la commande sur install-01..."
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${INSTALL_01_IP}" "${COMMAND}"
else
    echo "Usage: $0 <script.sh> ou $0 \"commandes\""
    exit 1
fi


