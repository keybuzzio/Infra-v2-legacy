#!/usr/bin/env bash
#
# 05_rmq_05_integration_tests.sh - Tests d'intégration RabbitMQ avec autres modules
#
# Ce script teste l'intégration du Module 5 (RabbitMQ) avec les autres modules
# installés (PostgreSQL, Redis, HAProxy).
#
# Usage:
#   ./05_rmq_05_integration_tests.sh [servers.tsv]
#
# Prérequis:
#   - Modules 3, 4, 5 installés
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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 5 - Tests d'Intégration"
echo "=============================================================="
echo ""

# Test 1: Vérifier que tous les modules sont opérationnels
log_info "=============================================================="
log_info "Test 1: Vérification des modules installés"
log_info "=============================================================="

MODULE3_OK=0
MODULE4_OK=0
MODULE5_OK=0

# Module 3 (PostgreSQL/Patroni)
if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@10.0.0.126" \
    "docker ps | grep -q patroni" 2>/dev/null; then
    log_success "Module 3 (PostgreSQL HA): Opérationnel"
    MODULE3_OK=1
else
    log_warning "Module 3 (PostgreSQL HA): Non détecté"
fi

# Module 4 (Redis)
if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@10.0.0.126" \
    "docker ps | grep -q redis" 2>/dev/null; then
    log_success "Module 4 (Redis HA): Opérationnel"
    MODULE4_OK=1
else
    log_warning "Module 4 (Redis HA): Non détecté"
fi

# Module 5 (RabbitMQ)
if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@10.0.0.126" \
    "docker ps | grep -q rabbitmq" 2>/dev/null; then
    log_success "Module 5 (RabbitMQ HA): Opérationnel"
    MODULE5_OK=1
else
    log_error "Module 5 (RabbitMQ HA): Non détecté"
fi

echo ""

# Test 2: Vérifier les ports et services
log_info "=============================================================="
log_info "Test 2: Vérification des ports et services"
log_info "=============================================================="

PORTS_OK=0
PORTS_TOTAL=0

# PostgreSQL (via HAProxy)
if timeout 3 nc -z 10.0.0.11 5432 2>/dev/null; then
    log_success "PostgreSQL (HAProxy): Port 5432 accessible"
    ((PORTS_OK++))
else
    log_warning "PostgreSQL (HAProxy): Port 5432 non accessible"
fi
((PORTS_TOTAL++))

# Redis (via HAProxy)
if timeout 3 nc -z 10.0.0.11 6379 2>/dev/null; then
    log_success "Redis (HAProxy): Port 6379 accessible"
    ((PORTS_OK++))
else
    log_warning "Redis (HAProxy): Port 6379 non accessible"
fi
((PORTS_TOTAL++))

# RabbitMQ (via HAProxy)
if timeout 3 nc -z 10.0.0.11 5672 2>/dev/null; then
    log_success "RabbitMQ (HAProxy): Port 5672 accessible"
    ((PORTS_OK++))
else
    log_error "RabbitMQ (HAProxy): Port 5672 non accessible"
fi
((PORTS_TOTAL++))

echo ""

# Test 3: Vérifier HAProxy pour RabbitMQ
log_info "=============================================================="
log_info "Test 3: HAProxy RabbitMQ"
log_info "=============================================================="

HAPROXY_OK=0
for ip in 10.0.0.11 10.0.0.12; do
    if timeout 3 nc -z "${ip}" 5672 2>/dev/null; then
        log_success "HAProxy ${ip}:5672 accessible"
        ((HAPROXY_OK++))
    else
        log_error "HAProxy ${ip}:5672 non accessible"
    fi
done

echo ""

# Test 4: Vérifier le cluster RabbitMQ
log_info "=============================================================="
log_info "Test 4: Cluster RabbitMQ"
log_info "=============================================================="

CLUSTER_OK=0
for ip in 10.0.0.126 10.0.0.127 10.0.0.128; do
    CLUSTER_STATUS=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'running_nodes' || echo '0'")
    
    if [[ "${CLUSTER_STATUS}" == "1" ]]; then
        log_success "RabbitMQ ${ip}: Cluster opérationnel"
        ((CLUSTER_OK++))
    else
        log_warning "RabbitMQ ${ip}: Cluster à vérifier"
    fi
done

echo ""

# Résumé final
echo "=============================================================="
log_info "Résumé des tests d'intégration"
echo "=============================================================="
echo ""
log_info "Modules:"
log_info "  - Module 3 (PostgreSQL): $([ ${MODULE3_OK} -eq 1 ] && echo '✓' || echo '✗')"
log_info "  - Module 4 (Redis): $([ ${MODULE4_OK} -eq 1 ] && echo '✓' || echo '✗')"
log_info "  - Module 5 (RabbitMQ): $([ ${MODULE5_OK} -eq 1 ] && echo '✓' || echo '✗')"
echo ""
log_info "Ports et services:"
log_info "  - Ports accessibles: ${PORTS_OK}/${PORTS_TOTAL}"
log_info "  - HAProxy RabbitMQ: ${HAPROXY_OK}/2"
log_info "  - Cluster RabbitMQ: ${CLUSTER_OK}/3"
echo ""

if [[ ${MODULE5_OK} -eq 1 ]] && \
   [[ ${PORTS_OK} -ge 2 ]] && \
   [[ ${HAPROXY_OK} -eq 2 ]] && \
   [[ ${CLUSTER_OK} -ge 1 ]]; then
    echo "=============================================================="
    log_success "✅ Tests d'intégration réussis !"
    echo "=============================================================="
    echo ""
    log_info "Le Module 5 (RabbitMQ HA) est opérationnel et intégré"
    log_info "avec les autres modules de l'infrastructure KeyBuzz."
    echo ""
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Certains tests d'intégration ont échoué"
    echo "=============================================================="
    echo ""
    log_warning "Vérifiez les erreurs ci-dessus."
    echo ""
    exit 1
fi

