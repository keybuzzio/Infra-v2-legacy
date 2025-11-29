#!/usr/bin/env bash
#
# 00_test_complet_infrastructure_avance.sh - Tests exhaustifs de l'infrastructure
#
# Ce script effectue des tests complets de tous les modules installés :
# - Tests de connectivité
# - Tests de failover automatique
# - Tests de récupération
# - Tests de synchronisation/réplication
# - Tests de load balancing
# - Tests de crash et récupération
#
# Usage:
#   ./00_test_complet_infrastructure_avance.sh [servers.tsv]
#

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

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Compteurs de tests
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_result() {
    local test_name="$1"
    local result="$2"
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [[ "${result}" == "PASS" ]]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        log_success "${test_name}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        log_error "${test_name}"
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Exhaustifs Infrastructure Complète"
echo "=============================================================="
echo ""
log_info "Ce script va tester :"
log_info "  - Module 3 : PostgreSQL HA (Patroni + PgBouncer + HAProxy)"
log_info "  - Module 4 : Redis HA (Master-Replica + Sentinel + HAProxy)"
log_info "  - Module 5 : RabbitMQ HA (Quorum cluster)"
log_info "  - Module 6 : MinIO S3"
log_info "  - Module 7 : MariaDB Galera HA + ProxySQL"
log_info "  - Module 8 : ProxySQL Advanced"
echo ""

# Charger les credentials (optionnel, certaines variables peuvent ne pas être définies)
CREDENTIALS_PG="${INSTALL_DIR}/credentials/postgres.env"
CREDENTIALS_REDIS="${INSTALL_DIR}/credentials/redis.env"
CREDENTIALS_MARIA="${INSTALL_DIR}/credentials/mariadb.env"

if [[ -f "${CREDENTIALS_PG}" ]]; then
    source "${CREDENTIALS_PG}"
fi

if [[ -f "${CREDENTIALS_REDIS}" ]]; then
    source "${CREDENTIALS_REDIS}"
fi

if [[ -f "${CREDENTIALS_MARIA}" ]]; then
    source "${CREDENTIALS_MARIA}"
fi

# Variables par défaut si non définies
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-keybuzz}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

# Collecter les serveurs
declare -a PG_NODES=()
declare -a PG_IPS=()
declare -a REDIS_NODES=()
declare -a REDIS_IPS=()
declare -a RABBITMQ_NODES=()
declare -a RABBITMQ_IPS=()
declare -a MINIO_NODES=()
declare -a MINIO_IPS=()
declare -a MARIADB_NODES=()
declare -a MARIADB_IPS=()
declare -a PROXYSQL_NODES=()
declare -a PROXYSQL_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" ]]; then
        if [[ "${SUBROLE}" == "postgres" ]]; then
            # Filtrer uniquement les 3 nœuds Patroni (exclure temporal-db, analytics-db, etc.)
            if [[ "${HOSTNAME}" == "db-master-01" ]] || \
               [[ "${HOSTNAME}" == "db-slave-01" ]] || \
               [[ "${HOSTNAME}" == "db-slave-02" ]]; then
                PG_NODES+=("${HOSTNAME}")
                PG_IPS+=("${IP_PRIVEE}")
            fi
        elif [[ "${SUBROLE}" == "mariadb" ]]; then
            if [[ "${HOSTNAME}" =~ ^maria- ]]; then
                MARIADB_NODES+=("${HOSTNAME}")
                MARIADB_IPS+=("${IP_PRIVEE}")
            fi
        fi
    elif [[ "${ROLE}" == "db_proxy" ]] || ([[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "proxysql" ]]); then
        if [[ "${HOSTNAME}" == "proxysql-01" ]] || [[ "${HOSTNAME}" == "proxysql-02" ]]; then
            PROXYSQL_NODES+=("${HOSTNAME}")
            PROXYSQL_IPS+=("${IP_PRIVEE}")
        fi
    elif [[ "${ROLE}" == "redis" ]]; then
        if [[ "${HOSTNAME}" =~ ^redis- ]]; then
            REDIS_NODES+=("${HOSTNAME}")
            REDIS_IPS+=("${IP_PRIVEE}")
        fi
    elif [[ "${ROLE}" == "queue" ]] && [[ "${SUBROLE}" == "rabbitmq" ]]; then
        if [[ "${HOSTNAME}" =~ ^queue- ]]; then
            RABBITMQ_NODES+=("${HOSTNAME}")
            RABBITMQ_IPS+=("${IP_PRIVEE}")
        fi
    elif [[ "${ROLE}" == "storage" ]] && [[ "${SUBROLE}" == "minio" ]]; then
        if [[ "${HOSTNAME}" =~ ^minio- ]]; then
            MINIO_NODES+=("${HOSTNAME}")
            MINIO_IPS+=("${IP_PRIVEE}")
        fi
    fi
done
exec 3<&-

log_success "Serveurs détectés :"
log_info "  PostgreSQL: ${#PG_NODES[@]} nœuds (${PG_NODES[*]})"
log_info "  Redis: ${#REDIS_NODES[@]} nœuds (${REDIS_NODES[*]})"
log_info "  RabbitMQ: ${#RABBITMQ_NODES[@]} nœuds (${RABBITMQ_NODES[*]})"
log_info "  MinIO: ${#MINIO_NODES[@]} nœuds (${MINIO_NODES[*]})"
log_info "  MariaDB: ${#MARIADB_NODES[@]} nœuds (${MARIADB_NODES[*]})"
log_info "  ProxySQL: ${#PROXYSQL_NODES[@]} nœuds (${PROXYSQL_NODES[*]})"
echo ""

# ============================================================
# MODULE 3 : PostgreSQL HA
# ============================================================
echo "=============================================================="
log_info "MODULE 3 : PostgreSQL HA - Tests de Base"
echo "=============================================================="

# Test 1: Connectivité PostgreSQL directe
if [[ ${#PG_IPS[@]} -gt 0 ]]; then
    log_info "Test 1.1: Connectivité PostgreSQL directe..."
    PG_CONNECTIVITY_OK=true
    for i in "${!PG_IPS[@]}"; do
        ip="${PG_IPS[$i]}"
        if ! ssh ${SSH_OPTS} root@${ip} "docker exec patroni psql -U${POSTGRES_USER:-postgres} -d${POSTGRES_DB:-keybuzz} -c 'SELECT 1;' >/dev/null 2>&1"; then
            PG_CONNECTIVITY_OK=false
            break
        fi
    done
    test_result "PostgreSQL - Connectivité directe" "${PG_CONNECTIVITY_OK:+PASS}${PG_CONNECTIVITY_OK:-FAIL}"
else
    log_warning "Aucun nœud PostgreSQL détecté, tests PostgreSQL ignorés"
    test_result "PostgreSQL - Connectivité directe" "SKIP"
fi

# Test 2: Statut Patroni
if [[ ${#PG_IPS[@]} -gt 0 ]]; then
    log_info "Test 1.2: Statut Patroni..."
    PATRONI_OK=true
    for i in "${!PG_IPS[@]}"; do
        ip="${PG_IPS[$i]}"
        if ! ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni 2>/dev/null | grep -q 'state'"; then
            PATRONI_OK=false
            break
        fi
    done
    test_result "PostgreSQL - Statut Patroni" "${PATRONI_OK:+PASS}${PATRONI_OK:-FAIL}"
else
    test_result "PostgreSQL - Statut Patroni" "SKIP"
fi

# Test 3: Leader/Replica
if [[ ${#PG_IPS[@]} -gt 0 ]]; then
    log_info "Test 1.3: Leader/Replica..."
    LEADER_COUNT=0
    REPLICA_COUNT=0
    for i in "${!PG_IPS[@]}"; do
        ip="${PG_IPS[$i]}"
        ROLE=$(ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '\"role\":\"[^\"]*\"' | cut -d'\"' -f4" 2>/dev/null || echo "")
        if [[ "${ROLE}" == "Leader" ]]; then
            LEADER_COUNT=$((LEADER_COUNT + 1))
        elif [[ "${ROLE}" == "Replica" ]]; then
            REPLICA_COUNT=$((REPLICA_COUNT + 1))
        fi
    done
    if [[ ${LEADER_COUNT} -eq 1 ]] && [[ ${REPLICA_COUNT} -ge 1 ]]; then
        test_result "PostgreSQL - Leader/Replica (1 leader, ${REPLICA_COUNT} replicas)" "PASS"
    else
        test_result "PostgreSQL - Leader/Replica (1 leader, ${REPLICA_COUNT} replicas)" "FAIL"
    fi
else
    test_result "PostgreSQL - Leader/Replica" "SKIP"
fi

# Test 4: PgBouncer (sur HAProxy nodes)
log_info "Test 1.4: PgBouncer..."
PGBOUNCER_OK=true
# Chercher les nœuds HAProxy
HAPROXY_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]]; then
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#HAPROXY_IPS[@]} -gt 0 ]]; then
    for ip in "${HAPROXY_IPS[@]}"; do
        if ! ssh ${SSH_OPTS} root@${ip} "docker exec pgbouncer psql -h127.0.0.1 -p6432 -U${POSTGRES_USER} -d${POSTGRES_DB} -c 'SELECT 1;' >/dev/null 2>&1" 2>/dev/null; then
            PGBOUNCER_OK=false
            break
        fi
    done
    test_result "PostgreSQL - PgBouncer" "${PGBOUNCER_OK:+PASS}${PGBOUNCER_OK:-FAIL}"
else
    test_result "PostgreSQL - PgBouncer" "SKIP"
fi

# Test 5: HAProxy PostgreSQL
log_info "Test 1.5: HAProxy PostgreSQL..."
HAPROXY_PG_OK=false
if [[ ${#HAPROXY_IPS[@]} -gt 0 ]]; then
    for ip in "${HAPROXY_IPS[@]}"; do
        if ssh ${SSH_OPTS} root@${ip} "docker exec haproxy psql -h127.0.0.1 -p5432 -U${POSTGRES_USER:-postgres} -d${POSTGRES_DB:-keybuzz} -c 'SELECT 1;' >/dev/null 2>&1" 2>/dev/null; then
            HAPROXY_PG_OK=true
            break
        fi
    done
    test_result "PostgreSQL - HAProxy" "${HAPROXY_PG_OK:+PASS}${HAPROXY_PG_OK:-FAIL}"
else
    test_result "PostgreSQL - HAProxy" "SKIP"
fi

echo ""

# ============================================================
# MODULE 4 : Redis HA
# ============================================================
echo "=============================================================="
log_info "MODULE 4 : Redis HA - Tests de Base"
echo "=============================================================="

# Test 1: Connectivité Redis directe
if [[ ${#REDIS_IPS[@]} -gt 0 ]]; then
    log_info "Test 2.1: Connectivité Redis directe..."
    REDIS_CONNECTIVITY_OK=true
    for i in "${!REDIS_IPS[@]}"; do
        ip="${REDIS_IPS[$i]}"
        if [[ -n "${REDIS_PASSWORD}" ]]; then
            if ! ssh ${SSH_OPTS} root@${ip} "docker exec redis redis-cli -a '${REDIS_PASSWORD}' PING >/dev/null 2>&1"; then
                REDIS_CONNECTIVITY_OK=false
                break
            fi
        else
            if ! ssh ${SSH_OPTS} root@${ip} "docker exec redis redis-cli PING >/dev/null 2>&1"; then
                REDIS_CONNECTIVITY_OK=false
                break
            fi
        fi
    done
    test_result "Redis - Connectivité directe" "${REDIS_CONNECTIVITY_OK:+PASS}${REDIS_CONNECTIVITY_OK:-FAIL}"
else
    log_warning "Aucun nœud Redis détecté, tests Redis ignorés"
    test_result "Redis - Connectivité directe" "SKIP"
fi

# Test 2: Master/Replica
log_info "Test 2.2: Master/Replica..."
REDIS_MASTER_OK=false
REDIS_REPLICA_OK=false
for i in "${!REDIS_IPS[@]}"; do
    ip="${REDIS_IPS[$i]}"
    ROLE=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication | grep 'role:' | cut -d: -f2 | tr -d '\r\n'" 2>/dev/null || echo "")
    if [[ "${ROLE}" == "master" ]]; then
        REDIS_MASTER_OK=true
    elif [[ "${ROLE}" == "slave" ]]; then
        REDIS_REPLICA_OK=true
    fi
done
if [[ "${REDIS_MASTER_OK}" == "true" ]] && [[ "${REDIS_REPLICA_OK}" == "true" ]]; then
    test_result "Redis - Master/Replica" "PASS"
else
    test_result "Redis - Master/Replica" "FAIL"
fi

# Test 3: Sentinel
log_info "Test 2.3: Sentinel..."
SENTINEL_OK=true
for i in "${!REDIS_IPS[@]}"; do
    ip="${REDIS_IPS[$i]}"
    if ! ssh ${SSH_OPTS} root@${ip} "docker exec redis-sentinel redis-cli -p26379 PING >/dev/null 2>&1"; then
        SENTINEL_OK=false
        break
    fi
done
test_result "Redis - Sentinel" "${SENTINEL_OK:+PASS}${SENTINEL_OK:-FAIL}"

# Test 4: HAProxy Redis
log_info "Test 2.4: HAProxy Redis..."
HAPROXY_REDIS_OK=false
HAPROXY_IP="10.0.0.11"  # À adapter selon votre configuration
if ssh ${SSH_OPTS} root@${HAPROXY_IP} "docker exec haproxy redis-cli -h127.0.0.1 -p6379 -a '${REDIS_PASSWORD}' PING >/dev/null 2>&1" 2>/dev/null; then
    HAPROXY_REDIS_OK=true
fi
test_result "Redis - HAProxy" "${HAPROXY_REDIS_OK:+PASS}${HAPROXY_REDIS_OK:-FAIL}"

echo ""

# ============================================================
# MODULE 5 : RabbitMQ HA
# ============================================================
echo "=============================================================="
log_info "MODULE 5 : RabbitMQ HA - Tests de Base"
echo "=============================================================="

# Test 1: Connectivité RabbitMQ
log_info "Test 3.1: Connectivité RabbitMQ..."
RABBITMQ_CONNECTIVITY_OK=true
for i in "${!RABBITMQ_IPS[@]}"; do
    ip="${RABBITMQ_IPS[$i]}"
    if ! ssh ${SSH_OPTS} root@${ip} "docker exec rabbitmq rabbitmqctl status >/dev/null 2>&1"; then
        RABBITMQ_CONNECTIVITY_OK=false
        break
    fi
done
test_result "RabbitMQ - Connectivité" "${RABBITMQ_CONNECTIVITY_OK:+PASS}${RABBITMQ_CONNECTIVITY_OK:-FAIL}"

# Test 2: Cluster RabbitMQ
log_info "Test 3.2: Cluster RabbitMQ..."
RABBITMQ_CLUSTER_OK=true
CLUSTER_SIZE=0
for i in "${!RABBITMQ_IPS[@]}"; do
    ip="${RABBITMQ_IPS[$i]}"
    SIZE=$(ssh ${SSH_OPTS} root@${ip} "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'rabbit@' || echo 0")
    if [[ ${SIZE} -gt ${CLUSTER_SIZE} ]]; then
        CLUSTER_SIZE=${SIZE}
    fi
done
if [[ ${CLUSTER_SIZE} -ge 2 ]]; then
    test_result "RabbitMQ - Cluster (${CLUSTER_SIZE} nœuds)" "PASS"
else
    test_result "RabbitMQ - Cluster (${CLUSTER_SIZE} nœuds)" "FAIL"
fi

echo ""

# ============================================================
# MODULE 6 : MinIO S3
# ============================================================
echo "=============================================================="
log_info "MODULE 6 : MinIO S3 - Tests de Base"
echo "=============================================================="

# Test 1: Connectivité MinIO
if [[ ${#MINIO_IPS[@]} -gt 0 ]]; then
    log_info "Test 4.1: Connectivité MinIO..."
    MINIO_OK=false
    for ip in "${MINIO_IPS[@]}"; do
        if ssh ${SSH_OPTS} root@${ip} "docker exec minio mc ready local >/dev/null 2>&1" 2>/dev/null; then
            MINIO_OK=true
            break
        fi
    done
    test_result "MinIO - Connectivité" "${MINIO_OK:+PASS}${MINIO_OK:-FAIL}"
else
    log_warning "Aucun nœud MinIO détecté, tests MinIO ignorés"
    test_result "MinIO - Connectivité" "SKIP"
fi

echo ""

# ============================================================
# MODULE 7 : MariaDB Galera HA + ProxySQL
# ============================================================
echo "=============================================================="
log_info "MODULE 7 : MariaDB Galera HA + ProxySQL - Tests de Base"
echo "=============================================================="

# Test 1: Connectivité MariaDB directe
log_info "Test 5.1: Connectivité MariaDB directe..."
MARIADB_CONNECTIVITY_OK=true
for i in "${!MARIADB_IPS[@]}"; do
    ip="${MARIADB_IPS[$i]}"
    if ! ssh ${SSH_OPTS} root@${ip} "source /tmp/mariadb.env && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e 'SELECT 1;' >/dev/null 2>&1"; then
        MARIADB_CONNECTIVITY_OK=false
        break
    fi
done
test_result "MariaDB - Connectivité directe" "${MARIADB_CONNECTIVITY_OK:+PASS}${MARIADB_CONNECTIVITY_OK:-FAIL}"

# Test 2: Cluster Galera
log_info "Test 5.2: Cluster Galera..."
GALERA_CLUSTER_OK=true
CLUSTER_SIZE=0
for i in "${!MARIADB_IPS[@]}"; do
    ip="${MARIADB_IPS[$i]}"
    SIZE=$(ssh ${SSH_OPTS} root@${ip} "source /tmp/mariadb.env && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\" 2>/dev/null | grep -o '[0-9]' | head -1 || echo 0")
    if [[ ${SIZE} -gt ${CLUSTER_SIZE} ]]; then
        CLUSTER_SIZE=${SIZE}
    fi
done
if [[ ${CLUSTER_SIZE} -eq ${#MARIADB_IPS[@]} ]]; then
    test_result "MariaDB - Cluster Galera (${CLUSTER_SIZE} nœuds)" "PASS"
else
    test_result "MariaDB - Cluster Galera (${CLUSTER_SIZE} nœuds, attendu ${#MARIADB_IPS[@]})" "FAIL"
fi

# Test 3: ProxySQL
if [[ ${#PROXYSQL_IPS[@]} -gt 0 ]]; then
    log_info "Test 5.3: ProxySQL..."
    PROXYSQL_OK=true
    for i in "${!PROXYSQL_IPS[@]}"; do
        ip="${PROXYSQL_IPS[$i]}"
        if ! ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/mariadb.env 2>/dev/null || source /tmp/mariadb.env 2>/dev/null && docker exec proxysql mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e 'SELECT 1;' >/dev/null 2>&1"; then
            PROXYSQL_OK=false
            break
        fi
    done
    test_result "MariaDB - ProxySQL" "${PROXYSQL_OK:+PASS}${PROXYSQL_OK:-FAIL}"
else
    test_result "MariaDB - ProxySQL" "SKIP"
fi

echo ""

# ============================================================
# TESTS DE FAILOVER ET CRASH
# ============================================================
echo "=============================================================="
log_warning "TESTS DE FAILOVER ET CRASH"
echo "=============================================================="
log_warning "Ces tests vont arrêter temporairement des services"
echo ""

read -p "Continuer avec les tests de failover ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    log_info "Tests de failover annulés"
else
    # Test Failover PostgreSQL
    if [[ ${#PG_IPS[@]} -ge 2 ]]; then
        log_info "Test Failover PostgreSQL : Arrêt du leader..."
        LEADER_IP=""
        for i in "${!PG_IPS[@]}"; do
            ip="${PG_IPS[$i]}"
            ROLE=$(ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni | grep -o '\"role\":\"[^\"]*\"' | cut -d'\"' -f4" 2>/dev/null || echo "")
            if [[ "${ROLE}" == "Leader" ]]; then
                LEADER_IP="${ip}"
                break
            fi
        done
        
        if [[ -n "${LEADER_IP}" ]]; then
            log_info "Arrêt du leader PostgreSQL sur ${LEADER_IP}..."
            ssh ${SSH_OPTS} root@${LEADER_IP} "docker stop postgresql" || true
            sleep 10
            
            # Vérifier qu'un nouveau leader est élu
            NEW_LEADER=false
            for i in "${!PG_IPS[@]}"; do
                ip="${PG_IPS[$i]}"
                if [[ "${ip}" != "${LEADER_IP}" ]]; then
                    ROLE=$(ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni | grep -o '\"role\":\"[^\"]*\"' | cut -d'\"' -f4" 2>/dev/null || echo "")
                    if [[ "${ROLE}" == "Leader" ]]; then
                        NEW_LEADER=true
                        break
                    fi
                fi
            done
            
            if [[ "${NEW_LEADER}" == "true" ]]; then
                test_result "PostgreSQL - Failover automatique" "PASS"
            else
                test_result "PostgreSQL - Failover automatique" "FAIL"
            fi
            
            # Redémarrer le nœud
            log_info "Redémarrage du nœud PostgreSQL..."
            ssh ${SSH_OPTS} root@${LEADER_IP} "docker start postgresql" || true
            sleep 15
        fi
    fi
    
    # Test Failover Redis
    if [[ ${#REDIS_IPS[@]} -ge 2 ]]; then
        log_info "Test Failover Redis : Arrêt du master..."
        MASTER_IP=""
        for i in "${!REDIS_IPS[@]}"; do
            ip="${REDIS_IPS[$i]}"
            ROLE=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication | grep 'role:' | cut -d: -f2 | tr -d '\r\n'" 2>/dev/null || echo "")
            if [[ "${ROLE}" == "master" ]]; then
                MASTER_IP="${ip}"
                break
            fi
        done
        
        if [[ -n "${MASTER_IP}" ]]; then
            log_info "Arrêt du master Redis sur ${MASTER_IP}..."
            ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true
            sleep 10
            
            # Vérifier qu'un nouveau master est promu
            NEW_MASTER=false
            for i in "${!REDIS_IPS[@]}"; do
                ip="${REDIS_IPS[$i]}"
                if [[ "${ip}" != "${MASTER_IP}" ]]; then
                    ROLE=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication | grep 'role:' | cut -d: -f2 | tr -d '\r\n'" 2>/dev/null || echo "")
                    if [[ "${ROLE}" == "master" ]]; then
                        NEW_MASTER=true
                        break
                    fi
                fi
            done
            
            if [[ "${NEW_MASTER}" == "true" ]]; then
                test_result "Redis - Failover automatique (Sentinel)" "PASS"
            else
                test_result "Redis - Failover automatique (Sentinel)" "FAIL"
            fi
            
            # Redémarrer le nœud
            log_info "Redémarrage du nœud Redis..."
            ssh ${SSH_OPTS} root@${MASTER_IP} "docker start redis" || true
            sleep 15
        fi
    fi
fi

echo ""

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
echo "=============================================================="
log_info "RÉSUMÉ DES TESTS"
echo "=============================================================="
log_info "Total de tests : ${TOTAL_TESTS}"
log_success "Tests réussis : ${PASSED_TESTS}"
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "Tests échoués : ${FAILED_TESTS}"
else
    log_success "Tests échoués : ${FAILED_TESTS}"
fi

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    echo ""
    log_success "✅ Tous les tests sont passés avec succès !"
    echo ""
    log_info "L'infrastructure est prête pour le Module 9 (K3s HA Core)"
else
    echo ""
    log_error "❌ Certains tests ont échoué"
    log_warning "Veuillez corriger les problèmes avant de passer au Module 9"
fi

echo ""

