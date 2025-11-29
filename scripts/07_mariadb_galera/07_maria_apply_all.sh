#!/usr/bin/env bash
#
# 07_maria_apply_all.sh - Script master pour l'installation complète du Module 7
#
# Ce script orchestre l'installation complète de MariaDB Galera HA :
#   1. Configuration des credentials
#   2. Préparation des nœuds
#   3. Déploiement du cluster Galera
#   4. Installation ProxySQL
#   5. Tests et diagnostics
#
# Usage:
#   ./07_maria_apply_all.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs
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
echo " [KeyBuzz] Module 7 - Installation Complète MariaDB Galera HA"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Configuration des credentials"
echo "  2. Préparation des nœuds MariaDB"
echo "  3. Déploiement du cluster Galera"
echo "  4. Installation ProxySQL"
echo "  5. Tests et diagnostics"
echo ""

# Confirmation
if [[ "${AUTO_YES}" != "--yes" ]]; then
    # Gérer le mode non-interactif
    NON_INTERACTIVE=false
    for arg in "$@"; do
        if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
            NON_INTERACTIVE=true
            break
        fi
    done
    
    if [[ "${NON_INTERACTIVE}" == "false" ]]; then
        read -p "Continuer ? (o/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
            log_info "Installation annulée"
            exit 0
        fi
    else
        log_info "Mode non-interactif activé, continuation automatique..."
    fi
fi

# Étape 1: Credentials
log_info "============================================================="
log_info "Étape 1/5 : Configuration des credentials"
log_info "============================================================="
"${SCRIPT_DIR}/07_maria_00_setup_credentials.sh"
if [ $? -ne 0 ]; then
    log_error "Échec de la configuration des credentials"
    exit 1
fi
log_success "Credentials configurés"
echo ""

# Étape 2: Préparation des nœuds
log_info "============================================================="
log_info "Étape 2/5 : Préparation des nœuds MariaDB"
log_info "============================================================="
"${SCRIPT_DIR}/07_maria_01_prepare_nodes.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de la préparation des nœuds"
    exit 1
fi
log_success "Nœuds préparés"
echo ""

# Étape 3: Déploiement Galera
log_info "============================================================="
log_info "Étape 3/5 : Déploiement du cluster Galera"
log_info "============================================================="
"${SCRIPT_DIR}/07_maria_02_deploy_galera.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec du déploiement du cluster Galera"
    exit 1
fi
log_success "Cluster Galera déployé"
echo ""

# Attendre la stabilisation
log_info "Attente de la stabilisation du cluster (30 secondes)..."
sleep 30

# Étape 4: Installation ProxySQL
log_info "============================================================="
log_info "Étape 4/5 : Installation ProxySQL"
log_info "============================================================="
"${SCRIPT_DIR}/07_maria_03_install_proxysql.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de l'installation ProxySQL"
    exit 1
fi
log_success "ProxySQL installé"
echo ""

# Étape 5: Tests
log_info "============================================================="
log_info "Étape 5/5 : Tests et diagnostics"
log_info "============================================================="
"${SCRIPT_DIR}/07_maria_04_tests.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Certains tests ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 7 terminée !"
echo "=============================================================="
echo ""
log_info "MariaDB Galera HA est maintenant opérationnel."
log_info ""
log_info "Points d'accès :"
log_info "  - MariaDB Galera: 10.0.0.170, 10.0.0.171, 10.0.0.172:3306"
log_info "  - ProxySQL: Voir servers.tsv pour les IPs ProxySQL"
log_info "  - LB Hetzner (à configurer): 10.0.0.20:3306"
log_info ""
log_info "Pour ERPNext, utiliser :"
log_info "  db_host: 10.0.0.20 (LB Hetzner)"
log_info "  db_port: 3306"
log_info "  db_name: erpnext"
log_info "  db_user: erpnext"
log_info ""
log_info "Pour vérifier MariaDB Galera :"
log_info "  ./07_maria_04_tests.sh ${TSV_FILE}"
echo ""

