#!/usr/bin/env bash
#
# 09_k3s_06_deploy_core_apps.sh - Déploiement KeyBuzz Core Apps
#
# NOTE: Ce script est un placeholder. Les applications KeyBuzz (API, Front, Chatwoot, n8n, etc.)
# seront déployées dans des modules séparés pour un meilleur contrôle et validation.
#
# Ce script crée uniquement les namespaces de base et vérifie la connectivité
# aux services backend (PostgreSQL, Redis, RabbitMQ, MinIO, MariaDB).
#
# Usage:
#   ./09_k3s_06_deploy_core_apps.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_05_ingress_daemonset.sh exécuté
#   - Cluster K3s opérationnel
#   - Modules 3-8 installés (services backend)
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
echo " [KeyBuzz] Module 9 - Préparation pour Applications KeyBuzz"
echo "=============================================================="
echo ""
log_info "Ce script prépare l'environnement pour les applications KeyBuzz"
log_info "Les applications seront déployées dans des modules séparés"
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

# Créer les namespaces de base
log_info "Création des namespaces de base..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

# Namespaces pour applications KeyBuzz
kubectl create namespace keybuzz --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace chatwoot --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace n8n --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ai --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace vault --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Namespaces créés"
kubectl get namespaces | grep -E "keybuzz|chatwoot|n8n|analytics|ai|vault"
EOF

log_success "Namespaces créés"
echo ""

# Vérifier la connectivité aux services backend
log_info "Vérification de la connectivité aux services backend..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

echo "=== Test connectivité PostgreSQL (10.0.0.10:5432) ==="
timeout 3 nc -z 10.0.0.10 5432 && echo "✓ PostgreSQL accessible" || echo "✗ PostgreSQL non accessible"

echo ""
echo "=== Test connectivité Redis (10.0.0.10:6379) ==="
timeout 3 nc -z 10.0.0.10 6379 && echo "✓ Redis accessible" || echo "✗ Redis non accessible"

echo ""
echo "=== Test connectivité RabbitMQ (10.0.0.10:5672) ==="
timeout 3 nc -z 10.0.0.10 5672 && echo "✓ RabbitMQ accessible" || echo "✗ RabbitMQ non accessible"

echo ""
echo "=== Test connectivité MinIO (10.0.0.134:9000) ==="
timeout 3 nc -z 10.0.0.134 9000 && echo "✓ MinIO accessible" || echo "✗ MinIO non accessible"

echo ""
echo "=== Test connectivité MariaDB (10.0.0.20:3306) ==="
timeout 3 nc -z 10.0.0.20 3306 && echo "✓ MariaDB accessible" || echo "✗ MariaDB non accessible"
EOF

# Créer un ConfigMap avec les endpoints des services
log_info "Création du ConfigMap avec les endpoints des services..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

cat <<CONFIGMAP | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: keybuzz-backend-services
  namespace: keybuzz
data:
  postgresql.host: "10.0.0.10"
  postgresql.port: "5432"
  redis.host: "10.0.0.10"
  redis.port: "6379"
  rabbitmq.host: "10.0.0.10"
  rabbitmq.port: "5672"
  minio.host: "10.0.0.134"
  minio.port: "9000"
  mariadb.host: "10.0.0.20"
  mariadb.port: "3306"
CONFIGMAP

echo "✓ ConfigMap créé"
kubectl get configmap keybuzz-backend-services -n keybuzz
EOF

log_success "ConfigMap créé avec les endpoints des services"
echo ""

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Environnement préparé pour applications KeyBuzz"
echo "=============================================================="
echo ""
log_info "Namespaces créés:"
log_info "  - keybuzz (KeyBuzz API/Front)"
log_info "  - chatwoot (Chatwoot rebrandé)"
log_info "  - n8n (n8n Workflows)"
log_info "  - analytics (Superset)"
log_info "  - ai (LiteLLM, Services IA)"
log_info "  - vault (Vault Agent)"
echo ""
log_info "ConfigMap créé: keybuzz-backend-services"
log_info "  Contient les endpoints de tous les services backend"
echo ""
log_warning "NOTE: Les applications seront déployées dans des modules séparés:"
log_warning "  - Module 10: KeyBuzz API & Front"
log_warning "  - Module 11: Chatwoot"
log_warning "  - Module 12: n8n"
log_warning "  - Module 13: Superset"
log_warning "  - Module 14: Vault Agent"
log_warning "  - Module 15: LiteLLM & Services IA"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_07_install_monitoring.sh ${TSV_FILE}"
echo ""

