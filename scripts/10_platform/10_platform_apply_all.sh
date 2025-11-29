#!/usr/bin/env bash
#
# 10_platform_apply_all.sh - Script master Module 10 Platform
#
# Ce script orchestre l'installation complète du Module 10 Platform (KeyBuzz).
#
# Usage:
#   ./10_platform_apply_all.sh [servers.tsv] [--yes]
#
# Options:
#   --yes : Mode non-interactif (sauter les confirmations)
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Modules 3-6 installés (services backend)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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
echo " [KeyBuzz] Module 10 Platform - Installation Complète"
echo "=============================================================="
echo ""
echo "Date de démarrage: $(date)"
echo ""

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Confirmation
if [[ "${AUTO_YES}" != "--yes" ]]; then
    log_warning "Ce script va installer Platform KeyBuzz (API, UI, My) sur K3s"
    log_warning "Architecture: Deployment + Service ClusterIP + Ingress"
    read -p "Continuer ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation annulée"
        exit 0
    fi
fi

# Fonction pour exécuter un script
run_script() {
    local script_name=$1
    local script_path="${SCRIPT_DIR}/${script_name}"
    local description=$2
    local extra_args="${3:-}"
    
    if [[ ! -f "${script_path}" ]]; then
        log_error "Script introuvable: ${script_path}"
        return 1
    fi
    
    if [[ ! -x "${script_path}" ]]; then
        chmod +x "${script_path}"
    fi
    
    log_info "=============================================================="
    log_info "${description}"
    log_info "=============================================================="
    echo ""
    
    if [[ -n "${extra_args}" ]]; then
        if "${script_path}" "${TSV_FILE}" "${extra_args}"; then
            log_success "✅ ${description} terminé"
            echo ""
            return 0
        else
            log_error "❌ ${description} a échoué"
            echo ""
            return 1
        fi
    else
        if "${script_path}" "${TSV_FILE}"; then
            log_success "✅ ${description} terminé"
            echo ""
            return 0
        else
            log_error "❌ ${description} a échoué"
            echo ""
            return 1
        fi
    fi
}

# Exécution des scripts dans l'ordre
ERRORS=0

# 1. Setup credentials
if ! run_script "10_platform_00_setup_credentials.sh" "Configuration Credentials Platform" "${AUTO_YES}"; then
    ((ERRORS++))
fi

# 2. Déploiement API
if ! run_script "10_platform_01_deploy_api.sh" "Déploiement Platform API"; then
    ((ERRORS++))
fi

# 3. Déploiement UI
if ! run_script "10_platform_02_deploy_ui.sh" "Déploiement Platform UI"; then
    ((ERRORS++))
fi

# 4. Déploiement My Portal
if ! run_script "10_platform_03_deploy_my.sh" "Déploiement My Portal"; then
    ((ERRORS++))
fi

# 5. Configuration Ingress
if ! run_script "10_platform_04_configure_ingress.sh" "Configuration Ingress"; then
    ((ERRORS++))
fi

# Résumé final
echo ""
echo "=============================================================="
echo " Résumé de l'Installation"
echo "=============================================================="
echo ""
echo "Date de fin: $(date)"
echo ""

if [[ ${ERRORS} -eq 0 ]]; then
    log_success "✅ Module 10 Platform installé avec succès"
    echo ""
    log_info "Composants déployés:"
    log_info "  - Platform API (Deployment, Service ClusterIP, Ingress)"
    log_info "  - Platform UI (Deployment, Service ClusterIP, Ingress)"
    log_info "  - My Portal (Deployment, Service ClusterIP, Ingress)"
    echo ""
    log_info "URLs configurées:"
    log_info "  - https://platform-api.keybuzz.io"
    log_info "  - https://platform.keybuzz.io"
    log_info "  - https://my.keybuzz.io"
    echo ""
    log_warning "⚠️  Actions requises:"
    log_info "  1. Configurer les DNS pour pointer vers les LB Hetzner"
    log_info "  2. Vérifier les certificats TLS sur les LB Hetzner"
    log_info "  3. Exécuter: ./validate_module10_platform.sh"
    echo ""
    exit 0
else
    log_error "❌ Module 10 Platform installé avec ${ERRORS} erreur(s)"
    echo ""
    log_warning "Vérifiez les logs ci-dessus pour plus de détails"
    echo ""
    exit 1
fi

