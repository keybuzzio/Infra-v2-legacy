#!/usr/bin/env bash
#
# test_ssh_connection.sh - Teste la connexion SSH vers install-01
#
# Usage:
#   ./test_ssh_connection.sh [IP]
#
# Teste la connexion SSH et affiche les informations du serveur

set -euo pipefail

INSTALL_01_IP="${1:-91.98.128.153}"
SSH_KEY="${HOME}/.ssh/keybuzz_infra"

echo "=============================================================="
echo " [KeyBuzz] Test de connexion SSH vers install-01"
echo "=============================================================="
echo ""
echo "IP cible : ${INSTALL_01_IP}"
echo ""

# Détecter la clé SSH à utiliser
if [[ -f "${SSH_KEY}" ]]; then
    SSH_OPTS="-i ${SSH_KEY}"
    echo "✅ Clé SSH trouvée : ${SSH_KEY}"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_OPTS="-i ${HOME}/.ssh/id_ed25519"
    echo "✅ Utilisation de la clé par défaut : id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_OPTS="-i ${HOME}/.ssh/id_rsa"
    echo "✅ Utilisation de la clé par défaut : id_rsa"
else
    SSH_OPTS=""
    echo "⚠️  Aucune clé SSH trouvée, utilisation de l'authentification par défaut"
fi

echo ""
echo "Test de connexion..."
echo ""

# Test de connexion
if ssh ${SSH_OPTS} -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=~/.ssh/known_hosts \
    root@${INSTALL_01_IP} "echo '✅ Connexion SSH réussie!' && hostname && whoami && uname -a"; then
    echo ""
    echo "=============================================================="
    echo "✅ Connexion SSH fonctionnelle !"
    echo "=============================================================="
    echo ""
    echo "Informations du serveur :"
    ssh ${SSH_OPTS} root@${INSTALL_01_IP} << 'EOF'
echo "Hostname : $(hostname)"
echo "IP privée : $(ip addr show | grep 'inet 10.0.0' | awk '{print $2}' | cut -d/ -f1)"
echo "OS : $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "Kernel : $(uname -r)"
echo "Uptime : $(uptime -p)"
echo "Docker : $(docker --version 2>/dev/null || echo 'Non installé')"
echo "Git : $(git --version 2>/dev/null || echo 'Non installé')"
EOF
    echo ""
    echo "=============================================================="
    exit 0
else
    echo ""
    echo "=============================================================="
    echo "❌ Échec de la connexion SSH"
    echo "=============================================================="
    echo ""
    echo "Vérifications à faire :"
    echo "1. Le serveur est-il accessible ?"
    echo "   ping ${INSTALL_01_IP}"
    echo ""
    echo "2. Le port 22 est-il ouvert ?"
    echo "   telnet ${INSTALL_01_IP} 22"
    echo ""
    echo "3. La clé SSH est-elle déposée sur install-01 ?"
    echo "   Voir SETUP_SSH_ACCESS.md"
    echo ""
    echo "4. Les permissions de la clé sont-elles correctes ?"
    echo "   chmod 600 ${SSH_KEY}"
    echo ""
    exit 1
fi

