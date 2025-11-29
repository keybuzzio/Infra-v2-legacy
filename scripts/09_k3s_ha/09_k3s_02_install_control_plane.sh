#!/usr/bin/env bash
#
# 09_k3s_02_install_control_plane.sh - Installation control-plane HA K3s
#
# Ce script installe le control-plane HA K3s sur 3 masters :
# - k3s-master-01 : Bootstrap avec --cluster-init
# - k3s-master-02 : Join avec --server
# - k3s-master-03 : Join avec --server
#
# Usage:
#   ./09_k3s_02_install_control_plane.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_01_prepare.sh exécuté
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
TOKEN_FILE="${INSTALL_DIR}/credentials/k3s_token.txt"

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
echo " [KeyBuzz] Module 9 - Installation Control-Plane HA K3s"
echo "=============================================================="
echo ""

# Collecter les nœuds masters
declare -a K3S_MASTER_NODES=()
declare -a K3S_MASTER_IPS=()
declare -a K3S_MASTER_PUBLIC_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]]; then
        if [[ -n "${IP_PRIVEE}" ]] && [[ -n "${IP_PUBLIQUE}" ]]; then
            K3S_MASTER_NODES+=("${HOSTNAME}")
            K3S_MASTER_IPS+=("${IP_PRIVEE}")
            K3S_MASTER_PUBLIC_IPS+=("${IP_PUBLIQUE}")
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 3 ]]; then
    log_error "3 nœuds master K3s requis, trouvé: ${#K3S_MASTER_IPS[@]}"
    exit 1
fi

log_success "Nœuds masters détectés: ${K3S_MASTER_NODES[*]} (${K3S_MASTER_IPS[*]})"
echo ""

# Créer le répertoire pour le token
mkdir -p "$(dirname "${TOKEN_FILE}")"

# Étape 1: Installer K3s sur le premier master (bootstrap)
log_info "=============================================================="
log_info "Étape 1/3 : Installation bootstrap sur ${K3S_MASTER_NODES[0]}"
log_info "=============================================================="

BOOTSTRAP_IP="${K3S_MASTER_IPS[0]}"
BOOTSTRAP_PUBLIC_IP="${K3S_MASTER_PUBLIC_IPS[0]}"
BOOTSTRAP_HOSTNAME="${K3S_MASTER_NODES[0]}"

log_info "Installation K3s avec --cluster-init..."
ssh ${SSH_KEY_OPTS} "root@${BOOTSTRAP_IP}" bash <<EOF
set -euo pipefail

# Vérifier que K3s n'est pas déjà installé
if command -v k3s >/dev/null 2>&1; then
    echo "K3s déjà installé, arrêt et désinstallation..."
    k3s-killall.sh || true
    k3s-uninstall.sh || true
    sleep 5
fi

# Installer K3s avec cluster-init (configuration HA complète)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --cluster-init --write-kubeconfig-mode 644 --tls-san ${BOOTSTRAP_IP} --tls-san ${BOOTSTRAP_PUBLIC_IP} --node-ip ${BOOTSTRAP_IP} --advertise-address ${BOOTSTRAP_IP} --flannel-iface eth0 --flannel-backend vxlan --disable traefik --disable servicelb" sh -

# Attendre que K3s soit prêt
echo "Attente que K3s soit prêt (30 secondes)..."
sleep 30

# Vérifier l'installation
if kubectl get nodes >/dev/null 2>&1; then
    echo "✓ K3s installé et opérationnel"
    kubectl get nodes
else
    echo "ERREUR: K3s non opérationnel"
    exit 1
fi
EOF

if [ $? -ne 0 ]; then
    log_error "Échec de l'installation bootstrap"
    exit 1
fi

log_success "Bootstrap réussi sur ${BOOTSTRAP_HOSTNAME}"

# Récupérer le token
log_info "Récupération du token K3s..."
K3S_TOKEN=$(ssh ${SSH_KEY_OPTS} "root@${BOOTSTRAP_IP}" "cat /var/lib/rancher/k3s/server/node-token")

if [[ -z "${K3S_TOKEN}" ]]; then
    log_error "Impossible de récupérer le token K3s"
    exit 1
fi

# Sauvegarder le token
echo "${K3S_TOKEN}" > "${TOKEN_FILE}"
chmod 600 "${TOKEN_FILE}"
log_success "Token sauvegardé: ${TOKEN_FILE}"

# Étape 2: Installer K3s sur le deuxième master
log_info "=============================================================="
log_info "Étape 2/3 : Installation sur ${K3S_MASTER_NODES[1]}"
log_info "=============================================================="

MASTER2_IP="${K3S_MASTER_IPS[1]}"
MASTER2_PUBLIC_IP="${K3S_MASTER_PUBLIC_IPS[1]}"
MASTER2_HOSTNAME="${K3S_MASTER_NODES[1]}"

log_info "Installation K3s avec --server..."
ssh ${SSH_KEY_OPTS} "root@${MASTER2_IP}" bash <<EOF
set -euo pipefail

# Vérifier que K3s n'est pas déjà installé
if command -v k3s >/dev/null 2>&1; then
    echo "K3s déjà installé, arrêt et désinstallation..."
    k3s-killall.sh || true
    k3s-uninstall.sh || true
    sleep 5
fi

# Installer K3s en rejoignant le cluster (configuration HA complète)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --server https://${BOOTSTRAP_IP}:6443 --token ${K3S_TOKEN} --write-kubeconfig-mode 644 --tls-san ${MASTER2_IP} --tls-san ${MASTER2_PUBLIC_IP} --node-ip ${MASTER2_IP} --advertise-address ${MASTER2_IP} --flannel-iface eth0 --flannel-backend vxlan --disable traefik --disable servicelb" sh -

# Attendre que K3s soit prêt
echo "Attente que K3s soit prêt (30 secondes)..."
sleep 30

echo "✓ K3s installé"
EOF

if [ $? -ne 0 ]; then
    log_error "Échec de l'installation sur ${MASTER2_HOSTNAME}"
    exit 1
fi

log_success "Installation réussie sur ${MASTER2_HOSTNAME}"

# Étape 3: Installer K3s sur le troisième master
log_info "=============================================================="
log_info "Étape 3/3 : Installation sur ${K3S_MASTER_NODES[2]}"
log_info "=============================================================="

MASTER3_IP="${K3S_MASTER_IPS[2]}"
MASTER3_PUBLIC_IP="${K3S_MASTER_PUBLIC_IPS[2]}"
MASTER3_HOSTNAME="${K3S_MASTER_NODES[2]}"

log_info "Installation K3s avec --server..."
ssh ${SSH_KEY_OPTS} "root@${MASTER3_IP}" bash <<EOF
set -euo pipefail

# Vérifier que K3s n'est pas déjà installé
if command -v k3s >/dev/null 2>&1; then
    echo "K3s déjà installé, arrêt et désinstallation..."
    k3s-killall.sh || true
    k3s-uninstall.sh || true
    sleep 5
fi

# Installer K3s en rejoignant le cluster (configuration HA complète)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server --server https://${BOOTSTRAP_IP}:6443 --token ${K3S_TOKEN} --write-kubeconfig-mode 644 --tls-san ${MASTER3_IP} --tls-san ${MASTER3_PUBLIC_IP} --node-ip ${MASTER3_IP} --advertise-address ${MASTER3_IP} --flannel-iface eth0 --flannel-backend vxlan --disable traefik --disable servicelb" sh -

# Attendre que K3s soit prêt
echo "Attente que K3s soit prêt (30 secondes)..."
sleep 30

echo "✓ K3s installé"
EOF

if [ $? -ne 0 ]; then
    log_error "Échec de l'installation sur ${MASTER3_HOSTNAME}"
    exit 1
fi

log_success "Installation réussie sur ${MASTER3_HOSTNAME}"

# Attendre la stabilisation du cluster
log_info "Attente de la stabilisation du cluster (20 secondes)..."
sleep 20

# Vérifier le cluster HA
log_info "Vérification du cluster HA..."
ssh ${SSH_KEY_OPTS} "root@${BOOTSTRAP_IP}" bash <<EOF
set -euo pipefail

echo "=== État des nœuds ==="
kubectl get nodes -o wide

echo ""
echo "=== État du control-plane ==="
kubectl get nodes -l node-role.kubernetes.io/master=true || kubectl get nodes -l node-role.kubernetes.io/control-plane=true

echo ""
echo "=== Pods système ==="
kubectl get pods -n kube-system
EOF

# Copier kubeconfig sur install-01
log_info "Copie du kubeconfig sur install-01..."
mkdir -p "${HOME}/.kube"
ssh ${SSH_KEY_OPTS} "root@${BOOTSTRAP_IP}" "cat /etc/rancher/k3s/k3s.yaml" | sed "s/127.0.0.1/${BOOTSTRAP_IP}/g" > "${HOME}/.kube/config" 2>/dev/null || true
chmod 600 "${HOME}/.kube/config" 2>/dev/null || true

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Control-plane HA K3s installé"
echo "=============================================================="
echo ""
log_info "Masters installés:"
log_info "  - ${K3S_MASTER_NODES[0]} (${K3S_MASTER_IPS[0]}) - Bootstrap"
log_info "  - ${K3S_MASTER_NODES[1]} (${K3S_MASTER_IPS[1]})"
log_info "  - ${K3S_MASTER_NODES[2]} (${K3S_MASTER_IPS[2]})"
echo ""
log_info "Token sauvegardé: ${TOKEN_FILE}"
log_info "Kubeconfig disponible sur ${BOOTSTRAP_IP}"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_03_join_workers.sh ${TSV_FILE}"
echo ""
