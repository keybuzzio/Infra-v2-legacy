#!/usr/bin/env bash
#
# 03_pg_05_install_pgvector.sh - Installation de l'extension pgvector
#
# Ce script installe l'extension pgvector sur le cluster PostgreSQL HA.
#
# Usage:
#   ./03_pg_05_install_pgvector.sh
#
# Prérequis:
#   - Cluster Patroni installé et fonctionnel
#   - HAProxy installé et fonctionnel
#   - Credentials configurés
#   - psql installé sur install-01
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"

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

# Vérifier les prérequis
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    log_info "Exécutez d'abord: ./03_pg_00_setup_credentials.sh"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Vérifier que psql est installé
if ! command -v psql >/dev/null 2>&1; then
    log_info "Installation de postgresql-client..."
    apt-get update -y
    apt-get install -y postgresql-client
fi

# LB Hetzner IP (10.0.0.10)
LB_IP="10.0.0.10"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 3 - Installation pgvector"
echo "=============================================================="
echo ""
echo "Database     : ${POSTGRES_DB}"
echo "Cluster      : ${PATRONI_CLUSTER_NAME}"
echo ""

# Vérifier la connectivité au cluster
log_info "Vérification de la connectivité au cluster..."

CONNECTION_STRING="postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@${LB_IP}:5432/${POSTGRES_DB}"

if ! psql "${CONNECTION_STRING}" -c "SELECT version();" >/dev/null 2>&1; then
    log_error "Impossible de se connecter au cluster PostgreSQL"
    log_info "Vérifiez que :"
    log_info "  - Le cluster Patroni est démarré"
    log_info "  - HAProxy est configuré et fonctionnel"
    log_info "  - Le LB Hetzner 10.0.0.10 est configuré"
    exit 1
fi

log_success "Connectivité au cluster OK"
echo ""

# Vérifier si pgvector est déjà installé
log_info "Vérification de l'extension pgvector..."

if psql "${CONNECTION_STRING}" -t -c "SELECT extname FROM pg_extension WHERE extname='vector';" 2>/dev/null | grep -q vector; then
    log_warning "L'extension pgvector est déjà installée"
    read -p "Voulez-vous la réinstaller ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation annulée"
        exit 0
    fi
    log_info "Suppression de l'extension existante..."
    psql "${CONNECTION_STRING}" -c "DROP EXTENSION IF EXISTS vector CASCADE;" || true
fi

# Installer pgvector
log_info "Installation de l'extension pgvector..."

if psql "${CONNECTION_STRING}" -c "CREATE EXTENSION IF NOT EXISTS vector;" 2>&1; then
    log_success "Extension pgvector installée avec succès"
else
    log_error "Échec de l'installation de pgvector"
    log_warning "Note: L'image Docker Patroni doit inclure pgvector"
    log_warning "Si l'image ne l'inclut pas, vous devrez :"
    log_warning "  1. Utiliser une image avec pgvector pré-installé"
    log_warning "  2. Ou compiler pgvector dans le conteneur"
    exit 1
fi

# Vérifier l'installation
log_info "Vérification de l'installation..."

VECTOR_VERSION=$(psql "${CONNECTION_STRING}" -t -c "SELECT extversion FROM pg_extension WHERE extname='vector';" 2>/dev/null | tr -d ' ')

if [[ -n "${VECTOR_VERSION}" ]]; then
    log_success "pgvector version ${VECTOR_VERSION} installé"
else
    log_error "Impossible de vérifier la version de pgvector"
    exit 1
fi

# Test de l'extension
log_info "Test de l'extension pgvector..."

if psql "${CONNECTION_STRING}" -c "SELECT vector('[1,2,3]'::float[]);" >/dev/null 2>&1; then
    log_success "Test de pgvector réussi"
else
    log_warning "Le test de pgvector a échoué, mais l'extension est installée"
fi

echo ""
echo "=============================================================="
log_success "pgvector installé avec succès !"
echo "=============================================================="
echo ""
log_info "L'extension pgvector est maintenant disponible sur tout le cluster."
log_info "Vous pouvez l'utiliser pour stocker des embeddings vectoriels."
echo ""


