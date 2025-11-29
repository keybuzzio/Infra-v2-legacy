#!/usr/bin/env bash
#
# 00_check_ssh_access_all_servers.sh - Verifie l'acces SSH a tous les serveurs
#
# Usage:
#   ./00_check_ssh_access_all_servers.sh [servers.tsv]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Fonction pour parser servers.tsv
get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

# Fonction pour tester l'acces SSH
test_ssh() {
    local ip="$1"
    local hostname="$2"
    if ssh ${SSH_OPTS} root@"${ip}" "echo OK" 2>/dev/null | grep -q "OK"; then
        return 0
    else
        return 1
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Verification Acces SSH - Tous les Serveurs"
echo "=============================================================="
echo ""

ACCESSIBLE=0
INACCESSIBLE=0
INACCESSIBLE_LIST=()

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    # Ignorer la ligne d'en-tete
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]] || [[ -z "${HOSTNAME}" ]]; then
        continue
    fi
    
    if test_ssh "${IP_PRIVEE}" "${HOSTNAME}"; then
        log_success "${HOSTNAME} (${IP_PRIVEE})"
        ACCESSIBLE=$((ACCESSIBLE + 1))
    else
        log_error "${HOSTNAME} (${IP_PRIVEE})"
        INACCESSIBLE=$((INACCESSIBLE + 1))
        INACCESSIBLE_LIST+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

echo ""
echo "=============================================================="
echo " Resume"
echo "=============================================================="
log_info "Serveurs accessibles: ${ACCESSIBLE}"
if [[ ${INACCESSIBLE} -gt 0 ]]; then
    log_error "Serveurs inaccessibles: ${INACCESSIBLE}"
    echo ""
    log_warning "Serveurs inaccessibles:"
    for server in "${INACCESSIBLE_LIST[@]}"; do
        echo "  - ${server}"
    done
else
    log_success "Tous les serveurs sont accessibles"
fi
echo ""

if [[ ${ACCESSIBLE} -eq 0 ]]; then
    log_error "Aucun serveur accessible. Verifiez la connectivite."
    exit 1
fi

if [[ ${INACCESSIBLE} -gt 0 ]]; then
    log_warning "Certains serveurs sont inaccessibles. Le redemarrage peut echouer pour ces serveurs."
    exit 1
fi

log_success "Tous les serveurs sont accessibles. Pret pour le redemarrage."
exit 0

