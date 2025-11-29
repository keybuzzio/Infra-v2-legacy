#!/usr/bin/env bash
#
# 10_platform_00_setup_credentials.sh - Configuration des credentials Platform KeyBuzz
#
# Ce script charge les credentials des services backend et génère les URLs
# pour Platform API avec PgBouncer (port 6432).
#
# Usage:
#   ./10_platform_00_setup_credentials.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Modules 3, 4, 5 installés (PostgreSQL, Redis, RabbitMQ)
#   - Fichiers credentials existants
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/platform.env"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 10 Platform - Configuration Credentials"
echo "=============================================================="
echo ""

# Créer le répertoire credentials si nécessaire
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

# Vérifier si le fichier existe déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${DATABASE_URL:-}" ]] && [[ -n "${REDIS_URL:-}" ]] && [[ -n "${RABBITMQ_URL:-}" ]]; then
        log_success "Credentials Platform déjà configurés"
        log_info "Database URL: ${DATABASE_URL%%@*}@..."
        log_info "Redis URL: ${REDIS_URL%%@*}@..."
        log_info "RabbitMQ URL: ${RABBITMQ_URL%%@*}@..."
        echo ""
        if [[ "${AUTO_YES}" == "--yes" ]]; then
            log_info "Mode non-interactif: utilisation des credentials existants"
            exit 0
        fi
        read -p "Voulez-vous régénérer les credentials ? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Utilisation des credentials existants"
            exit 0
        fi
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

# Charger les credentials des services backend
log_info "Chargement des credentials des services backend..."

# PostgreSQL
POSTGRES_CREDENTIALS="${CREDENTIALS_DIR}/postgres.env"
if [[ ! -f "${POSTGRES_CREDENTIALS}" ]]; then
    log_error "Fichier credentials PostgreSQL introuvable: ${POSTGRES_CREDENTIALS}"
    log_error "Exécutez d'abord le Module 3 (PostgreSQL HA)"
    exit 1
fi
source "${POSTGRES_CREDENTIALS}"

# Redis
REDIS_CREDENTIALS="${CREDENTIALS_DIR}/redis.env"
if [[ ! -f "${REDIS_CREDENTIALS}" ]]; then
    log_error "Fichier credentials Redis introuvable: ${REDIS_CREDENTIALS}"
    log_error "Exécutez d'abord le Module 4 (Redis HA)"
    exit 1
fi
source "${REDIS_CREDENTIALS}"

# RabbitMQ
RABBITMQ_CREDENTIALS="${CREDENTIALS_DIR}/rabbitmq.env"
if [[ ! -f "${RABBITMQ_CREDENTIALS}" ]]; then
    log_error "Fichier credentials RabbitMQ introuvable: ${RABBITMQ_CREDENTIALS}"
    log_error "Exécutez d'abord le Module 5 (RabbitMQ HA)"
    exit 1
fi
source "${RABBITMQ_CREDENTIALS}"

log_success "Credentials backend chargés"

# Construire les URLs selon les spécifications
# DATABASE_URL avec PgBouncer (port 6432) - RECOMMANDÉ
# OU port 5432 direct si PgBouncer non disponible
USE_PGBOUNCER="${USE_PGBOUNCER:-true}"
if [[ "${USE_PGBOUNCER}" == "true" ]]; then
    DATABASE_URL="postgresql://${POSTGRES_APP_USER:-kb_app}:${POSTGRES_APP_PASS:-}@10.0.0.10:6432/${POSTGRES_DB:-keybuzz}"
    log_info "Utilisation de PgBouncer (port 6432)"
else
    DATABASE_URL="postgresql://${POSTGRES_APP_USER:-kb_app}:${POSTGRES_APP_PASS:-}@10.0.0.10:5432/${POSTGRES_DB:-keybuzz}"
    log_info "Utilisation de PostgreSQL direct (port 5432)"
fi

# REDIS_URL
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    REDIS_URL="redis://:${REDIS_PASSWORD}@10.0.0.10:6379"
else
    REDIS_URL="redis://10.0.0.10:6379"
fi

# RABBITMQ_URL
RABBITMQ_URL="amqp://${RABBITMQ_USER:-kb_rmq}:${RABBITMQ_PASSWORD:-}@10.0.0.10:5672/"

# MINIO_ENDPOINT (sans / à la fin)
MINIO_ENDPOINT="http://10.0.0.134:9000"

# MARIADB_HOST (pour ERPNext si nécessaire)
MARIADB_HOST="10.0.0.20"

# Créer le fichier credentials Platform
log_info "Création du fichier ${CREDENTIALS_FILE}..."

cat > "${CREDENTIALS_FILE}" <<EOF
#!/bin/bash
# Platform KeyBuzz Credentials - Généré automatiquement
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# Ne pas modifier manuellement

# URLs de connexion aux services backend
export DATABASE_URL="${DATABASE_URL}"
export REDIS_URL="${REDIS_URL}"
export RABBITMQ_URL="${RABBITMQ_URL}"
export MINIO_ENDPOINT="${MINIO_ENDPOINT}"
export MARIADB_HOST="${MARIADB_HOST}"

# Variables d'environnement détaillées (pour référence)
export POSTGRES_HOST="10.0.0.10"
export POSTGRES_PORT="$([ "${USE_PGBOUNCER:-true}" == "true" ] && echo "6432" || echo "5432")"
export POSTGRES_DB="${POSTGRES_DB:-keybuzz}"
export POSTGRES_USER="${POSTGRES_APP_USER:-kb_app}"
export POSTGRES_PASSWORD="${POSTGRES_APP_PASS:-}"

export REDIS_HOST="10.0.0.10"
export REDIS_PORT="6379"
export REDIS_PASSWORD="${REDIS_PASSWORD:-}"

export RABBITMQ_HOST="10.0.0.10"
export RABBITMQ_PORT="5672"
export RABBITMQ_USER="${RABBITMQ_USER:-kb_rmq}"
export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-}"

export MINIO_ENDPOINT_HOST="10.0.0.134"
export MINIO_ENDPOINT_PORT="9000"
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials Platform générés"
log_info "Fichier: ${CREDENTIALS_FILE}"
echo ""
echo "=============================================================="
log_success "✅ Credentials Platform configurés avec succès"
echo "=============================================================="
echo ""
echo "URLs configurées:"
POSTGRES_PORT_VAL="$([ "${USE_PGBOUNCER:-true}" == "true" ] && echo "6432" || echo "5432")"
echo "  Database: ${DATABASE_URL%%@*}@10.0.0.10:${POSTGRES_PORT_VAL}/${POSTGRES_DB:-keybuzz}"
echo "  Redis: ${REDIS_URL}"
echo "  RabbitMQ: ${RABBITMQ_URL%%@*}@10.0.0.10:5672/"
echo "  MinIO: ${MINIO_ENDPOINT}"
echo "  MariaDB: ${MARIADB_HOST}"
echo ""
log_info "Prochaine étape: ./10_platform_01_deploy_api.sh"
echo ""

