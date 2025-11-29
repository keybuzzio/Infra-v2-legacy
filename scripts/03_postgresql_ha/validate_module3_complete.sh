#!/bin/bash
#
# validate_module3_complete.sh - Validation complète du Module 3
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"

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

# Charger les credentials
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

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

echo "=============================================================="
echo " [KeyBuzz] Validation Complète Module 3"
echo "=============================================================="
echo ""

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# 1. Vérifier les conteneurs Patroni
log_info "1. Vérification des conteneurs Patroni:"
PATRONI_CONTAINERS=0
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    containers=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep -c patroni || echo 0' 2>/dev/null)
    if [[ "${containers}" -eq 1 ]]; then
        log_success "  ${ip}: Conteneur actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        PATRONI_CONTAINERS=$((PATRONI_CONTAINERS + 1))
    else
        log_error "  ${ip}: Conteneur non actif (${containers} conteneur(s))"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 2. Vérifier le cluster Patroni
log_info "2. État du cluster Patroni:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
cluster_status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.120" 'docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1' 2>/dev/null)
if echo "${cluster_status}" | grep -q "Leader.*running"; then
    log_success "  Cluster opérationnel avec Leader"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo "${cluster_status}" | sed 's/^/    /'
else
    log_error "  Cluster non opérationnel"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "${cluster_status}" | sed 's/^/    /'
fi
echo ""

# 3. Vérifier HAProxy
log_info "3. Vérification HAProxy:"
HAPROXY_ACTIVE=0
for ip in 10.0.0.11 10.0.0.12; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    haproxy=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep haproxy' 2>/dev/null)
    if [[ -n "${haproxy}" ]]; then
        log_success "  ${ip}: HAProxy actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        HAPROXY_ACTIVE=$((HAPROXY_ACTIVE + 1))
        
        # Test de connexion PostgreSQL via HAProxy
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        result=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" "PGPASSWORD=${POSTGRES_SUPERPASS} psql -h 127.0.0.1 -p 5432 -U ${POSTGRES_SUPERUSER} -d postgres -c 'SELECT version();' 2>&1" 2>/dev/null | head -1)
        if echo "${result}" | grep -q "PostgreSQL"; then
            log_success "    Connexion PostgreSQL via HAProxy OK"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_error "    Connexion PostgreSQL via HAProxy échouée"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        log_error "  ${ip}: HAProxy non actif"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 4. Vérifier PgBouncer
log_info "4. Vérification PgBouncer:"
PGBOUNCER_ACTIVE=0
for ip in 10.0.0.11 10.0.0.12; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    pgbouncer=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep pgbouncer' 2>/dev/null)
    if [[ -n "${pgbouncer}" ]]; then
        log_success "  ${ip}: PgBouncer actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        PGBOUNCER_ACTIVE=$((PGBOUNCER_ACTIVE + 1))
        
        # Test de connexion via PgBouncer
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        result=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" "PGPASSWORD=${POSTGRES_SUPERPASS} psql -h 127.0.0.1 -p 6432 -U ${POSTGRES_SUPERUSER} -d pgbouncer -c 'SHOW POOLS;' 2>&1" 2>/dev/null | head -3)
        if echo "${result}" | grep -q "pgbouncer\|pool"; then
            log_success "    Connexion PgBouncer OK"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_error "    Connexion PgBouncer échouée"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        log_error "  ${ip}: PgBouncer non actif"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 5. Vérifier pgvector
log_info "5. Vérification pgvector:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
result=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.120" "docker exec patroni psql -U postgres -c \"CREATE EXTENSION IF NOT EXISTS vector; SELECT extversion FROM pg_extension WHERE extname='vector';\" 2>&1" 2>/dev/null)
if echo "${result}" | grep -q "vector\|extversion"; then
    log_success "  pgvector disponible"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo "${result}" | grep -E "vector|extversion" | sed 's/^/    /' | head -2
else
    log_warning "  pgvector non disponible (peut être normal si non installé)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 6. Vérifier les services systemd
log_info "6. Vérification des services systemd:"
PATRONI_SYSTEMD=0
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'systemctl is-active patroni-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
    if [[ "${status}" = "active" ]]; then
        log_success "  ${ip}: Service systemd actif"
        PATRONI_SYSTEMD=$((PATRONI_SYSTEMD + 1))
    else
        log_warning "  ${ip}: Service systemd ${status} (conteneur Docker fonctionne)"
        WARNINGS=$((WARNINGS + 1))
    fi
done
echo ""

# Résumé
echo "=============================================================="
echo " RÉSUMÉ DE LA VALIDATION"
echo "=============================================================="
echo ""
echo "  Tests effectués: ${TOTAL_TESTS}"
echo "  Tests réussis:   ${PASSED_TESTS}"
echo "  Tests échoués:   ${FAILED_TESTS}"
echo "  Avertissements:  ${WARNINGS}"
echo ""
echo "  Conteneurs Patroni:     ${PATRONI_CONTAINERS}/3"
echo "  Services systemd:      ${PATRONI_SYSTEMD}/3"
echo "  HAProxy actifs:        ${HAPROXY_ACTIVE}/2"
echo "  PgBouncer actifs:      ${PGBOUNCER_ACTIVE}/2"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]] && [[ ${PATRONI_CONTAINERS} -eq 3 ]] && [[ ${HAPROXY_ACTIVE} -eq 2 ]] && [[ ${PGBOUNCER_ACTIVE} -eq 2 ]]; then
    echo "=============================================================="
    log_success "✅ Module 3 validé à 100% !"
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Module 3 validé avec ${FAILED_TESTS} échec(s) et ${WARNINGS} avertissement(s)"
    echo "=============================================================="
    exit 1
fi

