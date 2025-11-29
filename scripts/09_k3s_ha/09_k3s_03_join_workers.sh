#!/usr/bin/env bash
#
# 09_k3s_03_join_workers.sh - Join des workers au cluster K3s
#
# Ce script fait rejoindre tous les workers au cluster K3s HA.
# Les workers se connectent via le LB Hetzner (10.0.0.5) ou directement
# au premier master.
#
# Usage:
#   ./09_k3s_03_join_workers.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_02_install_control_plane.sh exécuté
#   - Control-plane HA opérationnel
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
TOKEN_FILE="${INSTALL_DIR}/credentials/k3s_token.txt"
K3S_API_LB="10.0.0.5"  # LB Hetzner pour K3s API (à configurer manuellement)

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

if [[ ! -f "${TOKEN_FILE}" ]]; then
    log_error "Fichier token introuvable: ${TOKEN_FILE}"
    log_info "Exécutez d'abord: ./09_k3s_02_install_control_plane.sh"
    exit 1
fi

K3S_TOKEN=$(cat "${TOKEN_FILE}")

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
echo " [KeyBuzz] Module 9 - Join des Workers au Cluster K3s"
echo "=============================================================="
echo ""

# Collecter les nœuds
declare -a K3S_MASTER_IPS=()
declare -a K3S_WORKER_NODES=()
declare -a K3S_WORKER_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]]; then
        if [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
            K3S_MASTER_IPS+=("${IP_PRIVEE}")
        elif [[ "${SUBROLE}" == "worker" ]] && [[ -n "${IP_PRIVEE}" ]]; then
            K3S_WORKER_NODES+=("${HOSTNAME}")
            K3S_WORKER_IPS+=("${IP_PRIVEE}")
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

if [[ ${#K3S_WORKER_IPS[@]} -lt 1 ]]; then
    log_warning "Aucun worker détecté"
    log_info "Aucun worker à joindre, étape ignorée"
    exit 0
fi

# Utiliser le premier master comme API endpoint (ou LB si configuré)
K3S_API_ENDPOINT="${K3S_MASTER_IPS[0]}"
log_info "API Endpoint: ${K3S_API_ENDPOINT}:6443"
log_info "Workers à joindre: ${K3S_WORKER_NODES[*]} (${K3S_WORKER_IPS[*]})"
echo ""

# Joindre chaque worker
for i in "${!K3S_WORKER_NODES[@]}"; do
    hostname="${K3S_WORKER_NODES[$i]}"
    ip="${K3S_WORKER_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Join worker: ${hostname} (${ip})"
    log_info "=============================================================="
    
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

# Vérifier que K3s n'est pas déjà installé
if command -v k3s >/dev/null 2>&1; then
    echo "K3s déjà installé, arrêt et désinstallation..."
    k3s-killall.sh || true
    k3s-uninstall.sh || true
    sleep 5
fi

# Configuration UFW pour K3s worker
if command -v ufw &>/dev/null; then
    ufw allow from 10.0.0.0/16 to any port 10250 proto tcp comment 'K3s Kubelet' 2>/dev/null || true
    ufw allow from 10.0.0.0/16 to any port 8472 proto udp comment 'K3s Flannel VXLAN' 2>/dev/null || true
    ufw allow from 10.42.0.0/16 comment 'K3s Pod Network' 2>/dev/null || true
    ufw allow from 10.43.0.0/16 comment 'K3s Service Network' 2>/dev/null || true
    ufw reload 2>/dev/null || true
fi

# Joindre le cluster (configuration complète)
echo "Join au cluster K3s..."
curl -sfL https://get.k3s.io | K3S_URL=https://${K3S_API_ENDPOINT}:6443 K3S_TOKEN=${K3S_TOKEN} sh -s - agent --node-ip ${ip} --flannel-iface eth0

# Attendre que K3s soit prêt
echo "Attente que K3s soit prêt (20 secondes)..."
sleep 20

# Vérifier l'installation
if systemctl is-active --quiet k3s-agent; then
    echo "✓ K3s agent actif"
else
    echo "ERREUR: K3s agent non actif"
    systemctl status k3s-agent || true
    exit 1
fi
EOF
    
    if [ $? -eq 0 ]; then
        log_success "${hostname}: Joint au cluster avec succès"
    else
        log_error "${hostname}: Échec du join"
        exit 1
    fi
    
    echo ""
done

# Attendre la stabilisation
log_info "Attente de la stabilisation (15 secondes)..."
sleep 15

# Vérifier les nœuds depuis le master
log_info "Vérification des nœuds..."
ssh ${SSH_KEY_OPTS} "root@${K3S_MASTER_IPS[0]}" bash <<EOF
set -euo pipefail

echo "=== Tous les nœuds ==="
kubectl get nodes -o wide

echo ""
echo "=== Workers ==="
kubectl get nodes -l node-role.kubernetes.io/master!=true,node-role.kubernetes.io/control-plane!=true -o wide || kubectl get nodes --no-headers | grep -v master | grep -v control-plane || true
EOF

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Tous les workers joints au cluster"
echo "=============================================================="
echo ""
log_info "Workers joints: ${#K3S_WORKER_IPS[@]} nœuds"
log_info "  ${K3S_WORKER_NODES[*]}"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_04_bootstrap_addons.sh ${TSV_FILE}"
echo ""

