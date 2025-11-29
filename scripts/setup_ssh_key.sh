#!/usr/bin/env bash
#
# setup_ssh_key.sh - Génère une clé SSH pour l'accès à install-01
#
# Usage:
#   ./setup_ssh_key.sh
#
# Ce script génère une paire de clés SSH (sans passphrase pour l'automatisation)
# et affiche les instructions pour déposer la clé publique sur install-01

set -euo pipefail

KEY_NAME="keybuzz_infra"
KEY_PATH="${HOME}/.ssh/${KEY_NAME}"
KEY_PUB="${KEY_PATH}.pub"

echo "=============================================================="
echo " [KeyBuzz] Génération de clé SSH pour install-01"
echo "=============================================================="

# Créer le dossier .ssh s'il n'existe pas
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"

# Générer la clé SSH (sans passphrase pour l'automatisation)
if [[ ! -f "${KEY_PATH}" ]]; then
    echo "Génération de la clé SSH..."
    ssh-keygen -t ed25519 -f "${KEY_PATH}" -N "" -C "keybuzz-infra-automation"
    echo "✅ Clé SSH générée : ${KEY_PATH}"
else
    echo "⚠️  La clé existe déjà : ${KEY_PATH}"
fi

# Afficher la clé publique
echo ""
echo "=============================================================="
echo " Clé publique à déposer sur install-01 :"
echo "=============================================================="
echo ""
cat "${KEY_PUB}"
echo ""
echo "=============================================================="
echo " Instructions :"
echo "=============================================================="
echo ""
echo "1. Copier la clé publique ci-dessus"
echo ""
echo "2. Se connecter sur install-01 :"
echo "   ssh root@91.98.128.153"
echo ""
echo "3. Ajouter la clé publique dans ~/.ssh/authorized_keys :"
echo "   mkdir -p ~/.ssh"
echo "   chmod 700 ~/.ssh"
echo "   echo '[COLLER_LA_CLE_PUBLIQUE_ICI]' >> ~/.ssh/authorized_keys"
echo "   chmod 600 ~/.ssh/authorized_keys"
echo ""
echo "4. Tester la connexion depuis cette machine :"
echo "   ssh -i ${KEY_PATH} root@91.98.128.153"
echo ""
echo "=============================================================="


