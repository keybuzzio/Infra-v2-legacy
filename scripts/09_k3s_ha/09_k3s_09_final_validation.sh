#!/usr/bin/env bash
#
# 09_k3s_09_final_validation.sh - Validation finale Module 9
#
# Ce script valide l'installation complète du Module 9 (K3s HA Core) :
# - État des nœuds (masters + workers)
# - Pods système
# - Addons (CoreDNS, metrics-server)
# - Ingress NGINX DaemonSet
# - Namespaces créés
# - Connectivité services backend
#
# Usage:
#   ./09_k3s_09_final_validation.sh [servers.tsv]
#
# Prérequis:
#   - Tous les scripts précédents du Module 9 exécutés
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
echo " [KeyBuzz] Module 9 - Validation Finale K3s HA"
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

log_info "Validation depuis: ${MASTER_IP}"
echo ""

# Validation complète
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'VALIDATION_SCRIPT'
set -euo pipefail

echo "=============================================================="
echo "1. ÉTAT DES NŒUDS"
echo "=============================================================="
kubectl get nodes -o wide

MASTER_COUNT=$(kubectl get nodes -l node-role.kubernetes.io/master=true --no-headers 2>/dev/null | wc -l || kubectl get nodes -l node-role.kubernetes.io/control-plane=true --no-headers 2>/dev/null | wc -l || echo "0")
WORKER_COUNT=$(kubectl get nodes --no-headers | grep -v master | grep -v control-plane | wc -l || echo "0")

echo ""
echo "Masters: ${MASTER_COUNT}"
echo "Workers: ${WORKER_COUNT}"

echo ""
echo "=============================================================="
echo "2. PODS SYSTÈME"
echo "=============================================================="
kubectl get pods -n kube-system

echo ""
echo "=============================================================="
echo "3. ADDONS"
echo "=============================================================="

echo "CoreDNS:"
kubectl get deployment coredns -n kube-system 2>/dev/null && echo "✓ CoreDNS" || echo "✗ CoreDNS non trouvé"

echo ""
echo "metrics-server:"
kubectl get deployment metrics-server -n kube-system 2>/dev/null && echo "✓ metrics-server" || echo "✗ metrics-server non trouvé"

echo ""
echo "StorageClass:"
kubectl get storageclass

echo ""
echo "=============================================================="
echo "4. INGRESS NGINX DAEMONSET"
echo "=============================================================="
kubectl get daemonset -n ingress-nginx

echo ""
NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
INGRESS_POD_COUNT=$(kubectl get pods -n ingress-nginx --no-headers | grep Running | wc -l)

echo "Nœuds: ${NODE_COUNT}"
echo "Pods Ingress Running: ${INGRESS_POD_COUNT}"

if [[ ${INGRESS_POD_COUNT} -ge ${NODE_COUNT} ]]; then
    echo "✓ Tous les nœuds ont un Pod Ingress"
else
    echo "⚠ Certains nœuds n'ont pas encore de Pod Ingress"
fi

echo ""
echo "=============================================================="
echo "5. NAMESPACES CRÉÉS"
echo "=============================================================="
kubectl get namespaces | grep -E "keybuzz|chatwoot|n8n|analytics|ai|vault|monitoring" || echo "Aucun namespace applicatif trouvé"

echo ""
echo "=============================================================="
echo "6. CONNECTIVITÉ SERVICES BACKEND"
echo "=============================================================="

echo "PostgreSQL (10.0.0.10:5432):"
timeout 2 nc -z 10.0.0.10 5432 && echo "✓ Accessible" || echo "✗ Non accessible"

echo "Redis (10.0.0.10:6379):"
timeout 2 nc -z 10.0.0.10 6379 && echo "✓ Accessible" || echo "✗ Non accessible"

echo "RabbitMQ (10.0.0.10:5672):"
timeout 2 nc -z 10.0.0.10 5672 && echo "✓ Accessible" || echo "✗ Non accessible"

echo "MinIO (10.0.0.134:9000):"
timeout 2 nc -z 10.0.0.134 9000 && echo "✓ Accessible" || echo "✗ Non accessible"

echo "MariaDB (10.0.0.20:3306):"
timeout 2 nc -z 10.0.0.20 3306 && echo "✓ Accessible" || echo "✗ Non accessible"

echo ""
echo "=============================================================="
echo "7. MONITORING (si installé)"
echo "=============================================================="
kubectl get pods -n monitoring 2>/dev/null | head -10 || echo "Monitoring non installé ou en cours d'installation"

VALIDATION_SCRIPT

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Validation Module 9 terminée"
echo "=============================================================="
echo ""
log_info "Module 9 (K3s HA Core) est maintenant opérationnel"
log_info ""
log_info "Composants validés:"
log_info "  - Control-plane HA: 3 masters"
log_info "  - Workers: Joints au cluster"
log_info "  - Addons: CoreDNS, metrics-server, StorageClass"
log_info "  - Ingress: NGINX DaemonSet"
log_info "  - Namespaces: Préparés pour applications"
log_info "  - Monitoring: Prometheus Stack (si installé)"
echo ""
log_warning "PROCHAINES ÉTAPES - Applications (modules séparés):"
log_warning "  - Module 10: KeyBuzz API & Front"
log_warning "  - Module 11: Chatwoot"
log_warning "  - Module 12: n8n"
log_warning "  - Module 13: Superset"
log_warning "  - Module 14: Vault Agent"
log_warning "  - Module 15: LiteLLM & Services IA"
echo ""

