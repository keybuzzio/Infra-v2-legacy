#!/usr/bin/env bash
#
# 05_rmq_00_setup_credentials.sh - Configuration des credentials RabbitMQ
#
# Ce script génère ou charge les credentials RabbitMQ nécessaires pour le cluster.
# Il crée le fichier rabbitmq.env avec les variables d'environnement requises.
#
# Usage:
#   ./05_rmq_00_setup_credentials.sh
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Répertoire credentials existant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/rabbitmq.env"

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
echo " [KeyBuzz] Module 5 - Configuration Credentials RabbitMQ"
echo "=============================================================="
echo ""

# Créer le répertoire credentials s'il n'existe pas
mkdir -p "${CREDENTIALS_DIR}"

# Vérifier si les credentials existent déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    
    # Charger les credentials existants
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${RABBITMQ_USER:-}" ]] && [[ -n "${RABBITMQ_PASSWORD:-}" ]] && [[ -n "${RABBITMQ_ERLANG_COOKIE:-}" ]]; then
        log_success "Credentials RabbitMQ déjà configurés"
        log_info "User: ${RABBITMQ_USER}"
        log_info "Erlang Cookie: ${RABBITMQ_ERLANG_COOKIE:0:8}..."
        echo ""
        log_info "Utilisation des credentials existants"
        exit 0
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

log_info "Génération des nouveaux credentials RabbitMQ..."
echo ""

# Générer un mot de passe fort (32 caractères)
RABBITMQ_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Générer un cookie Erlang fort (32 caractères alphanumériques)
RABBITMQ_ERLANG_COOKIE=$(openssl rand -hex 16)

# User par défaut
RABBITMQ_USER="kb_rmq"

# Créer le fichier credentials
cat > "${CREDENTIALS_FILE}" <<EOF
# RabbitMQ Credentials - Généré automatiquement
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# Ne pas modifier manuellement

RABBITMQ_USER="${RABBITMQ_USER}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD}"
RABBITMQ_ERLANG_COOKIE="${RABBITMQ_ERLANG_COOKIE}"

# Export pour utilisation dans les scripts
export RABBITMQ_USER
export RABBITMQ_PASSWORD
export RABBITMQ_ERLANG_COOKIE
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials RabbitMQ générés avec succès"
echo ""
log_info "Fichier: ${CREDENTIALS_FILE}"
log_info "User: ${RABBITMQ_USER}"
log_info "Password: ${RABBITMQ_PASSWORD:0:8}..."
log_info "Erlang Cookie: ${RABBITMQ_ERLANG_COOKIE}"
echo ""
log_warning "IMPORTANT: Le cookie Erlang doit être identique sur tous les nœuds du cluster"
log_warning "Ce fichier sera copié sur tous les nœuds RabbitMQ"
echo ""

