#!/usr/bin/env bash
#
# 04_redis_00_setup_credentials.sh - Configuration des credentials Redis
#
# Ce script génère ou charge les credentials Redis nécessaires pour le cluster HA.
#
# Usage:
#   ./04_redis_00_setup_credentials.sh
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Répertoire /opt/keybuzz-installer/credentials existe

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/redis.env"

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
echo " [KeyBuzz] Module 4 - Configuration Credentials Redis"
echo "=============================================================="
echo ""

# Créer le répertoire credentials si nécessaire
mkdir -p "${CREDENTIALS_DIR}"

# Gérer le mode non-interactif
NON_INTERACTIVE=false
for arg in "$@"; do
    if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
        NON_INTERACTIVE=true
        break
    fi
done

# Vérifier si les credentials existent déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${REDIS_PASSWORD:-}" ]] && [[ -n "${REDIS_MASTER_NAME:-}" ]]; then
        log_success "Credentials Redis déjà configurés"
        log_info "Master name: ${REDIS_MASTER_NAME}"
        log_info "Password hash: $(echo -n "${REDIS_PASSWORD}" | sha256sum | cut -c1-16)..."
        if [[ "${NON_INTERACTIVE}" == "true" ]]; then
            log_info "Mode non-interactif: utilisation des credentials existants"
            exit 0
        else
            echo ""
            read -p "Voulez-vous régénérer les credentials ? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_info "Utilisation des credentials existants"
                exit 0
            fi
        fi
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

# Générer les credentials
log_info "Génération des credentials Redis..."

# Générer un mot de passe fort
REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/\n" | cut -c1-32)
REDIS_SENTINEL_PASSWORD="${REDIS_PASSWORD}"  # Même mot de passe pour simplifier
REDIS_MASTER_NAME="kb-redis-master"

# Créer le fichier credentials
cat > "${CREDENTIALS_FILE}" <<EOF
#!/bin/bash
# Redis Credentials - NE JAMAIS COMMITER
# Généré le $(date '+%Y-%m-%d %H:%M:%S')

export REDIS_PASSWORD="${REDIS_PASSWORD}"
export REDIS_SENTINEL_PASSWORD="${REDIS_SENTINEL_PASSWORD}"
export REDIS_MASTER_NAME="${REDIS_MASTER_NAME}"
export REDIS_SENTINEL_QUORUM="2"
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials Redis générés"
log_info "Fichier: ${CREDENTIALS_FILE}"
log_info "Master name: ${REDIS_MASTER_NAME}"
log_info "Password hash: $(echo -n "${REDIS_PASSWORD}" | sha256sum | cut -c1-16)..."
echo ""

log_success "✅ Configuration des credentials terminée !"
echo ""

