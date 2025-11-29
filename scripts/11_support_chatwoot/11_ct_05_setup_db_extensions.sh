#!/usr/bin/env bash
#
# 11_ct_05_setup_db_extensions.sh - Crée les extensions PostgreSQL nécessaires
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
echo " [KeyBuzz] Module 11 - Setup Extensions PostgreSQL"
echo "=============================================================="
echo ""

# Charger les credentials
source "${CREDENTIALS_DIR}/postgres.env"
source "${CREDENTIALS_DIR}/chatwoot.env"

POSTGRES_HOST="${POSTGRES_HOST:-10.0.0.10}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-kb_admin}"
POSTGRES_SUPERPASS="${POSTGRES_SUPERPASS:-}"

export PGPASSWORD="${POSTGRES_SUPERPASS}"

log_info "Création de l'extension pg_stat_statements dans la base chatwoot..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d chatwoot <<EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOF

if [ $? -eq 0 ]; then
    log_success "Extension pg_stat_statements créée"
else
    log_error "Échec de la création de l'extension"
    exit 1
fi

# Vérifier que l'extension existe
log_info "Vérification de l'extension..."
EXT_EXISTS=$(psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_SUPERUSER}" -d chatwoot -t -c "SELECT COUNT(*) FROM pg_extension WHERE extname = 'pg_stat_statements';" 2>/dev/null | tr -d ' ')

if [ "${EXT_EXISTS}" = "1" ]; then
    log_success "Extension vérifiée"
else
    log_warning "Extension peut ne pas exister (vérification: ${EXT_EXISTS})"
fi

echo ""
log_success "✅ Extensions PostgreSQL configurées"
echo ""

