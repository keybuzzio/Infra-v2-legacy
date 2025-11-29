#!/usr/bin/env bash
#
# 00_relance_modules_failed.sh - Relance les installations des modules en échec
#
# Ce script relance les installations des modules qui ont échoué dans les tests
# dans l'ordre normal d'installation.
#
# Usage:
#   ./00_relance_modules_failed.sh [servers.tsv]

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

# Header
echo "=============================================================="
echo " [KeyBuzz] Relance Installation Modules en Échec"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo ""

# Module 3 : PostgreSQL HA
log_info "=============================================================="
log_info "MODULE 3 : PostgreSQL HA"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 3 a échoué"
        exit 1
    }
    log_success "Module 3 terminé"
else
    log_error "Script Module 3 introuvable"
    exit 1
fi
echo ""

# Module 4 : Redis HA
log_info "=============================================================="
log_info "MODULE 4 : Redis HA"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 4 a échoué"
        exit 1
    }
    log_success "Module 4 terminé"
else
    log_error "Script Module 4 introuvable"
    exit 1
fi
echo ""

# Module 5 : RabbitMQ HA
log_info "=============================================================="
log_info "MODULE 5 : RabbitMQ HA"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 5 a échoué"
        exit 1
    }
    log_success "Module 5 terminé"
else
    log_error "Script Module 5 introuvable"
    exit 1
fi
echo ""

# Module 6 : MinIO
log_info "=============================================================="
log_info "MODULE 6 : MinIO S3"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 6 a échoué"
        exit 1
    }
    log_success "Module 6 terminé"
else
    log_error "Script Module 6 introuvable"
    exit 1
fi
echo ""

# Module 7 : MariaDB Galera
log_info "=============================================================="
log_info "MODULE 7 : MariaDB Galera HA"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 7 a échoué"
        exit 1
    }
    log_success "Module 7 terminé"
else
    log_error "Script Module 7 introuvable"
    exit 1
fi
echo ""

# Module 8 : ProxySQL Advanced
log_info "=============================================================="
log_info "MODULE 8 : ProxySQL Advanced"
log_info "=============================================================="
if [[ -f "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh" ]]; then
    echo "y" | "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh" "${TSV_FILE}" || {
        log_error "Module 8 a échoué"
        exit 1
    }
    log_success "Module 8 terminé"
else
    log_error "Script Module 8 introuvable"
    exit 1
fi
echo ""

# Résumé
echo "=============================================================="
log_success "Tous les modules ont été relancés"
echo "=============================================================="
echo ""
log_info "Prochaine étape : Relancer les tests avec :"
log_info "  bash 00_test_complet_infrastructure_v2.sh ${TSV_FILE}"
echo ""

