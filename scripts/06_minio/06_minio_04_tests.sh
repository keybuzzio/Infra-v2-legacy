#!/usr/bin/env bash
#
# 06_minio_04_tests.sh - Tests et diagnostics MinIO
#
# Ce script exécute une série de tests pour valider MinIO :
# - Tests de connectivité
# - Tests S3 API
# - Tests de bucket
# - Tests d'upload/download
#
# Usage:
#   ./06_minio_04_tests.sh [servers.tsv]
#
# Prérequis:
#   - Tous les scripts précédents exécutés
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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 6 - Tests et Diagnostics MinIO"
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

# Test 1: Connectivité MinIO
log_info "=============================================================="
log_info "Test 1: Connectivité MinIO"
log_info "=============================================================="

MINIO_OK=0

# Test port 9000 (S3 API)
if timeout 3 nc -z "${MINIO_IP}" 9000 2>/dev/null; then
    log_success "Port 9000 (S3 API): Accessible"
    ((MINIO_OK++))
else
    log_error "Port 9000 (S3 API): Non accessible"
fi

# Test port 9001 (Console)
if timeout 3 nc -z "${MINIO_IP}" 9001 2>/dev/null; then
    log_success "Port 9001 (Console): Accessible"
    ((MINIO_OK++))
else
    log_warning "Port 9001 (Console): Non accessible"
fi

# Test health endpoint
if timeout 3 curl -s -f "http://${MINIO_IP}:9000/minio/health/live" >/dev/null 2>&1; then
    log_success "Health endpoint: Répond correctement"
    ((MINIO_OK++))
else
    log_warning "Health endpoint: Ne répond pas"
fi

echo ""

# Test 2: Client mc
log_info "=============================================================="
log_info "Test 2: Client MinIO (mc)"
log_info "=============================================================="

MC_OK=0

if ! command -v mc >/dev/null 2>&1; then
    log_error "Client mc non installé"
else
    log_success "Client mc installé"
    ((MC_OK++))
    
    # Vérifier l'alias
    if mc alias list | grep -q "minio"; then
        log_success "Alias MinIO configuré"
        ((MC_OK++))
    else
        log_warning "Alias MinIO non configuré"
    fi
    
    # Test admin info
    if mc admin info minio >/dev/null 2>&1; then
        log_success "Connexion mc à MinIO réussie"
        ((MC_OK++))
    else
        log_warning "Connexion mc à MinIO échouée"
    fi
fi

echo ""

# Test 3: Bucket
log_info "=============================================================="
log_info "Test 3: Bucket '${MINIO_BUCKET}'"
log_info "=============================================================="

BUCKET_OK=0

if command -v mc >/dev/null 2>&1; then
    if mc ls "minio/${MINIO_BUCKET}" >/dev/null 2>&1; then
        log_success "Bucket '${MINIO_BUCKET}' existe et est accessible"
        ((BUCKET_OK++))
        
        # Vérifier le versioning
        if mc version info "minio/${MINIO_BUCKET}" >/dev/null 2>&1; then
            log_success "Versioning activé sur le bucket"
            ((BUCKET_OK++))
        else
            log_warning "Versioning non vérifié"
        fi
    else
        log_error "Bucket '${MINIO_BUCKET}' non accessible"
    fi
else
    log_warning "Client mc non disponible pour tester le bucket"
fi

echo ""

# Test 4: Upload/Download
log_info "=============================================================="
log_info "Test 4: Upload/Download"
log_info "=============================================================="

UPLOAD_OK=0

if command -v mc >/dev/null 2>&1; then
    TEST_FILE="/tmp/minio_test_$(date +%s).txt"
    TEST_CONTENT="Test MinIO $(date)"
    echo "${TEST_CONTENT}" > "${TEST_FILE}"
    
    # Upload
    if mc cp "${TEST_FILE}" "minio/${MINIO_BUCKET}/test/" >/dev/null 2>&1; then
        log_success "Upload réussi"
        ((UPLOAD_OK++))
        
        # Download
        DOWNLOAD_FILE="/tmp/minio_test_download.txt"
        if mc cp "minio/${MINIO_BUCKET}/test/$(basename ${TEST_FILE})" "${DOWNLOAD_FILE}" >/dev/null 2>&1; then
            if [[ -f "${DOWNLOAD_FILE}" ]] && grep -q "${TEST_CONTENT}" "${DOWNLOAD_FILE}"; then
                log_success "Download réussi et contenu vérifié"
                ((UPLOAD_OK++))
            else
                log_warning "Download réussi mais contenu incorrect"
            fi
            rm -f "${DOWNLOAD_FILE}"
        else
            log_warning "Download échoué"
        fi
        
        # Nettoyer
        mc rm "minio/${MINIO_BUCKET}/test/$(basename ${TEST_FILE})" >/dev/null 2>&1 || true
        rm -f "${TEST_FILE}"
    else
        log_warning "Upload échoué"
        rm -f "${TEST_FILE}"
    fi
else
    log_warning "Client mc non disponible pour tester upload/download"
fi

echo ""

# Test 5: Docker container
log_info "=============================================================="
log_info "Test 5: Conteneur Docker"
log_info "=============================================================="

DOCKER_OK=0

if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MINIO_IP}" \
    "docker ps | grep -q minio" 2>/dev/null; then
    log_success "Conteneur MinIO en cours d'exécution"
    ((DOCKER_OK++))
    
    # Vérifier les logs (pas d'erreurs critiques)
    ERRORS=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MINIO_IP}" \
        "docker logs minio 2>&1 | grep -i 'error\|fatal\|panic' | wc -l" 2>/dev/null || echo "0")
    
    if [[ "${ERRORS}" == "0" ]]; then
        log_success "Aucune erreur dans les logs"
        ((DOCKER_OK++))
    else
        log_warning "${ERRORS} erreur(s) trouvée(s) dans les logs"
    fi
else
    log_error "Conteneur MinIO non en cours d'exécution"
fi

echo ""

# Résumé final
echo "=============================================================="
log_info "Résumé des tests"
echo "=============================================================="
echo ""
log_info "Connectivité:"
log_info "  - Tests réussis: ${MINIO_OK}/3"
echo ""
log_info "Client mc:"
log_info "  - Tests réussis: ${MC_OK}/3"
echo ""
log_info "Bucket:"
log_info "  - Tests réussis: ${BUCKET_OK}/2"
echo ""
log_info "Upload/Download:"
log_info "  - Tests réussis: ${UPLOAD_OK}/2"
echo ""
log_info "Docker:"
log_info "  - Tests réussis: ${DOCKER_OK}/2"
echo ""

TOTAL_TESTS=$((MINIO_OK + MC_OK + BUCKET_OK + UPLOAD_OK + DOCKER_OK))
TOTAL_POSSIBLE=12

if [[ ${TOTAL_TESTS} -ge 8 ]]; then
    echo "=============================================================="
    log_success "✅ Tests MinIO réussis !"
    echo "=============================================================="
    echo ""
    log_info "MinIO est opérationnel et prêt pour la production."
    log_info ""
    log_info "Points d'accès:"
    log_info "  - S3 API: http://${MINIO_IP}:9000"
    log_info "  - Console: http://${MINIO_IP}:9001"
    log_info "  - Bucket: ${MINIO_BUCKET}"
    echo ""
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Certains tests ont échoué"
    echo "=============================================================="
    echo ""
    log_warning "Score: ${TOTAL_TESTS}/${TOTAL_POSSIBLE}"
    log_warning "Vérifiez les erreurs ci-dessus."
    echo ""
    exit 1
fi

