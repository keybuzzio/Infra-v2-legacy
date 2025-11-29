#!/usr/bin/env bash
#
# 08_proxysql_apply_all.sh - Script master pour l'installation complète du Module 8
#
# Ce script orchestre l'installation complète de ProxySQL Avancé & Optimisation Galera :
#   1. Génération configuration ProxySQL avancée
#   2. Application configuration ProxySQL
#   3. Optimisation Galera pour ERPNext
#   4. Configuration monitoring
#   5. Tests failover avancés
#
# Usage:
#   ./08_proxysql_apply_all.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 7 installé (MariaDB Galera + ProxySQL basique)
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
echo " [KeyBuzz] Module 8 - Installation Complète ProxySQL Avancé & Optimisation Galera"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Génération configuration ProxySQL avancée"
echo "  2. Application configuration ProxySQL"
echo "  3. Optimisation Galera pour ERPNext"
echo "  4. Configuration monitoring"
echo "  5. Tests failover avancés"
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

# Étape 1: Génération configuration
log_info "============================================================="
log_info "Étape 1/5 : Génération configuration ProxySQL avancée"
log_info "============================================================="
"${SCRIPT_DIR}/08_proxysql_01_generate_config.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de la génération de la configuration"
    exit 1
fi
log_success "Configuration générée"
echo ""

# Étape 2: Application configuration
log_info "============================================================="
log_info "Étape 2/5 : Application configuration ProxySQL"
log_info "============================================================="
"${SCRIPT_DIR}/08_proxysql_02_apply_config.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de l'application de la configuration"
    exit 1
fi
log_success "Configuration appliquée"
echo ""

# Étape 3: Optimisation Galera
log_info "============================================================="
log_info "Étape 3/5 : Optimisation Galera pour ERPNext"
log_info "============================================================="
"${SCRIPT_DIR}/08_proxysql_03_optimize_galera.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de l'optimisation Galera"
    exit 1
fi
log_success "Galera optimisé"
echo ""

# Étape 4: Monitoring
log_info "============================================================="
log_info "Étape 4/5 : Configuration monitoring"
log_info "============================================================="
"${SCRIPT_DIR}/08_proxysql_04_monitoring_setup.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Certaines configurations de monitoring ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
log_success "Monitoring configuré"
echo ""

# Étape 5: Tests (optionnel)
log_info "============================================================="
log_info "Étape 5/5 : Tests failover avancés (optionnel)"
log_info "============================================================="
log_warning "Les tests de failover vont arrêter temporairement des services"
read -p "Exécuter les tests de failover ? (o/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[OoYy]$ ]]; then
    "${SCRIPT_DIR}/08_proxysql_05_failover_tests.sh" "${TSV_FILE}"
    if [ $? -ne 0 ]; then
        log_warning "Certains tests ont échoué"
        log_warning "Vérifiez les erreurs ci-dessus"
    fi
else
    log_info "Tests de failover ignorés"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 8 terminée !"
echo "=============================================================="
echo ""
log_info "ProxySQL Avancé & Optimisation Galera sont maintenant opérationnels."
log_info ""
log_info "Optimisations appliquées:"
log_info "  - ProxySQL: Checks Galera WSREP activés"
log_info "  - ProxySQL: Détection automatique des nœuds DOWN"
log_info "  - ProxySQL: Query rules optimisées pour ERPNext"
log_info "  - Galera: wsrep_provider_options optimisés"
log_info "  - Galera: InnoDB tuning (buffer_pool_size=1G)"
log_info "  - Galera: SST method rsync (stable)"
log_info "  - Galera: Auto recovery activé"
log_info ""
log_info "Monitoring:"
log_info "  - Scripts: /usr/local/bin/monitor_galera.sh"
log_info "  - Scripts: /usr/local/bin/monitor_proxysql.sh"
log_info ""
log_info "Pour vérifier le statut:"
log_info "  ssh root@<ip> /usr/local/bin/monitor_galera.sh"
log_info "  ssh root@<ip> /usr/local/bin/monitor_proxysql.sh"
echo ""

