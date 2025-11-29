#!/usr/bin/env bash
#
# 09_k3s_01_prepare.sh - Préparation des nœuds K3s
#
# Ce script prépare tous les nœuds K3s (masters et workers) :
# - Vérification des prérequis (swap OFF, Docker, UFW)
# - Configuration DNS (resolv.conf fix)
# - Configuration UFW pour K3s
# - Vérification de la connectivité réseau
#
# Usage:
#   ./09_k3s_01_prepare.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les nœuds
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
echo " [KeyBuzz] Module 9 - Préparation des nœuds K3s"
echo "=============================================================="
echo ""

# Collecter les nœuds K3s
declare -a K3S_MASTER_NODES=()
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
        if [[ -n "${IP_PRIVEE}" ]]; then
            if [[ "${SUBROLE}" == "master" ]]; then
                K3S_MASTER_NODES+=("${HOSTNAME}")
                K3S_MASTER_IPS+=("${IP_PRIVEE}")
            elif [[ "${SUBROLE}" == "worker" ]]; then
                K3S_WORKER_NODES+=("${HOSTNAME}")
                K3S_WORKER_IPS+=("${IP_PRIVEE}")
            fi
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 3 ]]; then
    log_error "3 nœuds master K3s requis, trouvé: ${#K3S_MASTER_IPS[@]}"
    exit 1
fi

if [[ ${#K3S_WORKER_IPS[@]} -lt 1 ]]; then
    log_warning "Aucun nœud worker détecté, mais la préparation continuera"
fi

log_success "Nœuds K3s détectés:"
log_info "  Masters: ${K3S_MASTER_NODES[*]} (${K3S_MASTER_IPS[*]})"
log_info "  Workers: ${K3S_WORKER_NODES[*]} (${K3S_WORKER_IPS[*]})"
echo ""

# Fonction pour préparer un nœud
prepare_node() {
    local hostname="$1"
    local ip="$2"
    local role="$3"  # master ou worker
    
    log_info "=============================================================="
    log_info "Préparation: ${hostname} (${ip}) - ${role}"
    log_info "=============================================================="
    
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

# 1. Vérifier swap OFF
log_info() { echo "[INFO] \$1"; }
log_success() { echo "[✓] \$1"; }
log_error() { echo "[✗] \$1"; }

log_info "Vérification swap..."
if swapon --show | grep -q .; then
    log_error "Swap activé, désactivation..."
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
    log_success "Swap désactivé"
else
    log_success "Swap déjà désactivé"
fi

# 2. Vérifier Docker (pour autres services, K3s utilise containerd)
log_info "Vérification Docker..."
if command -v docker >/dev/null 2>&1; then
    log_success "Docker installé"
    docker --version
else
    log_error "Docker non installé"
    exit 1
fi

# 3. Configuration DNS (fix resolv.conf)
log_info "Configuration DNS..."
if [[ ! -f /etc/resolv.conf.backup ]]; then
    cp /etc/resolv.conf /etc/resolv.conf.backup
fi

cat > /etc/resolv.conf <<RESOLV
nameserver 1.1.1.1
nameserver 8.8.8.8
RESOLV

chattr +i /etc/resolv.conf 2>/dev/null || true
log_success "DNS configuré (1.1.1.1, 8.8.8.8)"

# 4. Configuration UFW pour K3s
log_info "Configuration UFW..."

# Ports communs
ufw allow 22/tcp comment 'SSH'
ufw allow 10250/tcp comment 'K3s Kubelet API'
ufw allow 8472/udp comment 'K3s Flannel VXLAN'

# Ports spécifiques masters
if [[ "${role}" == "master" ]]; then
    ufw allow 6443/tcp comment 'K3s API Server'
fi

# Activer UFW si pas déjà activé
if ! ufw status | grep -q "Status: active"; then
    ufw --force enable
fi

log_success "UFW configuré"

# 5. Vérifier la connectivité réseau
log_info "Test connectivité réseau..."
if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
    log_success "Connectivité Internet OK"
else
    log_error "Pas de connectivité Internet"
    exit 1
fi

# 6. Vérifier que K3s n'est pas déjà installé
if command -v k3s >/dev/null 2>&1; then
    log_warning "K3s déjà installé sur ce nœud"
    log_warning "Continuez uniquement si vous voulez réinstaller"
else
    log_success "K3s non installé, prêt pour installation"
fi

log_success "${hostname} préparé avec succès"
EOF
    
    if [ $? -eq 0 ]; then
        log_success "${hostname}: Préparation réussie"
    else
        log_error "${hostname}: Échec de la préparation"
        exit 1
    fi
    
    echo ""
}

# Préparer tous les masters
log_info "Préparation des nœuds masters..."
for i in "${!K3S_MASTER_NODES[@]}"; do
    prepare_node "${K3S_MASTER_NODES[$i]}" "${K3S_MASTER_IPS[$i]}" "master"
done

# Préparer tous les workers
if [[ ${#K3S_WORKER_IPS[@]} -gt 0 ]]; then
    log_info "Préparation des nœuds workers..."
    for i in "${!K3S_WORKER_NODES[@]}"; do
        prepare_node "${K3S_WORKER_NODES[$i]}" "${K3S_WORKER_IPS[$i]}" "worker"
    done
fi

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Tous les nœuds K3s préparés"
echo "=============================================================="
echo ""
log_info "Nœuds préparés:"
log_info "  Masters: ${#K3S_MASTER_IPS[@]} nœuds"
log_info "  Workers: ${#K3S_WORKER_IPS[@]} nœuds"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_02_install_control_plane.sh ${TSV_FILE}"
echo ""

