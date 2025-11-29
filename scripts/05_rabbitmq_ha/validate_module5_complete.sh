#!/bin/bash
#
# validate_module5_complete.sh - Validation complète du Module 5
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/rabbitmq.env"

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
echo " [KeyBuzz] Validation Complète Module 5"
echo "=============================================================="
echo ""

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNINGS=0

# 1. Vérifier les conteneurs RabbitMQ
log_info "1. Vérification des conteneurs RabbitMQ:"
RABBITMQ_CONTAINERS=0
for ip in 10.0.0.126 10.0.0.127 10.0.0.128; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    containers=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep -c "^rabbitmq$" || echo 0' 2>/dev/null)
    if [[ "${containers}" -eq 1 ]]; then
        log_success "  ${ip}: Conteneur RabbitMQ actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        RABBITMQ_CONTAINERS=$((RABBITMQ_CONTAINERS + 1))
    else
        log_error "  ${ip}: Conteneur RabbitMQ non actif (${containers} conteneur(s))"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 2. Vérifier le cluster RabbitMQ
log_info "2. État du cluster RabbitMQ:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
cluster_status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.126" 'docker exec rabbitmq rabbitmqctl cluster_status 2>&1' 2>/dev/null)
if echo "${cluster_status}" | grep -q "running_nodes\|cluster_name"; then
    log_success "  Cluster RabbitMQ opérationnel"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    echo "${cluster_status}" | grep -E "running_nodes|cluster_name" | head -5 | sed 's/^/    /'
    
    # Compter les nœuds
    running_nodes=$(echo "${cluster_status}" | grep -c "rabbit@queue" || echo "0")
    if [[ "${running_nodes}" -ge 3 ]]; then
        log_success "  Nœuds dans le cluster: ${running_nodes}/3"
    else
        log_warning "  Nœuds dans le cluster: ${running_nodes}/3 (attendu: 3)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    log_error "  Cluster RabbitMQ non opérationnel"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    echo "${cluster_status}" | head -5 | sed 's/^/    /'
fi
echo ""

# 3. Vérifier les ports RabbitMQ
log_info "3. Vérification des ports RabbitMQ:"
for ip in 10.0.0.126 10.0.0.127 10.0.0.128; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    port_check=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'nc -z localhost 5672 2>&1 && echo "OK" || echo "FAILED"' 2>/dev/null)
    if echo "${port_check}" | grep -q "OK"; then
        log_success "  ${ip}: Port 5672 ouvert"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "  ${ip}: Port 5672 fermé"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 4. Vérifier HAProxy
log_info "4. Vérification HAProxy:"
HAPROXY_ACTIVE=0
for ip in 10.0.0.11 10.0.0.12; do
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    haproxy=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'docker ps --format "{{.Names}}" | grep haproxy' 2>/dev/null)
    if [[ -n "${haproxy}" ]]; then
        log_success "  ${ip}: HAProxy actif"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        HAPROXY_ACTIVE=$((HAPROXY_ACTIVE + 1))
        
        # Test de port HAProxy pour RabbitMQ
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        port_check=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'nc -z localhost 5672 2>&1 && echo "OK" || echo "FAILED"' 2>/dev/null)
        if echo "${port_check}" | grep -q "OK"; then
            log_success "    Port 5672 ouvert sur HAProxy"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            log_error "    Port 5672 fermé sur HAProxy"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        log_error "  ${ip}: HAProxy non actif"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
done
echo ""

# 5. Vérifier les services systemd
log_info "5. Vérification des services systemd:"
RABBITMQ_SYSTEMD=0
for ip in 10.0.0.126 10.0.0.127 10.0.0.128; do
    status=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" 'systemctl is-active rabbitmq-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
    if [[ "${status}" = "active" ]]; then
        RABBITMQ_SYSTEMD=$((RABBITMQ_SYSTEMD + 1))
    fi
done
if [[ ${RABBITMQ_SYSTEMD} -eq 3 ]]; then
    log_success "  Services RabbitMQ systemd: ${RABBITMQ_SYSTEMD}/3 actifs"
else
    log_warning "  Services RabbitMQ systemd: ${RABBITMQ_SYSTEMD}/3 actifs (conteneurs Docker fonctionnent)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# 6. Vérifier la connectivité RabbitMQ
log_info "6. Test de connectivité RabbitMQ:"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
connectivity=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@10.0.0.126" 'docker exec rabbitmq rabbitmqctl status 2>&1 | head -3' 2>/dev/null)
if echo "${connectivity}" | grep -q "Status\|RabbitMQ"; then
    log_success "  RabbitMQ répond correctement"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    log_error "  RabbitMQ ne répond pas"
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
echo "  Conteneurs RabbitMQ: ${RABBITMQ_CONTAINERS}/3"
echo "  Services systemd:   ${RABBITMQ_SYSTEMD}/3"
echo "  HAProxy actifs:     ${HAPROXY_ACTIVE}/2"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]] && [[ ${RABBITMQ_CONTAINERS} -eq 3 ]] && [[ ${HAPROXY_ACTIVE} -eq 2 ]]; then
    echo "=============================================================="
    log_success "✅ Module 5 validé à 100% !"
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Module 5 validé avec ${FAILED_TESTS} échec(s) et ${WARNINGS} avertissement(s)"
    echo "=============================================================="
    exit 1
fi

