#!/usr/bin/env bash
#
# deploy_module10_kubernetes.sh - Déploiement Module 10 Platform sur Kubernetes
#
# Usage:
#   ./deploy_module10_kubernetes.sh
#
# Prérequis:
#   - Module 9 installé (Kubernetes HA avec Kubespray)
#   - kubeconfig configuré sur install-01
#   - Credentials disponibles
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"

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

# Vérifier kubeconfig
export KUBECONFIG=/root/.kube/config
if ! kubectl cluster-info > /dev/null 2>&1; then
    log_error "Impossible de se connecter au cluster Kubernetes"
    log_error "Vérifiez que kubeconfig est configuré: export KUBECONFIG=/root/.kube/config"
    exit 1
fi

log_success "Cluster Kubernetes accessible"

# Charger les credentials
log_info "Chargement des credentials..."
source "${CREDENTIALS_DIR}/postgres.env"
source "${CREDENTIALS_DIR}/redis.env"
source "${CREDENTIALS_DIR}/rabbitmq.env"
source "${CREDENTIALS_DIR}/minio.env"

# Créer le namespace
log_info "Création du namespace keybuzz..."
kubectl create namespace keybuzz --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace keybuzz app=keybuzz component=platform --overwrite
log_success "Namespace keybuzz créé"

# Créer ConfigMap
log_info "Création du ConfigMap keybuzz-api-config..."
cat > /tmp/platform-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: keybuzz-api-config
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
data:
  MINIO_ENDPOINT: "http://10.0.0.134:9000"
  MARIADB_HOST: "10.0.0.20"
  POSTGRES_HOST: "10.0.0.10"
  POSTGRES_PORT: "6432"
  POSTGRES_DB: "keybuzz"
  POSTGRES_USER: "kb_app"
  REDIS_HOST: "10.0.0.10"
  REDIS_PORT: "6379"
  RABBITMQ_HOST: "10.0.0.10"
  RABBITMQ_PORT: "5672"
  RABBITMQ_USER: "kb_rmq"
  MINIO_ENDPOINT_HOST: "10.0.0.134"
  MINIO_ENDPOINT_PORT: "9000"
EOF

kubectl apply -f /tmp/platform-configmap.yaml
log_success "ConfigMap créé"

# Créer Secret
log_info "Création du Secret keybuzz-api-secret..."
kubectl create secret generic keybuzz-api-secret \
  -n keybuzz \
  --from-literal=DATABASE_URL="postgresql://kb_app:${POSTGRES_APP_PASS:-${POSTGRES_SUPERPASS}}@10.0.0.10:6432/keybuzz" \
  --from-literal=REDIS_URL="redis://:${REDIS_PASSWORD}@10.0.0.10:6379" \
  --from-literal=RABBITMQ_URL="amqp://kb_rmq:${RABBITMQ_PASSWORD}@10.0.0.10:5672/" \
  --from-literal=POSTGRES_PASSWORD="${POSTGRES_APP_PASS:-${POSTGRES_SUPERPASS}}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD}" \
  --from-literal=RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD}" \
  --from-literal=MINIO_ROOT_USER="${MINIO_ROOT_USER}" \
  --from-literal=MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" \
  --dry-run=client -o yaml | kubectl apply -f -
log_success "Secret créé"

echo ""
log_success "✅ Configuration de base terminée"
log_info "Prochaine étape: Déploiement des Deployments (API, UI, My)"
echo ""

