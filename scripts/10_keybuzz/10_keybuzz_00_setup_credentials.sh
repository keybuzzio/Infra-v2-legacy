#!/usr/bin/env bash
#
# 10_keybuzz_00_setup_credentials.sh - Configuration des credentials KeyBuzz
#
# Ce script charge les credentials des services backend (PostgreSQL, Redis, RabbitMQ)
# et génère les URLs complètes pour KeyBuzz API.
#
# Usage:
#   ./10_keybuzz_00_setup_credentials.sh
#
# Prérequis:
#   - Modules 3, 4, 5 installés (PostgreSQL, Redis, RabbitMQ)
#   - Fichiers credentials existants
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/keybuzz.env"
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
echo " [KeyBuzz] Module 10 - Configuration Credentials KeyBuzz"
echo "=============================================================="
echo ""

# Créer le répertoire credentials si nécessaire
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

# Vérifier si le fichier existe déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${KEYBUZZ_DATABASE_URL:-}" ]] && [[ -n "${KEYBUZZ_REDIS_URL:-}" ]] && [[ -n "${KEYBUZZ_RABBITMQ_URL:-}" ]]; then
        log_success "Credentials KeyBuzz déjà configurés"
        log_info "Database URL: ${KEYBUZZ_DATABASE_URL%%@*}@..."
        log_info "Redis URL: ${KEYBUZZ_REDIS_URL%%@*}@..."
        log_info "RabbitMQ URL: ${KEYBUZZ_RABBITMQ_URL%%@*}@..."
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

# Construire les URLs selon Context.txt
# DATABASE_URL=postgres://kb_app:<pass>@10.0.0.10:5432/keybuzz
KEYBUZZ_DATABASE_URL="postgres://${POSTGRES_APP_USER:-kb_app}:${POSTGRES_APP_PASS:-}@10.0.0.10:5432/${POSTGRES_DB:-keybuzz}"

# REDIS_URL=redis://10.0.0.10:6379
# Note: Redis peut avoir un mot de passe, mais selon Context.txt, on utilise redis:// sans auth
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    KEYBUZZ_REDIS_URL="redis://:${REDIS_PASSWORD}@10.0.0.10:6379"
else
    KEYBUZZ_REDIS_URL="redis://10.0.0.10:6379"
fi

# RABBITMQ_URL=amqp://kb_rmq:<pass>@10.0.0.10:5672//
KEYBUZZ_RABBITMQ_URL="amqp://${RABBITMQ_USER:-kb_rmq}:${RABBITMQ_PASSWORD:-}@10.0.0.10:5672//"

# MINIO_URL=http://10.0.0.134:9000
KEYBUZZ_MINIO_URL="http://10.0.0.134:9000"

# VECTOR_URL=http://10.0.0.136:6333 (Qdrant - optionnel pour Module 10)
KEYBUZZ_VECTOR_URL="http://10.0.0.136:6333"

# LLM_URL=http://llm-proxy.ai.svc.cluster.local:4000 (LiteLLM - sera déployé dans Module 15)
KEYBUZZ_LLM_URL="http://llm-proxy.ai.svc.cluster.local:4000"

# Créer le fichier credentials KeyBuzz
log_info "Création du fichier ${CREDENTIALS_FILE}..."

cat > "${CREDENTIALS_FILE}" <<EOF
#!/bin/bash
# KeyBuzz Credentials - Généré automatiquement
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# Ne pas modifier manuellement

# URLs de connexion aux services backend
export KEYBUZZ_DATABASE_URL="${KEYBUZZ_DATABASE_URL}"
export KEYBUZZ_REDIS_URL="${KEYBUZZ_REDIS_URL}"
export KEYBUZZ_RABBITMQ_URL="${KEYBUZZ_RABBITMQ_URL}"
export KEYBUZZ_MINIO_URL="${KEYBUZZ_MINIO_URL}"
export KEYBUZZ_VECTOR_URL="${KEYBUZZ_VECTOR_URL}"
export KEYBUZZ_LLM_URL="${KEYBUZZ_LLM_URL}"

# Variables d'environnement pour KeyBuzz API (format standard)
export DATABASE_URL="${KEYBUZZ_DATABASE_URL}"
export REDIS_URL="${KEYBUZZ_REDIS_URL}"
export RABBITMQ_URL="${KEYBUZZ_RABBITMQ_URL}"
export MINIO_URL="${KEYBUZZ_MINIO_URL}"
export VECTOR_URL="${KEYBUZZ_VECTOR_URL}"
export LLM_URL="${KEYBUZZ_LLM_URL}"

# Informations de connexion (pour référence)
export POSTGRES_HOST="10.0.0.10"
export POSTGRES_PORT="5432"
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

export MINIO_ENDPOINT="10.0.0.134"
export MINIO_PORT="9000"

export QDRANT_HOST="10.0.0.136"
export QDRANT_PORT="6333"
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials KeyBuzz générés"
log_info "Fichier: ${CREDENTIALS_FILE}"
echo ""
echo "=============================================================="
log_success "✅ Credentials KeyBuzz configurés avec succès"
echo "=============================================================="
echo ""
echo "URLs configurées:"
echo "  Database: ${KEYBUZZ_DATABASE_URL%%@*}@10.0.0.10:5432/${POSTGRES_DB:-keybuzz}"
echo "  Redis: ${KEYBUZZ_REDIS_URL}"
echo "  RabbitMQ: ${KEYBUZZ_RABBITMQ_URL%%@*}@10.0.0.10:5672//"
echo "  MinIO: ${KEYBUZZ_MINIO_URL}"
echo "  Qdrant: ${KEYBUZZ_VECTOR_URL}"
echo "  LiteLLM: ${KEYBUZZ_LLM_URL}"
echo ""
log_info "Prochaine étape: ./10_keybuzz_01_deploy_api.sh"
echo ""

