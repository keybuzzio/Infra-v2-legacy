#!/usr/bin/env bash
#
# 06_minio_03_configure_client.sh - Configuration client MinIO (mc)
#
# Ce script installe et configure le client MinIO (mc) sur install-01,
# crée le bucket par défaut et teste l'accès.
#
# Usage:
#   ./06_minio_03_configure_client.sh [servers.tsv]
#
# Prérequis:
#   - Script 06_minio_02_install_single.sh exécuté
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/minio.env"

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
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 6 - Configuration Client MinIO (mc)"
echo "=============================================================="
echo ""

# Trouver l'IP du premier nœud MinIO
MINIO_IP=""
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" == "prod" ]] && [[ "${ROLE}" == "storage" ]] && [[ "${SUBROLE}" == "minio" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        MINIO_IP="${IP_PRIVEE}"
        break
    fi
done
exec 3<&-

if [[ -z "${MINIO_IP}" ]]; then
    log_error "Aucun nœud MinIO trouvé dans servers.tsv"
    exit 1
fi

log_info "MinIO détecté sur: ${MINIO_IP}:9000"
echo ""

# Installer le client mc si nécessaire
if ! command -v mc >/dev/null 2>&1; then
    log_info "Installation du client MinIO (mc)..."
    
    if [[ -f /usr/local/bin/mc ]]; then
        log_info "Client mc déjà présent"
    else
        curl -s -O https://dl.min.io/client/mc/release/linux-amd64/mc
        chmod +x mc
        mv mc /usr/local/bin/
        log_success "Client mc installé"
    fi
else
    log_success "Client mc déjà installé"
fi
echo ""

# Configurer l'alias MinIO
log_info "Configuration de l'alias MinIO..."

# Supprimer l'alias existant s'il existe
mc alias remove minio 2>/dev/null || true

# Créer le nouvel alias
if mc alias set minio "http://${MINIO_IP}:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"; then
    log_success "Alias MinIO configuré"
else
    log_error "Échec de la configuration de l'alias"
    exit 1
fi

# Vérifier la connexion
log_info "Vérification de la connexion..."
if mc admin info minio >/dev/null 2>&1; then
    log_success "Connexion à MinIO réussie"
else
    log_warning "Connexion à MinIO non vérifiée (peut être normal au démarrage)"
fi
echo ""

# Créer le bucket par défaut
log_info "Création du bucket '${MINIO_BUCKET}'..."

if mc mb "minio/${MINIO_BUCKET}" 2>/dev/null; then
    log_success "Bucket '${MINIO_BUCKET}' créé"
elif mc ls "minio/${MINIO_BUCKET}" >/dev/null 2>&1; then
    log_info "Bucket '${MINIO_BUCKET}' existe déjà"
else
    log_warning "Impossible de créer ou vérifier le bucket (peut nécessiter quelques secondes)"
fi

# Activer le versioning sur le bucket (bonne pratique)
log_info "Activation du versioning sur le bucket..."
mc version enable "minio/${MINIO_BUCKET}" 2>/dev/null && \
    log_success "Versioning activé" || \
    log_warning "Impossible d'activer le versioning (non bloquant)"

echo ""

# Test d'upload/download
log_info "Test d'upload/download..."

TEST_FILE="/tmp/minio_test_$(date +%s).txt"
echo "Test MinIO $(date)" > "${TEST_FILE}"

if mc cp "${TEST_FILE}" "minio/${MINIO_BUCKET}/test/" 2>/dev/null; then
    log_success "Upload réussi"
    
    # Vérifier que le fichier existe
    if mc ls "minio/${MINIO_BUCKET}/test/" | grep -q "$(basename ${TEST_FILE})"; then
        log_success "Fichier visible dans MinIO"
        
        # Télécharger le fichier
        DOWNLOAD_FILE="/tmp/minio_test_download.txt"
        if mc cp "minio/${MINIO_BUCKET}/test/$(basename ${TEST_FILE})" "${DOWNLOAD_FILE}" 2>/dev/null; then
            log_success "Download réussi"
            rm -f "${DOWNLOAD_FILE}"
        fi
    fi
    
    # Nettoyer
    mc rm "minio/${MINIO_BUCKET}/test/$(basename ${TEST_FILE})" 2>/dev/null || true
    rm -f "${TEST_FILE}"
else
    log_warning "Test d'upload échoué (peut nécessiter quelques secondes)"
    rm -f "${TEST_FILE}"
fi

echo ""
echo "=============================================================="
log_success "✅ Configuration du client MinIO terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Client mc: Installé et configuré"
log_info "  - Alias: minio → http://${MINIO_IP}:9000"
log_info "  - Bucket: ${MINIO_BUCKET}"
log_info ""
log_info "Commandes utiles:"
log_info "  mc ls minio/${MINIO_BUCKET}/"
log_info "  mc cp <file> minio/${MINIO_BUCKET}/"
log_info "  mc admin info minio"
log_info ""
log_info "Prochaine étape: Exécuter les tests"
log_info "  ./06_minio_04_tests.sh ${TSV_FILE}"
echo ""

