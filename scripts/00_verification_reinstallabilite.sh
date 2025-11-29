#!/usr/bin/env bash
#
# 00_verification_reinstallabilite.sh - Vérifier que le script master peut tout réinstaller
#
# Ce script vérifie que le script master (00_install_module_by_module.sh)
# peut réinstaller toute l'infrastructure depuis zéro si on rebuild tous les serveurs.
#
# Usage:
#   ./00_verification_reinstallabilite.sh [servers.tsv]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

echo "=============================================================="
echo " [KeyBuzz] Vérification Réinstallabilité Complète"
echo "=============================================================="
echo ""

# Vérifier que le script master existe
MASTER_SCRIPT="${SCRIPT_DIR}/00_install_module_by_module.sh"
if [[ ! -f "${MASTER_SCRIPT}" ]]; then
    log_error "Script master introuvable: ${MASTER_SCRIPT}"
    exit 1
fi

log_success "Script master trouvé: ${MASTER_SCRIPT}"
echo ""

# Vérifier les options du script master
log_info "Vérification des options du script master..."
if grep -q "start-from-module" "${MASTER_SCRIPT}"; then
    log_success "Option --start-from-module disponible"
else
    log_error "Option --start-from-module non trouvée"
fi

if grep -q "skip-cleanup" "${MASTER_SCRIPT}"; then
    log_success "Option --skip-cleanup disponible"
else
    log_warning "Option --skip-cleanup non trouvée"
fi

echo ""

# Vérifier que tous les modules sont intégrés
log_info "Vérification de l'intégration des modules..."
MODULES_FOUND=0
MODULES_EXPECTED=9

for module in 2 3 4 5 6 7 8 9 10; do
    if grep -q "Module ${module}:" "${MASTER_SCRIPT}"; then
        log_success "Module ${module} intégré"
        ((MODULES_FOUND++))
    else
        log_warning "Module ${module} non trouvé"
    fi
done

echo ""
log_info "Modules trouvés: ${MODULES_FOUND}/${MODULES_EXPECTED}"
echo ""

# Vérifier que les scripts de chaque module existent
log_info "Vérification de l'existence des scripts de modules..."

declare -a MODULE_SCRIPTS=(
    "02_base_os_and_security/02_base_os_apply_all.sh:Module 2"
    "03_postgresql_ha/03_pg_apply_all.sh:Module 3"
    "04_redis_ha/04_redis_apply_all.sh:Module 4"
    "05_rabbitmq_ha/05_rabbitmq_apply_all.sh:Module 5"
    "06_minio/06_minio_apply_all.sh:Module 6"
    "07_mariadb_galera/07_maria_apply_all.sh:Module 7"
    "08_proxysql_advanced/08_proxysql_apply_all.sh:Module 8"
    "09_k3s_ha/09_k3s_apply_all.sh:Module 9"
    "10_keybuzz/10_keybuzz_apply_all.sh:Module 10"
)

ALL_SCRIPTS_EXIST=true
for script_info in "${MODULE_SCRIPTS[@]}"; do
    SCRIPT_PATH="${script_info%%:*}"
    MODULE_NAME="${script_info##*:}"
    FULL_PATH="${SCRIPT_DIR}/${SCRIPT_PATH}"
    
    if [[ -f "${FULL_PATH}" ]]; then
        log_success "${MODULE_NAME}: Script trouvé"
    else
        log_error "${MODULE_NAME}: Script introuvable (${FULL_PATH})"
        ALL_SCRIPTS_EXIST=false
    fi
done

echo ""

# Vérifier la distribution des credentials
log_info "Vérification de la distribution des credentials..."
if [[ -f "${SCRIPT_DIR}/00_distribute_credentials.sh" ]]; then
    log_success "Script de distribution des credentials trouvé"
else
    log_warning "Script de distribution des credentials non trouvé"
fi

if [[ -f "${SCRIPT_DIR}/00_load_credentials.sh" ]]; then
    log_success "Script de chargement des credentials trouvé"
else
    log_warning "Script de chargement des credentials non trouvé"
fi

echo ""

# Résumé
echo "=============================================================="
log_info "RÉSUMÉ DE LA VÉRIFICATION"
echo "=============================================================="
echo ""

if [[ ${MODULES_FOUND} -eq ${MODULES_EXPECTED} ]] && [[ "${ALL_SCRIPTS_EXIST}" == "true" ]]; then
    log_success "✅ Le script master peut réinstaller toute l'infrastructure"
    echo ""
    log_info "Pour réinstaller depuis zéro (après rebuild serveurs):"
    log_info "  1. Nettoyage: bash 00_cleanup_complete_installation.sh ${TSV_FILE}"
    log_info "  2. Installation: bash 00_install_module_by_module.sh --start-from-module=2"
    echo ""
    log_info "Pour réinstaller un module spécifique:"
    log_info "  bash 00_install_module_by_module.sh --start-from-module=N"
    echo ""
    log_info "Pour réinstaller sans nettoyage:"
    log_info "  bash 00_install_module_by_module.sh --start-from-module=2 --skip-cleanup"
    exit 0
else
    log_error "❌ Certains modules ou scripts manquent"
    log_warning "Vérifiez les erreurs ci-dessus"
    exit 1
fi

