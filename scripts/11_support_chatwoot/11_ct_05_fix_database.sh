#!/usr/bin/env bash
#
# 11_ct_05_fix_database.sh - Corrige la base de données Chatwoot
#

set -euo pipefail

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

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Correction Base de Données Chatwoot"
echo "=============================================================="
echo ""

# Charger les credentials
source "${CREDENTIALS_DIR}/postgres.env"
export PGPASSWORD="${POSTGRES_SUPERPASS}"

# Vérifier si la base chatwoot existe
log_info "Vérification de la base de données..."
DB_EXISTS=$(psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='chatwoot';" 2>/dev/null || echo "0")

if [ "${DB_EXISTS}" = "1" ]; then
    log_info "Base 'chatwoot' trouvée, renommage en 'chatwoot_production'..."
    psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres <<EOF
ALTER DATABASE chatwoot RENAME TO chatwoot_production;
EOF
    log_success "Base renommée"
elif psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='chatwoot_production';" 2>/dev/null | grep -q "1"; then
    log_success "Base 'chatwoot_production' existe déjà"
else
    log_info "Création de la base 'chatwoot_production'..."
    psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres <<EOF
CREATE DATABASE chatwoot_production OWNER chatwoot;
EOF
    log_success "Base créée"
fi

# Donner les permissions
log_info "Configuration des permissions..."
psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres <<EOF
GRANT ALL PRIVILEGES ON DATABASE chatwoot_production TO chatwoot;
ALTER USER chatwoot WITH CREATEDB;
EOF
log_success "Permissions configurées"

# Mettre à jour le ConfigMap
log_info "Mise à jour du ConfigMap..."
export KUBECONFIG=/root/.kube/config
kubectl patch configmap chatwoot-config -n chatwoot --type merge --patch '{"data":{"POSTGRES_DB":"chatwoot_production"}}'
log_success "ConfigMap mis à jour"

echo ""
log_success "✅ Base de données corrigée"
echo ""

