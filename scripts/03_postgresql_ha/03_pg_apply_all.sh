#!/usr/bin/env bash
#
# 03_pg_apply_all.sh - Script wrapper pour installer le Module 3 complet
#
# Ce script lance tous les scripts d'installation du Module 3 dans le bon ordre.
#
# Usage:
#   ./03_pg_apply_all.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs
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
echo " [KeyBuzz] Module 3 - Installation Complète PostgreSQL HA"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Configuration des credentials"
echo "  2. Cluster Patroni RAFT (3 nœuds)"
echo "  3. HAProxy sur haproxy-01/02"
echo "  4. PgBouncer sur haproxy-01/02"
echo "  5. Extension pgvector"
echo "  6. Diagnostics et tests"
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
log_info "Étape 1/6 : Configuration des credentials"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_00_setup_credentials.sh" ]]; then
    # Passer --yes si le mode non-interactif est activé
    CRED_ARGS=""
    for arg in "$@"; do
        if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
            CRED_ARGS="--yes"
            break
        fi
    done
    if "${SCRIPT_DIR}/03_pg_00_setup_credentials.sh" ${CRED_ARGS}; then
        log_success "Credentials configurés"
    else
        log_error "Échec de la configuration des credentials"
        exit 1
    fi
else
    log_error "Script 03_pg_00_setup_credentials.sh introuvable"
    exit 1
fi
echo ""

# Étape 2 : Patroni Cluster
log_info "=============================================================="
log_info "Étape 2/6 : Installation du cluster Patroni RAFT"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" ]]; then
    # Activer le mode non-interactif pour la vérification filesystem si --yes est passé
    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        export SKIP_FS_CHECK="true"
    fi
    if "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" "${TSV_FILE}"; then
        log_success "Cluster Patroni installé"
    else
        log_error "Échec de l'installation du cluster Patroni"
        exit 1
    fi
    unset SKIP_FS_CHECK
else
    log_error "Script 03_pg_02_install_patroni_cluster.sh introuvable"
    exit 1
fi
echo ""

# Attendre que le cluster soit stable et initialisé
log_info "Attente de la stabilisation et initialisation du cluster (60 secondes)..."
sleep 60

# Vérifier que le cluster est opérationnel
log_info "Vérification du statut du cluster..."
if ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1 | grep -q Leader"; then
    log_success "Cluster Patroni opérationnel avec Leader élu"
else
    log_warning "Le cluster n'a pas encore de Leader, attente supplémentaire..."
    sleep 30
fi
echo ""

# Étape 3 : HAProxy
log_info "=============================================================="
log_info "Étape 3/6 : Installation HAProxy"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_03_install_haproxy_db_lb.sh" ]]; then
    if "${SCRIPT_DIR}/03_pg_03_install_haproxy_db_lb.sh" "${TSV_FILE}"; then
        log_success "HAProxy installé"
    else
        log_error "Échec de l'installation de HAProxy"
        exit 1
    fi
else
    log_error "Script 03_pg_03_install_haproxy_db_lb.sh introuvable"
    exit 1
fi
echo ""

# Étape 4 : PgBouncer
log_info "=============================================================="
log_info "Étape 4/6 : Installation PgBouncer"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_04_install_pgbouncer.sh" ]]; then
    if "${SCRIPT_DIR}/03_pg_04_install_pgbouncer.sh" "${TSV_FILE}"; then
        log_success "PgBouncer installé"
    else
        log_error "Échec de l'installation de PgBouncer"
        exit 1
    fi
else
    log_error "Script 03_pg_04_install_pgbouncer.sh introuvable"
    exit 1
fi
echo ""

# Étape 5 : pgvector
log_info "=============================================================="
log_info "Étape 5/6 : Installation pgvector"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_05_install_pgvector.sh" ]]; then
    if "${SCRIPT_DIR}/03_pg_05_install_pgvector.sh"; then
        log_success "pgvector installé"
    else
        log_warning "Échec de l'installation de pgvector"
        log_warning "Note: pgvector devrait être déjà inclus dans l'image Docker Patroni"
        log_warning "Vérifiez que l'extension peut être créée manuellement si nécessaire"
    fi
else
    log_warning "Script 03_pg_05_install_pgvector.sh introuvable"
fi
echo ""

# Étape 6 : Diagnostics
log_info "=============================================================="
log_info "Étape 6/6 : Diagnostics et tests"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_pg_06_diagnostics.sh" ]]; then
    if "${SCRIPT_DIR}/03_pg_06_diagnostics.sh" "${TSV_FILE}"; then
        log_success "Tous les diagnostics sont OK"
    else
        log_warning "Certains tests de diagnostic ont échoué"
        log_warning "Vérifiez les erreurs ci-dessus"
    fi
else
    log_warning "Script 03_pg_06_diagnostics.sh introuvable"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 3 terminée !"
echo "=============================================================="
echo ""
log_info "Le cluster PostgreSQL HA est maintenant opérationnel."
log_info ""
log_info "Points d'accès :"
log_info "  - PostgreSQL direct (via HAProxy) : haproxy-01/02:5432"
log_info "  - PgBouncer (connection pooling)   : haproxy-01/02:6432"
log_info ""
log_info "Pour vérifier le cluster :"
log_info "  ./03_pg_06_diagnostics.sh ${TSV_FILE}"
log_info ""
log_info "Pour tester le failover (sûr et réversible) :"
log_info "  ./03_pg_07_test_failover_safe.sh"
log_info ""
log_info "Pour réinitialiser le cluster :"
log_info "  ./reinit_cluster.sh"
log_info ""
log_info "Pour vérifier l'état des services :"
log_info "  ./check_module3_status.sh"
echo ""


