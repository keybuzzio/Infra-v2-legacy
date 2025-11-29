#!/usr/bin/env bash
#
# 09_k3s_restore_cluster.sh - Restaurer le cluster K3s après tests de failover
#
# Ce script restaure tous les nœuds K3s à l'état Ready après des tests de failover
#

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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi
SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Trouver les nœuds K3s
declare -a K3S_MASTER_IPS=()
declare -a K3S_MASTER_HOSTNAMES=()
declare -a K3S_WORKER_IPS=()
declare -a K3S_WORKER_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        if [[ "${SUBROLE}" == "master" ]]; then
            K3S_MASTER_IPS+=("${IP_PRIVEE}")
            K3S_MASTER_HOSTNAMES+=("${HOSTNAME}")
        elif [[ "${SUBROLE}" == "worker" ]]; then
            K3S_WORKER_IPS+=("${IP_PRIVEE}")
            K3S_WORKER_HOSTNAMES+=("${HOSTNAME}")
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun nœud K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"

echo "=============================================================="
echo " [KeyBuzz] Restauration Cluster K3s"
echo "=============================================================="
echo ""

# État initial
log_info "État actuel du cluster..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes" || true
echo ""

# Redémarrer tous les masters
log_info "Redémarrage des masters..."
for i in "${!K3S_MASTER_IPS[@]}"; do
    IP="${K3S_MASTER_IPS[$i]}"
    HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "  ${HOSTNAME} (${IP})..."
    ssh ${SSH_KEY_OPTS} "root@${IP}" "systemctl start k3s" || true
    sleep 5
done

# Redémarrer tous les workers
log_info "Redémarrage des workers..."
for i in "${!K3S_WORKER_IPS[@]}"; do
    IP="${K3S_WORKER_IPS[$i]}"
    HOSTNAME="${K3S_WORKER_HOSTNAMES[$i]}"
    
    log_info "  ${HOSTNAME} (${IP})..."
    ssh ${SSH_KEY_OPTS} "root@${IP}" "systemctl start k3s-agent" || true
    sleep 3
done

log_info "Attente de la stabilisation (30 secondes)..."
sleep 30

# Vérifier l'état final
log_info "État final du cluster..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes"

echo ""
log_success "✅ Restauration terminée"

