#!/usr/bin/env bash
#
# 00_test_complet_infrastructure_haproxy01.sh - Tests complets de l'infrastructure
# avec vérification spécifique de haproxy-01 rebuild
#
# Ce script effectue des tests complets de tous les modules installés
# et vérifie spécifiquement haproxy-01 qui a été rebuild.
#
# Usage:
#   ./00_test_complet_infrastructure_haproxy01.sh [servers.tsv]
#
# Prérequis:
#   - Tous les modules installés (2-9)
#   - Exécuter depuis install-01

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="${INSTALL_DIR}/logs"
MAIN_LOG="${LOG_DIR}/test_complet_infrastructure_${TIMESTAMP}.log"
ERROR_LOG="${LOG_DIR}/test_complet_errors_${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

# Fonctions de log
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${MAIN_LOG}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${MAIN_LOG}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${MAIN_LOG}" "${ERROR_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${MAIN_LOG}"
}

log_section() {
    echo -e "${CYAN}==============================================================${NC}" | tee -a "${MAIN_LOG}"
    echo -e "${CYAN}$1${NC}" | tee -a "${MAIN_LOG}"
    echo -e "${CYAN}==============================================================${NC}" | tee -a "${MAIN_LOG}"
}

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Fonction de test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_output="${3:-}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${MAIN_LOG}"
    
    if [[ -n "${expected_output}" ]]; then
        # Test avec vérification de sortie
        output=$(eval "${test_command}" 2>&1)
        if echo "${output}" | grep -q "${expected_output}"; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_error "ÉCHEC"
            log_error "  Sortie: ${output}" | tee -a "${ERROR_LOG}"
            ((FAILED_TESTS++))
            return 1
        fi
    else
        # Test simple (code retour)
        if eval "${test_command}" > /dev/null 2>&1; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_error "ÉCHEC"
            ((FAILED_TESTS++))
            return 1
        fi
    fi
}

# Header
clear
log_section "[KeyBuzz] Tests Complets Infrastructure avec Vérification haproxy-01"
echo ""
log_info "Date: $(date)"
log_info "Log principal: ${MAIN_LOG}"
log_info "Log erreurs: ${ERROR_LOG}"
echo ""

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
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

# Options SSH
SSH_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

# ============================================================
# PARTIE 1: VÉRIFICATION SPÉCIALE haproxy-01 (REBUILD)
# ============================================================
log_section "PARTIE 1: Vérification haproxy-01 (Rebuild)"

HAPROXY01_IP=""
HAPROXY02_IP=""

# Lire servers.tsv
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "haproxy-01" ]]; then
        HAPROXY01_IP="${IP_PRIVEE}"
    elif [[ "${HOSTNAME}" == "haproxy-02" ]]; then
        HAPROXY02_IP="${IP_PRIVEE}"
    fi
done
exec 3<&-

if [[ -z "${HAPROXY01_IP}" ]]; then
    log_error "haproxy-01 non trouvé dans servers.tsv"
    exit 1
fi

log_info "haproxy-01 IP: ${HAPROXY01_IP}"
log_info "haproxy-02 IP: ${HAPROXY02_IP}"

echo ""

# Test 1: Connectivité SSH haproxy-01
log_info "Vérification connectivité SSH..."
run_test "SSH haproxy-01" "ssh ${SSH_OPTS} root@${HAPROXY01_IP} 'echo OK'"

# Test 2: Docker installé et fonctionnel
log_info "Vérification Docker..."
run_test "Docker installé haproxy-01" "ssh ${SSH_OPTS} root@${HAPROXY01_IP} 'docker --version'"

# Test 3: Services HAProxy
log_info "Vérification services HAProxy..."
HA_PROXY_STATUS=$(ssh ${SSH_OPTS} root@${HAPROXY01_IP} 'systemctl is-active haproxy-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
if [[ "${HA_PROXY_STATUS}" == "active" ]]; then
    log_success "Service HAProxy actif sur haproxy-01"
    ((PASSED_TESTS++))
else
    log_error "Service HAProxy inactif sur haproxy-01 (status: ${HA_PROXY_STATUS})"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Test 4: Conteneurs Docker sur haproxy-01
log_info "Vérification conteneurs Docker..."
CONTAINERS=$(ssh ${SSH_OPTS} root@${HAPROXY01_IP} 'docker ps --format "{{.Names}}" 2>/dev/null' 2>/dev/null || echo "")
if [[ -z "${CONTAINERS}" ]]; then
    log_warning "Aucun conteneur Docker en cours d'exécution sur haproxy-01"
    log_info "haproxy-01 semble avoir été rebuild mais pas réinstallé"
    ((WARNING_TESTS++))
    HAPROXY01_NEEDS_REINSTALL=true
else
    log_success "Conteneurs Docker détectés: ${CONTAINERS}"
    HAPROXY01_NEEDS_REINSTALL=false
fi
((TOTAL_TESTS++))

# Test 5: Configuration HAProxy présente
log_info "Vérification configuration HAProxy..."
HAPROXY_CFG=$(ssh ${SSH_OPTS} root@${HAPROXY01_IP} 'test -f /etc/haproxy/haproxy.cfg && echo exists || echo missing' 2>/dev/null || echo "missing")
if [[ "${HAPROXY_CFG}" == "exists" ]]; then
    log_success "Configuration HAProxy présente"
    ((PASSED_TESTS++))
else
    log_error "Configuration HAProxy manquante"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Test 6: Ports HAProxy accessibles
log_info "Vérification ports HAProxy..."
PORTS=(5432 6432 6379 5672 8404)
for port in "${PORTS[@]}"; do
    if nc -z -w2 ${HAPROXY01_IP} ${port} 2>/dev/null; then
        log_success "Port ${port} accessible sur haproxy-01"
        ((PASSED_TESTS++))
    else
        log_warning "Port ${port} non accessible sur haproxy-01"
        ((WARNING_TESTS++))
    fi
    ((TOTAL_TESTS++))
done

echo ""

# ============================================================
# PARTIE 2: MODULE 3 - PostgreSQL HA
# ============================================================
log_section "PARTIE 2: Module 3 - PostgreSQL HA (Patroni)"

PG_MASTER_IP=""
PG_SLAVE_IPS=()
DB_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" && "${SUBROLE}" == "postgres" ]]; then
        if [[ "${HOSTNAME}" == "db-master-01" ]]; then
            PG_MASTER_IP="${IP_PRIVEE}"
        else
            PG_SLAVE_IPS+=("${IP_PRIVEE}")
        fi
        DB_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ -n "${PG_MASTER_IP}" ]]; then
    log_info "Master PostgreSQL: ${PG_MASTER_IP}"
    log_info "Slaves PostgreSQL: ${PG_SLAVE_IPS[*]}"
    
    # Test 1: Connectivité PostgreSQL Master
    run_test "Connectivité PostgreSQL Master" \
        "ssh ${SSH_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -c \"SELECT version();\" > /dev/null 2>&1'"
    
    # Test 2: Patroni cluster status
    PATRONI_STATUS=$(ssh ${SSH_OPTS} root@${PG_MASTER_IP} 'docker exec patroni patronictl list 2>/dev/null' 2>/dev/null || echo "")
    if echo "${PATRONI_STATUS}" | grep -q "Leader\|Replica"; then
        log_success "Patroni cluster opérationnel"
        echo "${PATRONI_STATUS}" | tee -a "${MAIN_LOG}"
        ((PASSED_TESTS++))
    else
        log_error "Patroni cluster non opérationnel"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 3: Réplication
    REPLICA_COUNT=$(ssh ${SSH_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null' | tr -d ' ' || echo "0")
    if [[ "${REPLICA_COUNT}" =~ ^[1-9] ]]; then
        log_success "Réplication active (${REPLICA_COUNT} réplicas)"
        ((PASSED_TESTS++))
    else
        log_warning "Pas de réplication active (${REPLICA_COUNT} réplicas)"
        ((WARNING_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 4: HAProxy PostgreSQL (via 10.0.0.10 ou directement)
    log_info "Test HAProxy PostgreSQL..."
    if nc -z -w2 10.0.0.10 5432 2>/dev/null; then
        run_test "HAProxy PostgreSQL (10.0.0.10:5432)" \
            "PGPASSWORD=\${POSTGRES_PASSWORD:-} psql -h 10.0.0.10 -p 5432 -U postgres -d postgres -c 'SELECT 1;' > /dev/null 2>&1" || {
            log_warning "Test via LB 10.0.0.10 échoué, test direct..."
            run_test "HAProxy PostgreSQL direct (haproxy-01:5432)" \
                "nc -z -w2 ${HAPROXY01_IP} 5432"
        }
    else
        log_warning "LB 10.0.0.10 non accessible, test direct haproxy-01"
        run_test "HAProxy PostgreSQL direct (haproxy-01:5432)" \
            "nc -z -w2 ${HAPROXY01_IP} 5432"
    fi
    
    # Test 5: PgBouncer
    log_info "Test PgBouncer..."
    PGBOUNCER_IP="${HAPROXY01_IP}"
    if ssh ${SSH_OPTS} root@${PGBOUNCER_IP} 'docker ps | grep -q pgbouncer' 2>/dev/null; then
        run_test "PgBouncer conteneur actif" \
            "ssh ${SSH_OPTS} root@${PGBOUNCER_IP} 'docker exec pgbouncer psql -h localhost -p 6432 -U postgres -d postgres -c \"SELECT 1;\" > /dev/null 2>&1'"
    else
        log_warning "PgBouncer non installé ou non actif sur haproxy-01"
        ((WARNING_TESTS++))
        ((TOTAL_TESTS++))
    fi
    
    echo ""
else
    log_warning "Module 3 : PostgreSQL non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 3: MODULE 4 - Redis HA
# ============================================================
log_section "PARTIE 3: Module 4 - Redis HA (Sentinel)"

REDIS_NODES=()
REDIS_MASTER_IP=""

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "redis" ]]; then
        REDIS_NODES+=("${IP_PRIVEE}")
        if [[ "${SUBROLE}" == "master" ]]; then
            REDIS_MASTER_IP="${IP_PRIVEE}"
        fi
    fi
done
exec 3<&-

if [[ ${#REDIS_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds Redis: ${REDIS_NODES[*]}"
    
    # Charger credentials Redis
    REDIS_PASSWORD=""
    if [[ -f "${INSTALL_DIR}/credentials/redis.env" ]]; then
        source "${INSTALL_DIR}/credentials/redis.env"
        REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    fi
    
    # Test 1: Détection du master Redis
    log_info "Détection du master Redis..."
    for redis_ip in "${REDIS_NODES[@]}"; do
        if [[ -n "${REDIS_PASSWORD}" ]]; then
            ROLE=$(ssh ${SSH_OPTS} root@${redis_ip} "docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n'" 2>/dev/null || echo "")
        else
            ROLE=$(ssh ${SSH_OPTS} root@${redis_ip} "docker exec redis redis-cli INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n'" 2>/dev/null || echo "")
        fi
        
        if [[ "${ROLE}" == "master" ]]; then
            REDIS_MASTER_IP="${redis_ip}"
            log_success "Master Redis détecté: ${redis_ip}"
            ((PASSED_TESTS++))
            break
        fi
    done
    
    if [[ -z "${REDIS_MASTER_IP}" ]]; then
        log_error "Aucun master Redis détecté"
        ((FAILED_TESTS++))
        REDIS_MASTER_IP="${REDIS_NODES[0]}"
    fi
    ((TOTAL_TESTS++))
    
    # Test 2: Connectivité Redis
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        run_test "Connectivité Redis (avec auth)" \
            "ssh ${SSH_OPTS} root@${REDIS_MASTER_IP} \"docker exec redis redis-cli -a '${REDIS_PASSWORD}' ping\" | grep -q PONG"
    else
        run_test "Connectivité Redis" \
            "ssh ${SSH_OPTS} root@${REDIS_MASTER_IP} 'docker exec redis redis-cli ping' | grep -q PONG"
    fi
    
    # Test 3: Réplication Redis
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        run_test "Réplication Redis active" \
            "ssh ${SSH_OPTS} root@${REDIS_MASTER_IP} \"docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication\" | grep -q 'connected_slaves:[1-9]'"
    else
        run_test "Réplication Redis active" \
            "ssh ${SSH_OPTS} root@${REDIS_MASTER_IP} 'docker exec redis redis-cli INFO replication' | grep -q 'connected_slaves:[1-9]'"
    fi
    
    # Test 4: HAProxy Redis
    run_test "HAProxy Redis (10.0.0.10:6379)" \
        "nc -z -w2 10.0.0.10 6379" || \
        run_test "HAProxy Redis direct (haproxy-01:6379)" \
            "nc -z -w2 ${HAPROXY01_IP} 6379"
    
    # Test 5: Sentinel
    SENTINEL_IP="${REDIS_NODES[0]}"
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        run_test "Sentinel status" \
            "ssh ${SSH_OPTS} root@${SENTINEL_IP} \"docker exec sentinel redis-cli -a '${REDIS_PASSWORD}' -p 26379 SENTINEL masters\" | grep -q 'mymaster\|kb-redis-master'"
    else
        run_test "Sentinel status" \
            "ssh ${SSH_OPTS} root@${SENTINEL_IP} 'docker exec sentinel redis-cli -p 26379 SENTINEL masters' | grep -q 'mymaster\|kb-redis-master'"
    fi
    
    echo ""
else
    log_warning "Module 4 : Redis non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 4: MODULE 5 - RabbitMQ HA
# ============================================================
log_section "PARTIE 4: Module 5 - RabbitMQ HA (Quorum)"

RABBITMQ_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "queue" && "${SUBROLE}" == "rabbitmq" ]]; then
        RABBITMQ_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#RABBITMQ_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds RabbitMQ: ${RABBITMQ_NODES[*]}"
    
    RABBITMQ_IP="${RABBITMQ_NODES[0]}"
    
    # Test 1: Connectivité RabbitMQ
    run_test "Connectivité RabbitMQ" \
        "ssh ${SSH_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl status' > /dev/null 2>&1"
    
    # Test 2: Cluster RabbitMQ
    CLUSTER_STATUS=$(ssh ${SSH_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null' 2>/dev/null || echo "")
    if echo "${CLUSTER_STATUS}" | grep -q "running_nodes"; then
        log_success "Cluster RabbitMQ formé"
        ((PASSED_TESTS++))
    else
        log_error "Cluster RabbitMQ non formé"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 3: HAProxy RabbitMQ
    run_test "HAProxy RabbitMQ (10.0.0.10:5672)" \
        "nc -z -w2 10.0.0.10 5672" || \
        run_test "HAProxy RabbitMQ direct (haproxy-01:5672)" \
            "nc -z -w2 ${HAPROXY01_IP} 5672"
    
    echo ""
else
    log_warning "Module 5 : RabbitMQ non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 5: MODULE 6 - MinIO
# ============================================================
log_section "PARTIE 5: Module 6 - MinIO"

MINIO_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "storage" && "${SUBROLE}" == "minio" ]]; then
        MINIO_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#MINIO_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds MinIO: ${MINIO_NODES[*]}"
    
    MINIO_IP="${MINIO_NODES[0]}"
    
    # Test 1: Connectivité MinIO
    run_test "Connectivité MinIO (port 9000)" \
        "nc -z -w2 ${MINIO_IP} 9000"
    
    # Test 2: Console MinIO
    run_test "Console MinIO (port 9001)" \
        "nc -z -w2 ${MINIO_IP} 9001"
    
    # Test 3: Conteneur MinIO actif
    run_test "Conteneur MinIO actif" \
        "ssh ${SSH_OPTS} root@${MINIO_IP} 'docker ps | grep -q minio'"
    
    echo ""
else
    log_warning "Module 6 : MinIO non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 6: MODULE 7 - MariaDB Galera
# ============================================================
log_section "PARTIE 6: Module 7 - MariaDB Galera"

MARIADB_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" && "${SUBROLE}" == "mariadb" ]]; then
        MARIADB_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#MARIADB_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds MariaDB: ${MARIADB_NODES[*]}"
    
    MARIADB_IP="${MARIADB_NODES[0]}"
    
    # Charger credentials MariaDB
    MARIADB_PASSWORD=""
    if [[ -f "${INSTALL_DIR}/credentials/mariadb.env" ]]; then
        source "${INSTALL_DIR}/credentials/mariadb.env"
        MARIADB_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
    fi
    
    # Test 1: Connectivité MariaDB
    if [[ -n "${MARIADB_PASSWORD}" ]]; then
        run_test "Connectivité MariaDB (avec auth)" \
            "ssh ${SSH_OPTS} root@${MARIADB_IP} \"docker exec mariadb mysql -uroot -p'${MARIADB_PASSWORD}' -e 'SELECT 1;' > /dev/null 2>&1\""
    else
        run_test "Connectivité MariaDB" \
            "nc -z -w2 ${MARIADB_IP} 3306"
    fi
    
    # Test 2: Cluster Galera
    if [[ -n "${MARIADB_PASSWORD}" ]]; then
        WSREP_STATUS=$(ssh ${SSH_OPTS} root@${MARIADB_IP} "docker exec mariadb mysql -uroot -p'${MARIADB_PASSWORD}' -e 'SHOW STATUS LIKE \"wsrep_cluster_size\";' 2>/dev/null" 2>/dev/null || echo "")
        if echo "${WSREP_STATUS}" | grep -q "wsrep_cluster_size"; then
            log_success "Cluster Galera opérationnel"
            ((PASSED_TESTS++))
        else
            log_warning "Cluster Galera non vérifiable"
            ((WARNING_TESTS++))
        fi
    else
        log_warning "Impossible de vérifier cluster Galera (pas de credentials)"
        ((WARNING_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
else
    log_warning "Module 7 : MariaDB non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 7: MODULE 8 - ProxySQL
# ============================================================
log_section "PARTIE 7: Module 8 - ProxySQL"

PROXYSQL_NODES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db_proxy" && "${SUBROLE}" == "proxysql" ]]; then
        PROXYSQL_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#PROXYSQL_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds ProxySQL: ${PROXYSQL_NODES[*]}"
    
    PROXYSQL_IP="${PROXYSQL_NODES[0]}"
    
    # Test 1: Connectivité ProxySQL
    run_test "Connectivité ProxySQL (port 3306)" \
        "nc -z -w2 ${PROXYSQL_IP} 3306"
    
    # Test 2: Conteneur ProxySQL actif
    run_test "Conteneur ProxySQL actif" \
        "ssh ${SSH_OPTS} root@${PROXYSQL_IP} 'docker ps | grep -q proxysql'"
    
    # Test 3: LB 10.0.0.20 (ProxySQL)
    run_test "LB ProxySQL (10.0.0.20:3306)" \
        "nc -z -w2 10.0.0.20 3306"
    
    echo ""
else
    log_warning "Module 8 : ProxySQL non trouvé"
    echo ""
fi

# ============================================================
# PARTIE 8: MODULE 9 - K3s HA
# ============================================================
log_section "PARTIE 8: Module 9 - K3s HA"

K3S_MASTER_IPS=()
K3S_WORKER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]]; then
        if [[ "${SUBROLE}" == "master" ]]; then
            K3S_MASTER_IPS+=("${IP_PRIVEE}")
        elif [[ "${SUBROLE}" == "worker" ]]; then
            K3S_WORKER_IPS+=("${IP_PRIVEE}")
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -gt 0 ]]; then
    log_info "Masters K3s: ${K3S_MASTER_IPS[*]}"
    log_info "Workers K3s: ${K3S_WORKER_IPS[*]}"
    
    K3S_MASTER_IP="${K3S_MASTER_IPS[0]}"
    
    # Test 1: Service K3s actif sur master
    run_test "Service K3s actif sur master" \
        "ssh ${SSH_OPTS} root@${K3S_MASTER_IP} 'systemctl is-active k3s'"
    
    # Test 2: kubectl fonctionnel
    KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
    if ssh ${SSH_OPTS} root@${K3S_MASTER_IP} "test -f ${KUBECONFIG}" 2>/dev/null; then
        K3S_NODES=$(ssh ${SSH_OPTS} root@${K3S_MASTER_IP} "kubectl get nodes 2>/dev/null | grep -c Ready" 2>/dev/null || echo "0")
        if [[ "${K3S_NODES}" -ge 3 ]]; then
            log_success "Cluster K3s opérationnel (${K3S_NODES} nœuds Ready)"
            ((PASSED_TESTS++))
        else
            log_warning "Cluster K3s partiellement opérationnel (${K3S_NODES} nœuds Ready)"
            ((WARNING_TESTS++))
        fi
        ((TOTAL_TESTS++))
    else
        log_error "kubeconfig non trouvé"
        ((FAILED_TESTS++))
        ((TOTAL_TESTS++))
    fi
    
    # Test 3: Ingress NGINX
    if ssh ${SSH_OPTS} root@${K3S_MASTER_IP} "kubectl get daemonset -n ingress-nginx ingress-nginx-controller 2>/dev/null" | grep -q "ingress-nginx-controller"; then
        log_success "Ingress NGINX DaemonSet présent"
        ((PASSED_TESTS++))
    else
        log_warning "Ingress NGINX DaemonSet non trouvé"
        ((WARNING_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
else
    log_warning "Module 9 : K3s non trouvé"
    echo ""
fi

# ============================================================
# RÉSUMÉ ET RECOMMANDATIONS
# ============================================================
log_section "RÉSUMÉ DES TESTS"

echo ""
log_info "Total de tests: ${TOTAL_TESTS}"
log_success "Tests réussis: ${PASSED_TESTS}"
log_error "Tests échoués: ${FAILED_TESTS}"
log_warning "Tests avec avertissements: ${WARNING_TESTS}"

SUCCESS_RATE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
log_info "Taux de réussite: ${SUCCESS_RATE}%"

echo ""

# Recommandations spécifiques pour haproxy-01
if [[ "${HAPROXY01_NEEDS_REINSTALL:-false}" == "true" ]]; then
    log_section "⚠️ ACTION REQUISE: haproxy-01"
    echo ""
    log_warning "haproxy-01 a été rebuild mais n'a pas été réinstallé"
    log_info "Actions à effectuer:"
    echo "  1. Appliquer Module 2 (Base OS & Sécurité) sur haproxy-01"
    echo "  2. Réinstaller Module 3 (PostgreSQL HA - HAProxy + PgBouncer)"
    echo "  3. Réinstaller Module 4 (Redis HA - HAProxy Redis)"
    echo "  4. Réinstaller Module 5 (RabbitMQ HA - HAProxy RabbitMQ)"
    echo ""
    log_info "Scripts à exécuter (dans l'ordre):"
    echo "  cd ${INSTALL_DIR}/scripts/02_base_os_and_security"
    echo "  ./apply_base_os_to_all.sh ../../servers.tsv --host haproxy-01"
    echo ""
    echo "  cd ${INSTALL_DIR}/scripts/03_postgresql_ha"
    echo "  ./03_pg_03_install_haproxy_db_lb.sh ../../servers.tsv"
    echo ""
fi

# Recommandations générales
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_section "⚠️ ERREURS DÉTECTÉES"
    echo ""
    log_info "Consultez le log d'erreurs: ${ERROR_LOG}"
    log_info "Vérifiez les services ayant échoué et réinstallez si nécessaire"
    echo ""
fi

# Résumé final
log_section "FIN DES TESTS"
log_info "Log complet: ${MAIN_LOG}"
log_info "Log erreurs: ${ERROR_LOG}"

exit 0

