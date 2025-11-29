#!/usr/bin/env bash
#
# 06_minio_apply_all.sh - Script wrapper pour installer le Module 6 complet
#
# Ce script lance tous les scripts d'installation du Module 6 dans le bon ordre.
#
# Usage:
#   ./06_minio_apply_all.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs MinIO
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

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
echo " [KeyBuzz] Module 6 - Installation Complète MinIO S3 HA"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Configuration des credentials"
echo "  2. Préparation des nœuds MinIO"
echo "  3. Installation MinIO mono-nœud"
echo "  4. Configuration client mc et création du bucket"
echo "  5. Tests et diagnostics"
# Gérer le mode non-interactif
NON_INTERACTIVE=false
for arg in "$@"; do
    if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
        NON_INTERACTIVE=true
        break
    fi
done

if [[ "${NON_INTERACTIVE}" == "false" ]]; then
    echo ""
    read -p "Continuer ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation annulée"
        exit 0
    fi
else
    log_info "Mode non-interactif activé, continuation automatique..."
fi

echo ""

# Étape 1 : Credentials
log_info "=============================================================="
log_info "Étape 1/5 : Configuration des credentials"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio_00_setup_credentials.sh" ]]; then
    if "${SCRIPT_DIR}/06_minio_00_setup_credentials.sh"; then
        log_success "Credentials configurés"
    else
        log_error "Échec de la configuration des credentials"
        exit 1
    fi
else
    log_error "Script 06_minio_00_setup_credentials.sh introuvable"
    exit 1
fi
echo ""

# Étape 2 : Préparation des nœuds
log_info "=============================================================="
log_info "Étape 2/5 : Préparation des nœuds MinIO"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio_01_prepare_nodes.sh" ]]; then
    if "${SCRIPT_DIR}/06_minio_01_prepare_nodes.sh" "${TSV_FILE}"; then
        log_success "Nœuds MinIO préparés"
    else
        log_error "Échec de la préparation des nœuds"
        exit 1
    fi
else
    log_error "Script 06_minio_01_prepare_nodes.sh introuvable"
    exit 1
fi
echo ""

# Étape 3 : Installation MinIO Cluster Distributed
log_info "=============================================================="
log_info "Étape 3/5 : Installation MinIO Cluster Distributed (3 nœuds)"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio_01_deploy_minio_distributed_v2_FINAL.sh" ]]; then
    if "${SCRIPT_DIR}/06_minio_01_deploy_minio_distributed_v2_FINAL.sh" "${TSV_FILE}"; then
        log_success "MinIO Cluster Distributed installé"
    else
        log_error "Échec de l'installation du cluster MinIO"
        exit 1
    fi
else
    log_error "Script 06_minio_01_deploy_minio_distributed_v2_FINAL.sh introuvable"
    exit 1
fi
echo ""

# Attendre que MinIO soit stable
log_info "Attente de la stabilisation de MinIO (10 secondes)..."
sleep 10
echo ""

# Étape 4 : Configuration client
log_info "=============================================================="
log_info "Étape 4/5 : Configuration client mc"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio_03_configure_client.sh" ]]; then
    if "${SCRIPT_DIR}/06_minio_03_configure_client.sh" "${TSV_FILE}"; then
        log_success "Client mc configuré"
    else
        log_warning "Échec de la configuration du client mc"
        log_warning "Vous pouvez le configurer manuellement plus tard"
    fi
else
    log_warning "Script 06_minio_03_configure_client.sh introuvable"
fi
echo ""

# Étape 5 : Tests
log_info "=============================================================="
log_info "Étape 5/5 : Tests et diagnostics"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio_04_tests.sh" ]]; then
    if "${SCRIPT_DIR}/06_minio_04_tests.sh" "${TSV_FILE}"; then
        log_success "Tous les tests sont passés"
    else
        log_warning "Certains tests ont échoué"
        log_warning "Vérifiez les erreurs ci-dessus"
    fi
else
    log_warning "Script 06_minio_04_tests.sh introuvable"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 6 terminée !"
echo "=============================================================="
echo ""
log_info "MinIO S3 est maintenant opérationnel."
log_info ""
log_info "Points d'accès :"
log_info "  - S3 API: http://<minio-ip>:9000"
log_info "  - Console: http://<minio-ip>:9001"
log_info "  - Bucket: ${MINIO_BUCKET:-keybuzz-backups}"
log_info ""
log_info "Pour vérifier MinIO :"
log_info "  ./06_minio_04_tests.sh ${TSV_FILE}"
log_info ""
log_info "Pour migrer vers un cluster HA (futur) :"
log_info "  ./06_minio_03_install_cluster.sh ${TSV_FILE}"
echo ""

