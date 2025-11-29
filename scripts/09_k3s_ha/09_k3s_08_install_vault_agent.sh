#!/usr/bin/env bash
#
# 09_k3s_08_install_vault_agent.sh - Installation Vault Agent
#
# NOTE: Ce script est un placeholder. Vault Agent sera déployé dans un module séparé
# (Module 14) pour un meilleur contrôle et validation.
#
# Ce script crée uniquement le namespace vault et prépare l'environnement.
#
# Usage:
#   ./09_k3s_08_install_vault_agent.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_07_install_monitoring.sh exécuté
#   - Cluster K3s opérationnel
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 9 - Préparation Vault Agent"
echo "=============================================================="
echo ""
log_info "Vault Agent sera déployé dans Module 14 (séparé)"
log_info "Ce script prépare uniquement l'environnement"
echo ""

# Trouver le premier master
declare -a K3S_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"

log_info "Utilisation du master: ${MASTER_IP}"
echo ""

# Créer le namespace vault
log_info "Création du namespace vault..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Namespace vault créé"
kubectl get namespace vault
EOF

log_success "Namespace vault créé"
echo ""

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Environnement Vault préparé"
echo "=============================================================="
echo ""
log_info "Namespace créé: vault"
log_warning "NOTE: Vault Agent sera déployé dans Module 14 (séparé)"
log_warning "  Cela permet un meilleur contrôle et validation"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_09_final_validation.sh ${TSV_FILE}"
echo ""

