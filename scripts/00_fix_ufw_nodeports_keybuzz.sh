#!/usr/bin/env bash
#
# 00_fix_ufw_nodeports_keybuzz.sh - Ouverture ports NodePort dans UFW
#
# Ce script ouvre les ports NodePort (31695, 32720) dans UFW sur tous les workers K3s
# pour permettre aux Load Balancers Hetzner d'accéder à l'Ingress NGINX.
#
# Usage:
#   ./00_fix_ufw_nodeports_keybuzz.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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
echo " [KeyBuzz] Ouverture Ports NodePort dans UFW"
echo "=============================================================="
echo ""
echo "Ports à ouvrir :"
echo "  - HTTP  : 31695/tcp (Ingress NGINX)"
echo "  - HTTPS : 32720/tcp (Ingress NGINX)"
echo ""
echo "Workers affectés : Tous les workers K3s"
echo ""

if [[ "${AUTO_YES}" != "--yes" ]]; then
    read -p "Continuer ? (yes/NO) : " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Annulé"
        exit 0
    fi
fi

# Récupérer les IPs des workers
declare -a WORKER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "worker" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        WORKER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#WORKER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun worker K3s trouvé"
    exit 1
fi

log_info "Workers trouvés: ${#WORKER_IPS[@]}"
echo ""

HTTP_NODEPORT=31695
HTTPS_NODEPORT=32720

SUCCESS=0
FAIL=0

for ip in "${WORKER_IPS[@]}"; do
    log_info "Configuration UFW sur worker ${ip}..."
    
    set +e
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@${ip}" bash <<EOF
set +u

# Fonction pour ajouter une règle UFW (idempotente)
add_ufw_rule() {
    local port="\$1"
    local comment="\$2"
    
    if ! ufw status numbered | grep -q "\$comment"; then
        ufw allow \$port/tcp comment "\$comment" >/dev/null 2>&1 || true
        echo "  ✓ Port \$port ouvert"
    else
        echo "  ℹ️  Port \$port déjà ouvert"
    fi
}

# Ouvrir les NodePorts
add_ufw_rule "${HTTP_NODEPORT}" "Ingress NGINX HTTP NodePort"
add_ufw_rule "${HTTPS_NODEPORT}" "Ingress NGINX HTTPS NodePort"

# Recharger UFW SANS interruption
ufw reload >/dev/null 2>&1 || true
echo "  ✓ UFW rechargé"
EOF
    SSH_EXIT=$?
    set -e
    
    if [[ $SSH_EXIT -eq 0 ]]; then
        log_success "Worker ${ip} configuré"
        ((SUCCESS++))
    else
        log_error "Worker ${ip} : échec"
        ((FAIL++))
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
log_success "Workers configurés : ${SUCCESS} / ${#WORKER_IPS[@]}"
if [[ $FAIL -gt 0 ]]; then
    log_error "Workers en échec : ${FAIL} / ${#WORKER_IPS[@]}"
fi
echo ""

if [[ $FAIL -eq 0 ]]; then
    log_success "✅ Ports NodePort ouverts sur tous les workers"
    echo ""
    log_info "Test rapide depuis install-01:"
    for ip in "${WORKER_IPS[@]}"; do
        echo -n "  Worker ${ip}:${HTTP_NODEPORT} ... "
        if timeout 3 bash -c "</dev/tcp/${ip}/${HTTP_NODEPORT}" 2>/dev/null; then
            log_success "OK"
        else
            log_warning "TIMEOUT"
        fi
    done
    echo ""
    log_info "Prochaine étape: Exécuter 00_fix_504_keybuzz_complete.sh"
else
    log_warning "⚠️  Certains workers ont échoué"
    log_info "Vérifiez l'accès SSH aux workers en échec"
fi

echo ""
echo "=============================================================="

