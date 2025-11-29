#!/usr/bin/env bash
#
# 06_minio_00_setup_credentials.sh - Configuration des credentials MinIO
#
# Ce script génère ou charge les credentials MinIO nécessaires.
# Il crée le fichier minio.env avec les variables d'environnement requises.
#
# Usage:
#   ./06_minio_00_setup_credentials.sh
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Répertoire credentials existant

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/minio.env"

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
echo " [KeyBuzz] Module 6 - Configuration Credentials MinIO"
echo "=============================================================="
echo ""

# Créer le répertoire credentials s'il n'existe pas
mkdir -p "${CREDENTIALS_DIR}"

# Vérifier si les credentials existent déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    
    # Charger les credentials existants
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${MINIO_ROOT_USER:-}" ]] && [[ -n "${MINIO_ROOT_PASSWORD:-}" ]] && [[ -n "${MINIO_BUCKET:-}" ]]; then
        log_success "Credentials MinIO déjà configurés"
        log_info "User: ${MINIO_ROOT_USER}"
        log_info "Bucket: ${MINIO_BUCKET}"
        echo ""
        log_info "Utilisation des credentials existants"
        exit 0
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

log_info "Génération des nouveaux credentials MinIO..."
echo ""

# Générer un nom d'utilisateur admin avec suffixe aléatoire
RANDOM_SUFFIX=$(openssl rand -hex 4)
MINIO_ROOT_USER="admin-${RANDOM_SUFFIX}"

# Générer un mot de passe fort (32 caractères)
MINIO_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

# Bucket par défaut
MINIO_BUCKET="keybuzz-backups"

# Créer le fichier credentials
cat > "${CREDENTIALS_FILE}" <<EOF
# MinIO Credentials - Généré automatiquement
# Date: $(date '+%Y-%m-%d %H:%M:%S')
# Ne pas modifier manuellement

MINIO_ROOT_USER="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}"
MINIO_BUCKET="${MINIO_BUCKET}"

# Export pour utilisation dans les scripts
export MINIO_ROOT_USER
export MINIO_ROOT_PASSWORD
export MINIO_BUCKET
EOF

chmod 600 "${CREDENTIALS_FILE}"

log_success "Credentials MinIO générés avec succès"
echo ""
log_info "Fichier: ${CREDENTIALS_FILE}"
log_info "User: ${MINIO_ROOT_USER}"
log_info "Password: ${MINIO_ROOT_PASSWORD:0:8}..."
log_info "Bucket: ${MINIO_BUCKET}"
echo ""
log_warning "IMPORTANT: Conservez ces credentials en sécurité"
log_warning "Ils seront nécessaires pour accéder à MinIO et créer le bucket"
echo ""

