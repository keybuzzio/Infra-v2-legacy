#!/usr/bin/env bash
#
# 09_k3s_04_bootstrap_addons.sh - Bootstrap addons K3s
#
# Ce script configure les addons de base K3s :
# - CoreDNS (déjà déployé par K3s, vérification)
# - metrics-server (pour autoscaling et métriques)
# - StorageClass local-path (déjà déployé par K3s, vérification)
#
# Usage:
#   ./09_k3s_04_bootstrap_addons.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_03_join_workers.sh exécuté
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
echo " [KeyBuzz] Module 9 - Bootstrap Addons K3s"
echo "=============================================================="
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

# Vérifier CoreDNS
log_info "=============================================================="
log_info "Vérification CoreDNS"
log_info "=============================================================="

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

echo "Vérification CoreDNS..."
if kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
    echo "✓ CoreDNS déjà déployé"
    kubectl get pods -n kube-system -l k8s-app=kube-dns
else
    echo "ERREUR: CoreDNS non trouvé"
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    log_success "CoreDNS opérationnel"
else
    log_warning "CoreDNS non vérifié (peut être normal si K3s vient d'être installé)"
fi

echo ""

# Installer metrics-server
log_info "=============================================================="
log_info "Installation metrics-server"
log_info "=============================================================="

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

# Vérifier si metrics-server existe déjà
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    echo "metrics-server déjà installé, mise à jour..."
    kubectl delete deployment metrics-server -n kube-system || true
    sleep 5
fi

# Installer metrics-server
echo "Installation metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Attendre que metrics-server soit prêt
echo "Attente que metrics-server soit prêt (30 secondes)..."
sleep 30

# Vérifier l'installation
if kubectl get deployment metrics-server -n kube-system >/dev/null 2>&1; then
    echo "✓ metrics-server installé"
    kubectl get pods -n kube-system -l k8s-app=metrics-server
else
    echo "ERREUR: metrics-server non installé"
    exit 1
fi
EOF

if [ $? -eq 0 ]; then
    log_success "metrics-server installé"
else
    log_warning "metrics-server non installé (peut nécessiter une configuration supplémentaire)"
fi

echo ""

# Vérifier StorageClass
log_info "=============================================================="
log_info "Vérification StorageClass"
log_info "=============================================================="

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

echo "Vérification StorageClass..."
kubectl get storageclass

echo ""
echo "Vérification local-path-provisioner..."
if kubectl get deployment local-path-provisioner -n kube-system >/dev/null 2>&1; then
    echo "✓ local-path-provisioner déjà déployé"
    kubectl get pods -n kube-system -l app=local-path-provisioner
else
    echo "local-path-provisioner non trouvé (peut être normal)"
fi
EOF

log_success "StorageClass vérifié"
echo ""

# Vérifier l'état global du cluster
log_info "Vérification de l'état global du cluster..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

echo "=== Nœuds ==="
kubectl get nodes

echo ""
echo "=== Pods système ==="
kubectl get pods -n kube-system

echo ""
echo "=== Services ==="
kubectl get svc -n kube-system
EOF

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Addons bootstrap configurés"
echo "=============================================================="
echo ""
log_info "Addons vérifiés/installés:"
log_info "  - CoreDNS: Opérationnel"
log_info "  - metrics-server: Installé"
log_info "  - StorageClass: Vérifié"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_05_ingress_daemonset.sh ${TSV_FILE}"
echo ""

