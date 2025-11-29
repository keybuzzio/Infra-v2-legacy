#!/bin/bash
#
# validate_module4_complete.sh - Validation complète du Module 4
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/redis.env"

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
echo " [KeyBuzz] Validation Complète Module 4"
echo "=============================================================="
echo ""

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# 1. Vérifier les conteneurs Redis
log_info "1. Vérification des conteneurs Redis:"
REDIS_CONTAINERS=0
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    containers=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep -c "^redis$" || echo 0' 2>/dev/null)
    if [[ "${containers}" -eq 1 ]]; then
        log_success "  ${ip}: Conteneur Redis actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        REDIS_CONTAINERS=$((REDIS_CONTAINERS + 1))
    else
        log_error "  ${ip}: Conteneur Redis non actif (${containers} conteneur(s))"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 2. Vérifier les conteneurs Sentinel
log_info "2. Vérification des conteneurs Sentinel:"
SENTINEL_CONTAINERS=0
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    containers=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep -c "redis-sentinel" || echo 0' 2>/dev/null)
    if [[ "${containers}" -eq 1 ]]; then
        log_success "  ${ip}: Conteneur Sentinel actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        SENTINEL_CONTAINERS=$((SENTINEL_CONTAINERS + 1))
    else
        log_error "  ${ip}: Conteneur Sentinel non actif (${containers} conteneur(s))"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 3. Vérifier la réplication Redis
log_info "3. Vérification de la réplication Redis:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
master_info=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.123" 'docker exec redis redis-cli INFO replication 2>&1' 2>/dev/null)
if echo "${master_info}" | grep -q "role:master"; then
    log_success "  Master Redis: redis-01 (10.0.0.123) - rôle confirmé"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    connected_slaves=$(echo "${master_info}" | grep "connected_slaves:" | cut -d: -f2 | tr -d ' ')
    if [[ "${connected_slaves}" -ge 2 ]]; then
        log_success "  Replicas connectés: ${connected_slaves}/2"
    else
        log_warning "  Replicas connectés: ${connected_slaves}/2 (attendu: 2)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_error "  Master Redis non détecté"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
echo ""

# 4. Vérifier Sentinel
log_info "4. Vérification de Redis Sentinel:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
sentinel_masters=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.123" 'docker exec redis-sentinel redis-cli -p 26379 SENTINEL masters 2>&1' 2>/dev/null)
if echo "${sentinel_masters}" | grep -q "mymaster\|name"; then
    log_success "  Sentinel détecte le master"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo "${sentinel_masters}" | head -5 | sed 's/^/    /'
else
    log_error "  Sentinel ne détecte pas le master"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
echo ""

# 5. Vérifier HAProxy
log_info "5. Vérification HAProxy:"
HAPROXY_ACTIVE=0
for ip in 10.0.0.11 10.0.0.12; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    haproxy=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep haproxy' 2>/dev/null)
    if [[ -n "${haproxy}" ]]; then
        log_success "  ${ip}: HAProxy actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        HAPROXY_ACTIVE=$((HAPROXY_ACTIVE + 1))
        
        # Test de connexion Redis via HAProxy
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        result=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" "docker exec redis redis-cli -h 127.0.0.1 -p 6379 PING 2>&1" 2>/dev/null || echo "FAILED")
        if echo "${result}" | grep -q "PONG"; then
            log_success "    Connexion Redis via HAProxy OK"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_error "    Connexion Redis via HAProxy échouée"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        log_error "  ${ip}: HAProxy non actif"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 6. Vérifier les services systemd
log_info "6. Vérification des services systemd:"
REDIS_SYSTEMD=0
SENTINEL_SYSTEMD=0
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    redis_status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'systemctl is-active redis-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
    sentinel_status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'systemctl is-active redis-sentinel-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
    if [[ "${redis_status}" = "active" ]]; then
        REDIS_SYSTEMD=$((REDIS_SYSTEMD + 1))
    fi
    if [[ "${sentinel_status}" = "active" ]]; then
        SENTINEL_SYSTEMD=$((SENTINEL_SYSTEMD + 1))
    fi
done
if [[ ${REDIS_SYSTEMD} -eq 3 ]]; then
    log_success "  Services Redis systemd: ${REDIS_SYSTEMD}/3 actifs"
else
    log_warning "  Services Redis systemd: ${REDIS_SYSTEMD}/3 actifs (conteneurs Docker fonctionnent)"
    WARNINGS=$((WARNINGS + 1))
fi
if [[ ${SENTINEL_SYSTEMD} -eq 3 ]]; then
    log_success "  Services Sentinel systemd: ${SENTINEL_SYSTEMD}/3 actifs"
else
    log_warning "  Services Sentinel systemd: ${SENTINEL_SYSTEMD}/3 actifs (conteneurs Docker fonctionnent)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 7. Test de lecture/écriture
log_info "7. Test de lecture/écriture Redis:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
test_result=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.123" 'docker exec redis redis-cli SET test_key "test_value" && docker exec redis redis-cli GET test_key 2>&1' 2>/dev/null)
if echo "${test_result}" | grep -q "test_value"; then
    log_success "  Test de lecture/écriture OK"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    # Nettoyer
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.123" 'docker exec redis redis-cli DEL test_key 2>/dev/null' 2>/dev/null || true
else
    log_error "  Test de lecture/écriture échoué"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi
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
echo "  Conteneurs Redis:     ${REDIS_CONTAINERS}/3"
echo "  Conteneurs Sentinel:  ${SENTINEL_CONTAINERS}/3"
echo "  Services Redis:      ${REDIS_SYSTEMD}/3"
echo "  Services Sentinel:   ${SENTINEL_SYSTEMD}/3"
echo "  HAProxy actifs:      ${HAPROXY_ACTIVE}/2"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]] && [[ ${REDIS_CONTAINERS} -eq 3 ]] && [[ ${SENTINEL_CONTAINERS} -eq 3 ]] && [[ ${HAPROXY_ACTIVE} -eq 2 ]]; then
    echo "=============================================================="
    log_success "✅ Module 4 validé à 100% !"
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Module 4 validé avec ${FAILED_TESTS} échec(s) et ${WARNINGS} avertissement(s)"
    echo "=============================================================="
    exit 1
fi

