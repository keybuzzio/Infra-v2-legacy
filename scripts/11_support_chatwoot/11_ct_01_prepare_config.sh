#!/usr/bin/env bash
#
# 11_ct_01_prepare_config.sh - Crée ConfigMap et Secrets pour Chatwoot
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_DIR="/opt/keybuzz-installer-v2/credentials"

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

export KUBECONFIG=/root/.kube/config

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Préparation ConfigMap et Secrets"
echo "=============================================================="
echo ""

# Charger les credentials
if [ ! -f "${CREDENTIALS_DIR}/chatwoot.env" ]; then
    log_error "Fichier chatwoot.env non trouvé. Exécutez d'abord 11_ct_00_setup_credentials.sh"
    exit 1
fi

source "${CREDENTIALS_DIR}/chatwoot.env"
source "${CREDENTIALS_DIR}/postgres.env"
source "${CREDENTIALS_DIR}/redis.env"

# Générer SECRET_KEY_BASE si non défini
if [ -z "${SECRET_KEY_BASE:-}" ]; then
    SECRET_KEY_BASE=$(openssl rand -hex 64)
    log_info "SECRET_KEY_BASE généré"
fi

# Créer le namespace
log_info "Création du namespace chatwoot..."
kubectl create namespace chatwoot --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace chatwoot app=keybuzz-support component=chatwoot --overwrite
log_success "Namespace chatwoot créé"

# Construire REDIS_URL
if [ -n "${REDIS_PASSWORD:-}" ]; then
    REDIS_URL="redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}/0"
else
    REDIS_URL="redis://${REDIS_HOST}:${REDIS_PORT}/0"
fi

# Créer ConfigMap
log_info "Création du ConfigMap chatwoot-config..."
kubectl create configmap chatwoot-config \
  --from-literal=RAILS_ENV=production \
  --from-literal=FRONTEND_URL=https://support.keybuzz.io \
  --from-literal=INSTALLATION_ENV=KeyBuzz \
  --from-literal=POSTGRES_HOST="${POSTGRES_HOST}" \
  --from-literal=POSTGRES_PORT="${POSTGRES_PORT}" \
  --from-literal=POSTGRES_DB="${CHATWOOT_DB}" \
  --from-literal=POSTGRES_USERNAME="${CHATWOOT_USER}" \
  --from-literal=REDIS_HOST="${REDIS_HOST}" \
  --from-literal=REDIS_PORT="${REDIS_PORT}" \
  --from-literal=REDIS_URL="${REDIS_URL}" \
  --namespace=chatwoot \
  --dry-run=client -o yaml | kubectl apply -f -

log_success "ConfigMap créé"

# Créer Secret
log_info "Création du Secret chatwoot-secrets..."
kubectl create secret generic chatwoot-secrets \
  --from-literal=POSTGRES_PASSWORD="${CHATWOOT_PASSWORD}" \
  --from-literal=SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
  --from-literal=REDIS_PASSWORD="${REDIS_PASSWORD:-}" \
  --namespace=chatwoot \
  --dry-run=client -o yaml | kubectl apply -f -

log_success "Secret créé"

# Ajouter S3/MinIO si configuré
if [ -f "${CREDENTIALS_DIR}/minio.env" ]; then
    source "${CREDENTIALS_DIR}/minio.env"
    if [ -n "${MINIO_ACCESS_KEY:-}" ] && [ -n "${MINIO_SECRET_KEY:-}" ]; then
        log_info "Ajout de la configuration S3/MinIO..."
        
        # Mettre à jour ConfigMap
        kubectl patch configmap chatwoot-config -n chatwoot --type merge -p "{\"data\":{\"S3_ENDPOINT\":\"${MINIO_ENDPOINT:-http://10.0.0.134:9000}\",\"S3_BUCKET\":\"keybuzz-chatwoot\",\"S3_REGION\":\"us-east-1\"}}"
        
        # Mettre à jour Secret
        kubectl patch secret chatwoot-secrets -n chatwoot --type merge -p "{\"data\":{\"S3_ACCESS_KEY\":\"$(echo -n "${MINIO_ACCESS_KEY}" | base64 -w 0)\",\"S3_SECRET_KEY\":\"$(echo -n "${MINIO_SECRET_KEY}" | base64 -w 0)\"}}"
        
        log_success "Configuration S3/MinIO ajoutée"
    fi
fi

echo ""
log_success "✅ Configuration terminée"
echo ""
log_info "ConfigMap et Secret créés dans le namespace chatwoot"
echo ""

