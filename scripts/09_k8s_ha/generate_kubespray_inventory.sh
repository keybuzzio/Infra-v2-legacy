#!/usr/bin/env bash
#
# generate_kubespray_inventory.sh - Génère l'inventaire Kubespray depuis servers.tsv
#
# Usage:
#   ./generate_kubespray_inventory.sh [servers.tsv] [output_dir]
#
# Prérequis:
#   - Fichier servers.tsv avec les nœuds K8s
#   - Exécuter depuis install-01
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/inventory/servers.tsv}"
OUTPUT_DIR="${2:-${INSTALL_DIR}/kubespray/inventory/keybuzz}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

mkdir -p "${OUTPUT_DIR}"

# Collecter les nœuds K8s
declare -a MASTER_NODES
declare -a MASTER_IPS
declare -a WORKER_NODES
declare -a WORKER_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    # Détecter les masters K8s
    if [[ "${HOSTNAME}" == "k8s-master-01" ]] || \
       [[ "${HOSTNAME}" == "k8s-master-02" ]] || \
       [[ "${HOSTNAME}" == "k8s-master-03" ]]; then
        MASTER_NODES+=("${HOSTNAME}")
        MASTER_IPS+=("${IP_PRIVEE}")
    fi
    
    # Détecter les workers K8s
    if [[ "${HOSTNAME}" == "k8s-worker-01" ]] || \
       [[ "${HOSTNAME}" == "k8s-worker-02" ]] || \
       [[ "${HOSTNAME}" == "k8s-worker-03" ]] || \
       [[ "${HOSTNAME}" == "k8s-worker-04" ]] || \
       [[ "${HOSTNAME}" == "k8s-worker-05" ]]; then
        WORKER_NODES+=("${HOSTNAME}")
        WORKER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#MASTER_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de masters incorrect: ${#MASTER_NODES[@]} (attendu: 3)"
    exit 1
fi

if [[ ${#WORKER_NODES[@]} -ne 5 ]]; then
    log_error "Nombre de workers incorrect: ${#WORKER_NODES[@]} (attendu: 5)"
    exit 1
fi

log_info "Masters détectés: ${MASTER_NODES[*]}"
log_info "Workers détectés: ${WORKER_NODES[*]}"

# Générer hosts.yaml
log_info "Génération de hosts.yaml..."

cat > "${OUTPUT_DIR}/hosts.yaml" <<EOF
all:
  hosts:
EOF

# Ajouter les masters
for i in "${!MASTER_NODES[@]}"; do
    NODE="${MASTER_NODES[$i]}"
    IP="${MASTER_IPS[$i]}"
    cat >> "${OUTPUT_DIR}/hosts.yaml" <<EOF
    ${NODE}:
      ansible_host: ${IP}
      ip: ${IP}
      access_ip: ${IP}
EOF
done

# Ajouter les workers
for i in "${!WORKER_NODES[@]}"; do
    NODE="${WORKER_NODES[$i]}"
    IP="${WORKER_IPS[$i]}"
    cat >> "${OUTPUT_DIR}/hosts.yaml" <<EOF
    ${NODE}:
      ansible_host: ${IP}
      ip: ${IP}
      access_ip: ${IP}
EOF
done

# Ajouter les groupes
cat >> "${OUTPUT_DIR}/hosts.yaml" <<EOF
  children:
    kube_control_plane:
      hosts:
        ${MASTER_NODES[0]}:
        ${MASTER_NODES[1]}:
        ${MASTER_NODES[2]}:
    kube_node:
      hosts:
        ${WORKER_NODES[0]}:
        ${WORKER_NODES[1]}:
        ${WORKER_NODES[2]}:
        ${WORKER_NODES[3]}:
        ${WORKER_NODES[4]}:
    etcd:
      hosts:
        ${MASTER_NODES[0]}:
        ${MASTER_NODES[1]}:
        ${MASTER_NODES[2]}:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
EOF

log_success "Inventaire généré: ${OUTPUT_DIR}/hosts.yaml"
log_info "Fichier créé avec succès"

