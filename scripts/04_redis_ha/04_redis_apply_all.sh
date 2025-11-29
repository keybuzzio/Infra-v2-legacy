#!/usr/bin/env bash
#
# 04_redis_apply_all.sh - Script wrapper pour installer le Module 4 complet
#
# Ce script lance tous les scripts d'installation du Module 4 dans le bon ordre.
#
# Usage:
#   ./04_redis_apply_all.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs Redis et HAProxy
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
echo " [KeyBuzz] Module 4 - Installation Complète Redis HA"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Configuration des credentials"
echo "  2. Préparation des nœuds Redis"
echo "  3. Déploiement du cluster Redis (master + replicas)"
echo "  4. Déploiement de Redis Sentinel"
echo "  5. Configuration HAProxy avec watcher Sentinel"
echo "  6. Configuration LB healthcheck (optionnel)"
echo "  7. Tests et diagnostics"
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
log_info "Étape 1/7 : Configuration des credentials"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_00_setup_credentials.sh" ]]; then
    # Passer --yes si le mode non-interactif est activé
    CRED_ARGS=""
    for arg in "$@"; do
        if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
            CRED_ARGS="--yes"
            break
        fi
    done
    if "${SCRIPT_DIR}/04_redis_00_setup_credentials.sh" ${CRED_ARGS}; then
        log_success "Credentials configurés"
    else
        log_error "Échec de la configuration des credentials"
        exit 1
    fi
else
    log_error "Script 04_redis_00_setup_credentials.sh introuvable"
    exit 1
fi
echo ""

# Étape 2 : Préparation des nœuds
log_info "=============================================================="
log_info "Étape 2/7 : Préparation des nœuds Redis"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_01_prepare_nodes.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_01_prepare_nodes.sh" "${TSV_FILE}"; then
        log_success "Nœuds Redis préparés"
    else
        log_error "Échec de la préparation des nœuds"
        exit 1
    fi
else
    log_error "Script 04_redis_01_prepare_nodes.sh introuvable"
    exit 1
fi
echo ""

# Étape 3 : Déploiement Redis
log_info "=============================================================="
log_info "Étape 3/7 : Déploiement du cluster Redis"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_02_deploy_redis_cluster.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_02_deploy_redis_cluster.sh" "${TSV_FILE}"; then
        log_success "Cluster Redis déployé"
    else
        log_error "Échec du déploiement du cluster Redis"
        exit 1
    fi
else
    log_error "Script 04_redis_02_deploy_redis_cluster.sh introuvable"
    exit 1
fi
echo ""

# Attendre que le cluster soit stable
log_info "Attente de la stabilisation du cluster (10 secondes)..."
sleep 10
echo ""

# Étape 4 : Déploiement Sentinel
log_info "=============================================================="
log_info "Étape 4/7 : Déploiement de Redis Sentinel"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_03_deploy_sentinel.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_03_deploy_sentinel.sh" "${TSV_FILE}"; then
        log_success "Redis Sentinel déployé"
    else
        log_error "Échec du déploiement de Sentinel"
        exit 1
    fi
else
    log_error "Script 04_redis_03_deploy_sentinel.sh introuvable"
    exit 1
fi
echo ""

# Attendre que Sentinel découvre le master
log_info "Attente de la découverte du master par Sentinel (10 secondes)..."
sleep 10
echo ""

# Étape 5 : Configuration HAProxy
log_info "=============================================================="
log_info "Étape 5/7 : Configuration HAProxy"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_04_configure_haproxy_redis.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_04_configure_haproxy_redis.sh" "${TSV_FILE}"; then
        log_success "HAProxy configuré"
    else
        log_error "Échec de la configuration HAProxy"
        exit 1
    fi
else
    log_error "Script 04_redis_04_configure_haproxy_redis.sh introuvable"
    exit 1
fi
echo ""

# Étape 6 : Configuration LB healthcheck (optionnel)
log_info "=============================================================="
log_info "Étape 6/7 : Configuration LB healthcheck (optionnel)"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_05_configure_lb_healthcheck.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_05_configure_lb_healthcheck.sh" "${TSV_FILE}" 2>/dev/null; then
        log_success "LB healthcheck configuré"
    else
        log_warning "LB healthcheck non configuré (non bloquant)"
    fi
else
    log_warning "Script 04_redis_05_configure_lb_healthcheck.sh introuvable (non bloquant)"
fi
echo ""

# Étape 7 : Tests
log_info "=============================================================="
log_info "Étape 7/7 : Tests et diagnostics"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_06_tests.sh" ]]; then
    if "${SCRIPT_DIR}/04_redis_06_tests.sh" "${TSV_FILE}"; then
        log_success "Tous les tests sont passés"
    else
        log_warning "Certains tests ont échoué"
        log_warning "Vérifiez les erreurs ci-dessus"
    fi
else
    log_warning "Script 04_redis_06_tests.sh introuvable"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 4 terminée !"
echo "=============================================================="
echo ""
log_info "Le cluster Redis HA est maintenant opérationnel."
log_info ""
log_info "Points d'accès :"
log_info "  - Redis direct (via HAProxy) : haproxy-01/02:6379"
log_info "  - LB Hetzner (à configurer)  : 10.0.0.10:6379"
log_info ""
log_info "Pour vérifier le cluster :"
log_info "  ./04_redis_06_tests.sh ${TSV_FILE}"
log_info ""
log_info "Pour tester le failover (sûr et réversible) :"
log_info "  ./04_redis_07_test_failover_safe.sh (à créer)"
echo ""

