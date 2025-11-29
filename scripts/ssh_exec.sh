#!/usr/bin/env bash
#
# ssh_exec.sh - Exécute une commande sur install-01 via SSH
#
# Usage:
#   ./ssh_exec.sh "commande"
#   ./ssh_exec.sh "hostname && whoami"
#
# Ce script se connecte à install-01 et exécute la commande fournie

set -euo pipefail

INSTALL_01_IP="91.98.128.153"
SSH_USER="root"

# Détecter la clé SSH à utiliser
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Si un argument est fourni, exécuter la commande
if [[ $# -gt 0 ]]; then
    COMMAND="$*"
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${INSTALL_01_IP}" "${COMMAND}"
else
    # Sinon, ouvrir une session interactive
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=accept-new \
        "${SSH_USER}@${INSTALL_01_IP}"
fi


