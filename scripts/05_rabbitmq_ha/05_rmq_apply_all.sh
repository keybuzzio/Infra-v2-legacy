#!/usr/bin/env bash
#
# 05_rmq_apply_all.sh - Script wrapper pour installer le Module 5 complet
#
# Ce script lance tous les scripts d'installation du Module 5 dans le bon ordre.
#
# Usage:
#   ./05_rmq_apply_all.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs RabbitMQ et HAProxy
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
echo " [KeyBuzz] Module 5 - Installation Complète RabbitMQ HA"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Configuration des credentials"
echo "  2. Préparation des nœuds RabbitMQ"
echo "  3. Déploiement du cluster RabbitMQ (3 nœuds)"
echo "  4. Configuration HAProxy"
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
if [[ -f "${SCRIPT_DIR}/05_rmq_00_setup_credentials.sh" ]]; then
    if "${SCRIPT_DIR}/05_rmq_00_setup_credentials.sh"; then
        log_success "Credentials configurés"
    else
        log_error "Échec de la configuration des credentials"
        exit 1
    fi
else
    log_error "Script 05_rmq_00_setup_credentials.sh introuvable"
    exit 1
fi
echo ""

# Étape 2 : Préparation des nœuds
log_info "=============================================================="
log_info "Étape 2/5 : Préparation des nœuds RabbitMQ"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/05_rmq_01_prepare_nodes.sh" ]]; then
    if "${SCRIPT_DIR}/05_rmq_01_prepare_nodes.sh" "${TSV_FILE}"; then
        log_success "Nœuds RabbitMQ préparés"
    else
        log_error "Échec de la préparation des nœuds"
        exit 1
    fi
else
    log_error "Script 05_rmq_01_prepare_nodes.sh introuvable"
    exit 1
fi
echo ""

# Étape 3 : Déploiement du cluster
log_info "=============================================================="
log_info "Étape 3/5 : Déploiement du cluster RabbitMQ"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/05_rmq_02_deploy_cluster.sh" ]]; then
    if "${SCRIPT_DIR}/05_rmq_02_deploy_cluster.sh" "${TSV_FILE}"; then
        log_success "Cluster RabbitMQ déployé"
    else
        log_error "Échec du déploiement du cluster RabbitMQ"
        exit 1
    fi
else
    log_error "Script 05_rmq_02_deploy_cluster.sh introuvable"
    exit 1
fi
echo ""

# Attendre que le cluster soit stable
log_info "Attente de la stabilisation du cluster (10 secondes)..."
sleep 10
echo ""

# Étape 4 : Configuration HAProxy
log_info "=============================================================="
log_info "Étape 4/5 : Configuration HAProxy"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/05_rmq_03_configure_haproxy.sh" ]]; then
    if "${SCRIPT_DIR}/05_rmq_03_configure_haproxy.sh" "${TSV_FILE}"; then
        log_success "HAProxy configuré"
    else
        log_error "Échec de la configuration HAProxy"
        exit 1
    fi
else
    log_error "Script 05_rmq_03_configure_haproxy.sh introuvable"
    exit 1
fi
echo ""

# Étape 5 : Tests
log_info "=============================================================="
log_info "Étape 5/5 : Tests et diagnostics"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/05_rmq_04_tests.sh" ]]; then
    if "${SCRIPT_DIR}/05_rmq_04_tests.sh" "${TSV_FILE}"; then
        log_success "Tous les tests sont passés"
    else
        log_warning "Certains tests ont échoué"
        log_warning "Vérifiez les erreurs ci-dessus"
    fi
else
    log_warning "Script 05_rmq_04_tests.sh introuvable"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 5 terminée !"
echo "=============================================================="
echo ""
log_info "Le cluster RabbitMQ HA est maintenant opérationnel."
log_info ""
log_info "Points d'accès :"
log_info "  - RabbitMQ direct (via HAProxy) : haproxy-01/02:5672"
log_info "  - LB Hetzner (à configurer)      : 10.0.0.10:5672"
log_info ""
log_info "Pour vérifier le cluster :"
log_info "  ./05_rmq_04_tests.sh ${TSV_FILE}"
log_info ""
log_info "Pour tester le failover (sûr et réversible) :"
log_info "  Arrêter un nœud RabbitMQ et vérifier que le cluster continue"
echo ""

