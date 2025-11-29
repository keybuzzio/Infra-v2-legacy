#!/usr/bin/env bash
#
# 11_ct_06_recreate_configmap.sh - Recrée le ConfigMap complet
#

set -euo pipefail

CREDENTIALS_DIR="/opt/keybuzz-installer-v2/credentials"
export KUBECONFIG=/root/.kube/config

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

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Recréation ConfigMap Complet"
echo "=============================================================="
echo ""

# Charger les credentials
source "${CREDENTIALS_DIR}/chatwoot.env"
source "${CREDENTIALS_DIR}/redis.env"

# Supprimer l'ancien ConfigMap
log_info "Suppression de l'ancien ConfigMap..."
kubectl delete configmap chatwoot-config -n chatwoot --ignore-not-found=true

# Créer le nouveau ConfigMap complet
log_info "Création du ConfigMap complet..."
kubectl create configmap chatwoot-config \
  --from-literal=RAILS_ENV=production \
  --from-literal=FRONTEND_URL=https://support.keybuzz.io \
  --from-literal=INSTALLATION_ENV=KeyBuzz \
  --from-literal=POSTGRES_HOST=10.0.0.10 \
  --from-literal=POSTGRES_PORT=5432 \
  --from-literal=POSTGRES_DB=chatwoot_production \
  --from-literal=POSTGRES_USERNAME=chatwoot \
  --from-literal=REDIS_HOST=10.0.0.10 \
  --from-literal=REDIS_PORT=6379 \
  --from-literal=REDIS_URL="redis://:${REDIS_PASSWORD}@10.0.0.10:6379/0" \
  --namespace=chatwoot

log_success "ConfigMap créé"

echo ""
log_success "✅ ConfigMap recréé avec toutes les variables"
echo ""

