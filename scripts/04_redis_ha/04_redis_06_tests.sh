#!/usr/bin/env bash
#
# 04_redis_06_tests.sh - Tests et diagnostics Redis HA
#
# Ce script exécute une série de tests pour valider le cluster Redis HA :
# - Tests de connectivité
# - Tests SET/GET
# - Tests de réplication
# - Tests Sentinel
# - Tests HAProxy
#
# Usage:
#   ./04_redis_06_tests.sh [servers.tsv]
#
# Prérequis:
#   - Tous les scripts précédents exécutés
#   - Credentials configurés
#   - Exécuter depuis install-01

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

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Vérifier que redis-cli est disponible
if ! command -v redis-cli >/dev/null 2>&1; then
    log_info "Installation de redis-cli..."
    apt-get update -qq && apt-get install -y -qq redis-tools >/dev/null 2>&1
fi

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
echo " [KeyBuzz] Module 4 - Tests et Diagnostics Redis HA"
echo "=============================================================="
echo ""

# Collecter les informations
declare -a REDIS_NODES
declare -a REDIS_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "redis" ]] && \
       ([[ "${HOSTNAME}" == "redis-01" ]] || \
        [[ "${HOSTNAME}" == "redis-02" ]] || \
        [[ "${HOSTNAME}" == "redis-03" ]]); then
        REDIS_NODES+=("${HOSTNAME}")
        REDIS_IPS+=("${IP_PRIVEE}")
    fi
    
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]] && \
       ([[ "${HOSTNAME}" == "haproxy-01" ]] || [[ "${HOSTNAME}" == "haproxy-02" ]]); then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

# Test 1: Connectivité Redis
log_info "=============================================================="
log_info "Test 1: Connectivité Redis"
log_info "=============================================================="

REDIS_OK=0
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    if timeout 3 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
        log_success "${hostname} (${ip}): Connecté"
        ((REDIS_OK++))
    else
        log_error "${hostname} (${ip}): Non connecté"
    fi
done

if [[ ${REDIS_OK} -eq ${#REDIS_NODES[@]} ]]; then
    log_success "Tous les nœuds Redis sont accessibles"
else
    log_warning "Seulement ${REDIS_OK}/${#REDIS_NODES[@]} nœuds Redis accessibles"
fi
echo ""

# Test 2: Rôles Redis
log_info "=============================================================="
log_info "Test 2: Rôles Redis"
log_info "=============================================================="

MASTER_COUNT=0
REPLICA_COUNT=0

for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    ROLE=$(timeout 3 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning INFO replication 2>/dev/null | grep "role:" | cut -d: -f2 | tr -d '\r ' || echo "unknown")
    
    if [[ "${ROLE}" == "master" ]]; then
        log_success "${hostname}: Master"
        ((MASTER_COUNT++))
    elif [[ "${ROLE}" == "slave" ]] || [[ "${ROLE}" == "replica" ]]; then
        log_info "${hostname}: Replica"
        ((REPLICA_COUNT++))
    else
        log_warning "${hostname}: Rôle inconnu (${ROLE})"
    fi
done

if [[ ${MASTER_COUNT} -eq 1 ]] && [[ ${REPLICA_COUNT} -eq 2 ]]; then
    log_success "Topologie correcte: 1 Master + 2 Replicas"
else
    log_warning "Topologie inattendue: ${MASTER_COUNT} Master(s) + ${REPLICA_COUNT} Replica(s)"
fi
echo ""

# Test 3: Sentinel
log_info "=============================================================="
log_info "Test 3: Redis Sentinel"
log_info "=============================================================="

SENTINEL_OK=0
MASTER_DETECTED=""

for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    MASTER=$(timeout 3 redis-cli -h "${ip}" -p 26379 SENTINEL get-master-addr-by-name "${REDIS_MASTER_NAME}" 2>/dev/null | head -1 || echo "")
    
    if [[ -n "${MASTER}" ]]; then
        log_success "${hostname}: Sentinel opérationnel (master: ${MASTER})"
        ((SENTINEL_OK++))
        if [[ -z "${MASTER_DETECTED}" ]]; then
            MASTER_DETECTED="${MASTER}"
        fi
    else
        log_error "${hostname}: Sentinel ne répond pas"
    fi
done

if [[ ${SENTINEL_OK} -eq ${#REDIS_NODES[@]} ]]; then
    log_success "Tous les Sentinels sont opérationnels"
    log_info "Master détecté par Sentinel: ${MASTER_DETECTED}"
else
    log_warning "Seulement ${SENTINEL_OK}/${#REDIS_NODES[@]} Sentinels opérationnels"
fi
echo ""

# Test 4: HAProxy
log_info "=============================================================="
log_info "Test 4: HAProxy"
log_info "=============================================================="

HAPROXY_OK=0
for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    if timeout 3 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
        log_success "${hostname} (${ip}): HAProxy opérationnel"
        ((HAPROXY_OK++))
    else
        log_error "${hostname} (${ip}): HAProxy ne répond pas"
    fi
done

if [[ ${HAPROXY_OK} -eq ${#HAPROXY_NODES[@]} ]]; then
    log_success "Tous les HAProxy sont opérationnels"
else
    log_warning "Seulement ${HAPROXY_OK}/${#HAPROXY_NODES[@]} HAProxy opérationnels"
fi
echo ""

# Test 5: SET/GET
log_info "=============================================================="
log_info "Test 5: SET/GET via HAProxy"
log_info "=============================================================="

TEST_KEY="keybuzz_test_$(date +%s)"
TEST_VALUE="test_value_$(date +%s)"

if [[ ${#HAPROXY_IPS[@]} -gt 0 ]]; then
    TEST_IP="${HAPROXY_IPS[0]}"
    
    if timeout 3 redis-cli -h "${TEST_IP}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning SET "${TEST_KEY}" "${TEST_VALUE}" 2>/dev/null | grep -q "OK"; then
        log_success "SET réussi via HAProxy (${TEST_IP})"
        
        RETRIEVED_VALUE=$(timeout 3 redis-cli -h "${TEST_IP}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning GET "${TEST_KEY}" 2>/dev/null || echo "")
        
        if [[ "${RETRIEVED_VALUE}" == "${TEST_VALUE}" ]]; then
            log_success "GET réussi: valeur correcte"
        else
            log_error "GET échoué: valeur incorrecte (${RETRIEVED_VALUE} au lieu de ${TEST_VALUE})"
        fi
        
        # Nettoyer
        timeout 3 redis-cli -h "${TEST_IP}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning DEL "${TEST_KEY}" >/dev/null 2>&1 || true
    else
        log_error "SET échoué via HAProxy"
    fi
else
    log_warning "Aucun HAProxy disponible pour le test"
fi
echo ""

# Test 6: Réplication
log_info "=============================================================="
log_info "Test 6: Réplication"
log_info "=============================================================="

if [[ -n "${MASTER_DETECTED}" ]]; then
    REPLICA_KEY="keybuzz_replica_test_$(date +%s)"
    REPLICA_VALUE="replica_value_$(date +%s)"
    
    # Écrire sur le master
    if timeout 3 redis-cli -h "${MASTER_DETECTED}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning SET "${REPLICA_KEY}" "${REPLICA_VALUE}" 2>/dev/null | grep -q "OK"; then
        log_success "Écriture sur master réussie"
        
        # Attendre la réplication
        sleep 2
        
        # Vérifier sur les replicas
        REPLICA_OK=0
        for i in "${!REDIS_NODES[@]}"; do
            ip="${REDIS_IPS[$i]}"
            
            if [[ "${ip}" == "${MASTER_DETECTED}" ]]; then
                continue
            fi
            
            REPLICA_VALUE_RETRIEVED=$(timeout 3 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning GET "${REPLICA_KEY}" 2>/dev/null || echo "")
            
            if [[ "${REPLICA_VALUE_RETRIEVED}" == "${REPLICA_VALUE}" ]]; then
                log_success "Réplication OK sur ${ip}"
                ((REPLICA_OK++))
            else
                log_warning "Réplication non confirmée sur ${ip}"
            fi
        done
        
        if [[ ${REPLICA_OK} -eq 2 ]]; then
            log_success "Réplication complète: toutes les données répliquées"
        else
            log_warning "Réplication partielle: ${REPLICA_OK}/2 replicas"
        fi
        
        # Nettoyer
        timeout 3 redis-cli -h "${MASTER_DETECTED}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning DEL "${REPLICA_KEY}" >/dev/null 2>&1 || true
    else
        log_error "Écriture sur master échouée"
    fi
else
    log_warning "Master non détecté, test de réplication ignoré"
fi
echo ""

# Test 7: Healthcheck
log_info "=============================================================="
log_info "Test 7: Healthcheck LB"
log_info "=============================================================="

for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    STATE=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "cat /opt/keybuzz/redis-lb/status/STATE 2>/dev/null || echo 'UNKNOWN'")
    
    if [[ "${STATE}" == "OK" ]]; then
        log_success "${hostname}: État OK"
    elif [[ "${STATE}" == "DEGRADED" ]]; then
        log_warning "${hostname}: État DEGRADED"
    elif [[ "${STATE}" == "ERROR" ]]; then
        log_error "${hostname}: État ERROR"
    else
        log_warning "${hostname}: État ${STATE}"
    fi
done
echo ""

# Résumé final
echo "=============================================================="
log_info "Résumé des tests"
echo "=============================================================="
echo ""
log_info "Redis:"
log_info "  - Nœuds accessibles: ${REDIS_OK}/${#REDIS_NODES[@]}"
log_info "  - Topologie: ${MASTER_COUNT} Master + ${REPLICA_COUNT} Replicas"
echo ""
log_info "Sentinel:"
log_info "  - Sentinels opérationnels: ${SENTINEL_OK}/${#REDIS_NODES[@]}"
log_info "  - Master détecté: ${MASTER_DETECTED:-N/A}"
echo ""
log_info "HAProxy:"
log_info "  - HAProxy opérationnels: ${HAPROXY_OK}/${#HAPROXY_NODES[@]}"
echo ""

if [[ ${REDIS_OK} -eq ${#REDIS_NODES[@]} ]] && \
   [[ ${MASTER_COUNT} -eq 1 ]] && \
   [[ ${REPLICA_COUNT} -eq 2 ]] && \
   [[ ${SENTINEL_OK} -eq ${#REDIS_NODES[@]} ]] && \
   [[ ${HAPROXY_OK} -eq ${#HAPROXY_NODES[@]} ]]; then
    echo "=============================================================="
    log_success "✅ Tous les tests sont passés avec succès !"
    echo "=============================================================="
    echo ""
    log_info "Le cluster Redis HA est opérationnel et prêt pour la production."
    echo ""
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Certains tests ont échoué"
    echo "=============================================================="
    echo ""
    log_warning "Vérifiez les erreurs ci-dessus et corrigez les problèmes."
    echo ""
    exit 1
fi

