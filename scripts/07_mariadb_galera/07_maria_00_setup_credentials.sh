#!/usr/bin/env bash
#
# 07_maria_00_setup_credentials.sh - Configuration des credentials MariaDB Galera
#
# Ce script génère ou charge les credentials MariaDB nécessaires pour le cluster Galera.
# Il crée le fichier mariadb.env avec les variables d'environnement requises.
#
# Usage:
#   ./07_maria_00_setup_credentials.sh
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Répertoire credentials existant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/mariadb.env"

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
echo " [KeyBuzz] Module 7 - Configuration Credentials MariaDB Galera"
echo "=============================================================="
echo ""

# Créer le répertoire credentials s'il n'existe pas
mkdir -p "${CREDENTIALS_DIR}"

# Vérifier si les credentials existent déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    
    # Charger les credentials existants
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${MARIADB_ROOT_PASSWORD:-}" ]] && \
       [[ -n "${MARIADB_APP_USER:-}" ]] && \
       [[ -n "${MARIADB_APP_PASSWORD:-}" ]] && \
       [[ -n "${MARIADB_DB:-}" ]] && \
       [[ -n "${GALERA_CLUSTER_NAME:-}" ]]; then
        log_success "Credentials MariaDB déjà configurés"
        log_info "User: ${MARIADB_APP_USER}"
        log_info "Database: ${MARIADB_DB}"
        log_info "Cluster: ${GALERA_CLUSTER_NAME}"
        echo ""
        log_info "Utilisation des credentials existants"
        exit 0
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

log_info "Génération des nouveaux credentials MariaDB Galera..."
echo ""

# Générer les mots de passe forts
MARIADB_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
MARIADB_APP_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Configuration par défaut pour ERPNext
MARIADB_APP_USER="erpnext"
MARIADB_DB="erpnext"
GALERA_CLUSTER_NAME="keybuzz-galera"

# Créer le fichier credentials
cat > "${CREDENTIALS_FILE}" <<EOF
# MariaDB Galera Credentials - Généré automatiquement
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# Ne pas modifier manuellement

MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD}"
MARIADB_APP_USER="${MARIADB_APP_USER}"
MARIADB_APP_PASSWORD="${MARIADB_APP_PASSWORD}"
MARIADB_DB="${MARIADB_DB}"
GALERA_CLUSTER_NAME="${GALERA_CLUSTER_NAME}"

# Export pour utilisation dans les scripts
export MARIADB_ROOT_PASSWORD
export MARIADB_APP_USER
export MARIADB_APP_PASSWORD
export MARIADB_DB
export GALERA_CLUSTER_NAME
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials MariaDB Galera générés avec succès"
echo ""
log_info "Fichier: ${CREDENTIALS_FILE}"
log_info "Root Password: ${MARIADB_ROOT_PASSWORD:0:8}..."
log_info "App User: ${MARIADB_APP_USER}"
log_info "App Password: ${MARIADB_APP_PASSWORD:0:8}..."
log_info "Database: ${MARIADB_DB}"
log_info "Cluster Name: ${GALERA_CLUSTER_NAME}"
echo ""
log_warning "IMPORTANT: Conservez ces credentials en sécurité"
log_warning "Ils seront nécessaires pour accéder à MariaDB et configurer ERPNext"
echo ""

