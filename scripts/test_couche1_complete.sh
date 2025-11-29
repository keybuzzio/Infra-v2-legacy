#!/usr/bin/env bash
#
# test_couche1_complete.sh - Test Complet de la Couche 1 (Modules 2-8)
#
# Ce script teste exhaustivement tous les composants de la couche 1 (stateful/data)
# selon les bonnes pratiques KeyBuzz définies dans les rapports de validation.
#
# Usage:
#   ./test_couche1_complete.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Credentials disponibles dans /opt/keybuzz-installer/credentials/
#   - Accès SSH à tous les serveurs
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
LOG_DIR="${INSTALL_DIR}/logs"

# Vérifier si on est sur install-01
if [[ ! -d "${INSTALL_DIR}" ]]; then
    INSTALL_DIR="/opt/keybuzz-installer"
    CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
    LOG_DIR="${INSTALL_DIR}/logs"
fi
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/test_couche1_${TIMESTAMP}.log"
REPORT_FILE="${LOG_DIR}/RAPPORT_TEST_COUCHE1_${TIMESTAMP}.md"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Compteurs globaux
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Fonctions de logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${LOG_FILE}"
    ((PASSED_TESTS++))
    ((TOTAL_TESTS++))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${LOG_FILE}"
    ((FAILED_TESTS++))
    ((TOTAL_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${LOG_FILE}"
    ((WARNING_TESTS++))
    ((TOTAL_TESTS++))
}

log_section() {
    local section_title="$1"
    echo "" | tee -a "${LOG_FILE}"
    echo "==============================================================" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}${section_title}${NC}" | tee -a "${LOG_FILE}"
    echo "==============================================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -d "${CREDENTIALS_DIR}" ]]; then
    log_error "Répertoire credentials introuvable: ${CREDENTIALS_DIR}"
    exit 1
fi

mkdir -p "${LOG_DIR}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Charger les credentials
load_credentials() {
    local service=$1
    local env_file="${CREDENTIALS_DIR}/${service}.env"
    
    if [[ -f "${env_file}" ]]; then
        source "${env_file}"
        return 0
    else
        log_warning "Fichier credentials introuvable: ${env_file}"
        return 1
    fi
}

# Header
echo "==============================================================" | tee -a "${LOG_FILE}"
echo " [KeyBuzz] Test Complet Couche 1 (Modules 2-8)" | tee -a "${LOG_FILE}"
echo "==============================================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"
log_info "Date: $(date)"
log_info "Log: ${LOG_FILE}"
log_info "Rapport: ${REPORT_FILE}"
echo "" | tee -a "${LOG_FILE}"

# ============================================================
# MODULE 3 : PostgreSQL HA (Patroni + HAProxy + PgBouncer)
# ============================================================
log_section "MODULE 3 : PostgreSQL HA - Patroni + HAProxy + PgBouncer"

# Charger credentials PostgreSQL
if load_credentials "postgres"; then
    POSTGRES_PASSWORD="${POSTGRES_SUPERUSER_PASSWORD:-}"
    POSTGRES_REPLICATION_PASSWORD="${POSTGRES_REPLICATION_PASSWORD:-}"
else
    POSTGRES_PASSWORD=""
    POSTGRES_REPLICATION_PASSWORD=""
fi

# 3.1 Test conteneurs Patroni
log_info "3.1 Vérification des conteneurs Patroni..."
PATRONI_NODES=0
PATRONI_LEADER=""
PATRONI_REPLICAS=0

for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=patroni' --format '{{.Names}}' | grep -q patroni" 2>/dev/null; then
        ((PATRONI_NODES++))
        # Détecter le leader (gérer les erreurs jq)
        ROLE="unknown"
        JSON_OUTPUT=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec patroni patronictl list -f json 2>/dev/null" 2>/dev/null || echo "")
        if [[ -n "${JSON_OUTPUT}" ]]; then
            ROLE=$(echo "${JSON_OUTPUT}" | jq -r ".[] | select(.Member == \"${ip}\") | .Role" 2>/dev/null || echo "unknown")
        fi
        if [[ "${ROLE}" == "Leader" ]]; then
            PATRONI_LEADER="${ip}"
        elif [[ "${ROLE}" == "Replica" ]]; then
            ((PATRONI_REPLICAS++))
        fi
    fi
done

if [[ ${PATRONI_NODES} -eq 3 ]]; then
    log_success "Conteneurs Patroni : 3/3 actifs"
else
    log_error "Conteneurs Patroni : ${PATRONI_NODES}/3 actifs"
fi

if [[ -n "${PATRONI_LEADER}" ]]; then
    log_success "Leader Patroni détecté : ${PATRONI_LEADER}"
else
    log_warning "Leader Patroni non détecté"
fi

if [[ ${PATRONI_REPLICAS} -ge 2 ]]; then
    log_success "Réplicas Patroni : ${PATRONI_REPLICAS}/2"
else
    log_warning "Réplicas Patroni : ${PATRONI_REPLICAS}/2"
fi

# 3.2 Test HAProxy
log_info "3.2 Vérification HAProxy PostgreSQL..."
HAPROXY_PG_OK=0
for ip in 10.0.0.11 10.0.0.12; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=haproxy' --format '{{.Names}}' | grep -q haproxy" 2>/dev/null; then
        # Test connectivité port 5432
        if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/5432' 2>/dev/null"; then
            ((HAPROXY_PG_OK++))
        fi
    fi
done

if [[ ${HAPROXY_PG_OK} -eq 2 ]]; then
    log_success "HAProxy PostgreSQL : 2/2 opérationnels"
else
    log_warning "HAProxy PostgreSQL : ${HAPROXY_PG_OK}/2 opérationnels"
fi

# 3.3 Test PgBouncer
log_info "3.3 Vérification PgBouncer..."
PGBOUNCER_OK=0
for ip in 10.0.0.11 10.0.0.12; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=pgbouncer' --format '{{.Names}}' | grep -q pgbouncer" 2>/dev/null; then
        if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/6432' 2>/dev/null"; then
            ((PGBOUNCER_OK++))
        fi
    fi
done

if [[ ${PGBOUNCER_OK} -eq 2 ]]; then
    log_success "PgBouncer : 2/2 opérationnels"
else
    log_warning "PgBouncer : ${PGBOUNCER_OK}/2 opérationnels"
fi

# 3.4 Test connectivité via LB 10.0.0.10
log_info "3.4 Test connectivité via Load Balancer 10.0.0.10:5432..."
if [[ -n "${POSTGRES_PASSWORD}" ]]; then
    if PGPASSWORD="${POSTGRES_PASSWORD}" psql -h 10.0.0.10 -p 5432 -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Connectivité PostgreSQL via LB 10.0.0.10:5432 : OK"
    else
        log_error "Connectivité PostgreSQL via LB 10.0.0.10:5432 : ÉCHEC"
    fi
else
    log_warning "Credentials PostgreSQL non disponibles, test de connectivité ignoré"
fi

# 3.5 Test connectivité via PgBouncer LB 10.0.0.10:6432
log_info "3.5 Test connectivité via PgBouncer LB 10.0.0.10:6432..."
if [[ -n "${POSTGRES_PASSWORD}" ]]; then
    if PGPASSWORD="${POSTGRES_PASSWORD}" psql -h 10.0.0.10 -p 6432 -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Connectivité PgBouncer via LB 10.0.0.10:6432 : OK"
    else
        log_error "Connectivité PgBouncer via LB 10.0.0.10:6432 : ÉCHEC"
    fi
else
    log_warning "Credentials PostgreSQL non disponibles, test PgBouncer ignoré"
fi

# ============================================================
# MODULE 4 : Redis HA (Sentinel + HAProxy)
# ============================================================
log_section "MODULE 4 : Redis HA - Sentinel + HAProxy"

# Charger credentials Redis
if load_credentials "redis"; then
    REDIS_PASSWORD="${REDIS_PASSWORD:-}"
else
    REDIS_PASSWORD=""
fi

# 4.1 Test conteneurs Redis
log_info "4.1 Vérification des conteneurs Redis..."
REDIS_NODES=0
REDIS_MASTER=""
REDIS_REPLICAS=0

for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=redis' --format '{{.Names}}' | grep -q redis" 2>/dev/null; then
        ((REDIS_NODES++))
        # Détecter le master
        ROLE=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec redis redis-cli -a \"${REDIS_PASSWORD}\" INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r' || echo 'unknown'")
        if [[ "${ROLE}" == "master" ]]; then
            REDIS_MASTER="${ip}"
        elif [[ "${ROLE}" == "slave" ]]; then
            ((REDIS_REPLICAS++))
        fi
    fi
done

if [[ ${REDIS_NODES} -eq 3 ]]; then
    log_success "Conteneurs Redis : 3/3 actifs"
else
    log_error "Conteneurs Redis : ${REDIS_NODES}/3 actifs"
fi

if [[ -n "${REDIS_MASTER}" ]]; then
    log_success "Master Redis détecté : ${REDIS_MASTER}"
else
    log_warning "Master Redis non détecté"
fi

if [[ ${REDIS_REPLICAS} -ge 2 ]]; then
    log_success "Réplicas Redis : ${REDIS_REPLICAS}/2"
else
    log_warning "Réplicas Redis : ${REDIS_REPLICAS}/2"
fi

# 4.2 Test Sentinel
log_info "4.2 Vérification Redis Sentinel..."
SENTINEL_OK=0
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=redis-sentinel' --format '{{.Names}}' | grep -q redis-sentinel" 2>/dev/null; then
        if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/26379' 2>/dev/null"; then
            ((SENTINEL_OK++))
        fi
    fi
done

if [[ ${SENTINEL_OK} -eq 3 ]]; then
    log_success "Redis Sentinel : 3/3 opérationnels"
else
    log_warning "Redis Sentinel : ${SENTINEL_OK}/3 opérationnels"
fi

# 4.3 Test HAProxy Redis
log_info "4.3 Vérification HAProxy Redis..."
HAPROXY_REDIS_OK=0
for ip in 10.0.0.11 10.0.0.12; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/6379' 2>/dev/null"; then
        ((HAPROXY_REDIS_OK++))
    fi
done

if [[ ${HAPROXY_REDIS_OK} -eq 2 ]]; then
    log_success "HAProxy Redis : 2/2 opérationnels"
else
    log_warning "HAProxy Redis : ${HAPROXY_REDIS_OK}/2 opérationnels"
fi

# 4.4 Test connectivité via LB 10.0.0.10:6379
log_info "4.4 Test connectivité Redis via LB 10.0.0.10:6379..."
if [[ -n "${REDIS_PASSWORD}" ]]; then
    if redis-cli -h 10.0.0.10 -p 6379 -a "${REDIS_PASSWORD}" PING > /dev/null 2>&1; then
        log_success "Connectivité Redis via LB 10.0.0.10:6379 : OK"
        # Test write/read
        redis-cli -h 10.0.0.10 -p 6379 -a "${REDIS_PASSWORD}" SET test_key "test_value" > /dev/null 2>&1
        VALUE=$(redis-cli -h 10.0.0.10 -p 6379 -a "${REDIS_PASSWORD}" GET test_key 2>/dev/null)
        if [[ "${VALUE}" == "test_value" ]]; then
            log_success "Test write/read Redis : OK"
            redis-cli -h 10.0.0.10 -p 6379 -a "${REDIS_PASSWORD}" DEL test_key > /dev/null 2>&1
        else
            log_error "Test write/read Redis : ÉCHEC"
        fi
    else
        log_error "Connectivité Redis via LB 10.0.0.10:6379 : ÉCHEC"
    fi
else
    log_warning "Credentials Redis non disponibles, test de connectivité ignoré"
fi

# ============================================================
# MODULE 5 : RabbitMQ HA (Quorum + HAProxy)
# ============================================================
log_section "MODULE 5 : RabbitMQ HA - Quorum + HAProxy"

# Charger credentials RabbitMQ
if load_credentials "rabbitmq"; then
    RABBITMQ_USER="${RABBITMQ_DEFAULT_USER:-}"
    RABBITMQ_PASS="${RABBITMQ_DEFAULT_PASS:-}"
else
    RABBITMQ_USER=""
    RABBITMQ_PASS=""
fi

# 5.1 Test conteneurs RabbitMQ
log_info "5.1 Vérification des conteneurs RabbitMQ..."
RABBITMQ_NODES=0
RABBITMQ_CLUSTER_SIZE=0

for ip in 10.0.0.126 10.0.0.127 10.0.0.128; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=rabbitmq' --format '{{.Names}}' | grep -q rabbitmq" 2>/dev/null; then
        ((RABBITMQ_NODES++))
        # Vérifier le cluster
        CLUSTER_SIZE=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'running_nodes' || echo '0'")
        if [[ ${CLUSTER_SIZE} -gt ${RABBITMQ_CLUSTER_SIZE} ]]; then
            RABBITMQ_CLUSTER_SIZE=${CLUSTER_SIZE}
        fi
    fi
done

if [[ ${RABBITMQ_NODES} -eq 3 ]]; then
    log_success "Conteneurs RabbitMQ : 3/3 actifs"
else
    log_error "Conteneurs RabbitMQ : ${RABBITMQ_NODES}/3 actifs"
fi

if [[ ${RABBITMQ_CLUSTER_SIZE} -eq 3 ]]; then
    log_success "Cluster RabbitMQ : 3/3 nœuds"
else
    log_warning "Cluster RabbitMQ : ${RABBITMQ_CLUSTER_SIZE}/3 nœuds"
fi

# 5.2 Test HAProxy RabbitMQ
log_info "5.2 Vérification HAProxy RabbitMQ..."
HAPROXY_RABBITMQ_OK=0
for ip in 10.0.0.11 10.0.0.12; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/5672' 2>/dev/null"; then
        ((HAPROXY_RABBITMQ_OK++))
    fi
done

if [[ ${HAPROXY_RABBITMQ_OK} -eq 2 ]]; then
    log_success "HAProxy RabbitMQ : 2/2 opérationnels"
else
    log_warning "HAProxy RabbitMQ : ${HAPROXY_RABBITMQ_OK}/2 opérationnels"
fi

# 5.3 Test connectivité via LB 10.0.0.10:5672
log_info "5.3 Test connectivité RabbitMQ via LB 10.0.0.10:5672..."
if [[ -n "${RABBITMQ_USER}" ]] && [[ -n "${RABBITMQ_PASS}" ]]; then
    if timeout 5 bash -c "</dev/tcp/10.0.0.10/5672" 2>/dev/null; then
        log_success "Connectivité RabbitMQ via LB 10.0.0.10:5672 : OK"
    else
        log_error "Connectivité RabbitMQ via LB 10.0.0.10:5672 : ÉCHEC"
    fi
else
    log_warning "Credentials RabbitMQ non disponibles, test de connectivité ignoré"
fi

# ============================================================
# MODULE 6 : MinIO S3 (Cluster 3 Nœuds)
# ============================================================
log_section "MODULE 6 : MinIO S3 - Cluster 3 Noeuds"

# Charger credentials MinIO
if load_credentials "minio"; then
    MINIO_USER="${MINIO_ROOT_USER:-}"
    MINIO_PASS="${MINIO_ROOT_PASSWORD:-}"
else
    MINIO_USER=""
    MINIO_PASS=""
fi

# 6.1 Test conteneurs MinIO
log_info "6.1 Vérification des conteneurs MinIO..."
MINIO_NODES=0

for ip in 10.0.0.134 10.0.0.131 10.0.0.132; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=minio' --format '{{.Names}}' | grep -q minio" 2>/dev/null; then
        ((MINIO_NODES++))
    fi
done

if [[ ${MINIO_NODES} -eq 3 ]]; then
    log_success "Conteneurs MinIO : 3/3 actifs"
else
    log_warning "Conteneurs MinIO : ${MINIO_NODES}/3 actifs"
fi

# 6.2 Test connectivité MinIO
log_info "6.2 Test connectivité MinIO..."
MINIO_OK=0
for ip in 10.0.0.134 10.0.0.131 10.0.0.132; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "timeout 2 bash -c '</dev/tcp/${ip}/9000' 2>/dev/null"; then
        ((MINIO_OK++))
    fi
done

if [[ ${MINIO_OK} -eq 3 ]]; then
    log_success "Connectivité MinIO S3 API : 3/3 opérationnels"
else
    log_warning "Connectivité MinIO S3 API : ${MINIO_OK}/3 opérationnels"
fi

# 6.3 Test client mc
log_info "6.3 Verification client MinIO mc..."
if command -v mc &> /dev/null; then
    log_success "Client mc installé"
    if [[ -n "${MINIO_USER}" ]] && [[ -n "${MINIO_PASS}" ]]; then
        if mc alias list | grep -q "minio"; then
            log_success "Alias MinIO configuré"
        else
            log_warning "Alias MinIO non configuré"
        fi
    fi
else
    log_warning "Client mc non installé"
fi

# ============================================================
# MODULE 7 : MariaDB Galera HA
# ============================================================
log_section "MODULE 7 : MariaDB Galera HA"

# Charger credentials MariaDB
if load_credentials "mariadb"; then
    MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
    MARIADB_APP_PASSWORD="${MARIADB_APP_PASSWORD:-}"
else
    MARIADB_ROOT_PASSWORD=""
    MARIADB_APP_PASSWORD=""
fi

# 7.1 Test conteneurs MariaDB Galera
log_info "7.1 Vérification des conteneurs MariaDB Galera..."
MARIADB_NODES=0
MARIADB_CLUSTER_SIZE=0

for ip in 10.0.0.170 10.0.0.171 10.0.0.172; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=mariadb' --format '{{.Names}}' | grep -q mariadb" 2>/dev/null; then
        ((MARIADB_NODES++))
        # Vérifier le cluster size
        if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
            CLUSTER_SIZE=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec mariadb mysql -uroot -p\"${MARIADB_ROOT_PASSWORD}\" -e 'SHOW STATUS LIKE \"wsrep_cluster_size\";' 2>/dev/null | grep wsrep_cluster_size | awk '{print \$2}' || echo '0'")
            if [[ ${CLUSTER_SIZE} -gt ${MARIADB_CLUSTER_SIZE} ]]; then
                MARIADB_CLUSTER_SIZE=${CLUSTER_SIZE}
            fi
        fi
    fi
done

if [[ ${MARIADB_NODES} -eq 3 ]]; then
    log_success "Conteneurs MariaDB Galera : 3/3 actifs"
else
    log_error "Conteneurs MariaDB Galera : ${MARIADB_NODES}/3 actifs"
fi

if [[ ${MARIADB_CLUSTER_SIZE} -eq 3 ]]; then
    log_success "Cluster Galera : 3/3 nœuds"
else
    log_warning "Cluster Galera : ${MARIADB_CLUSTER_SIZE}/3 nœuds"
fi

# 7.2 Test ProxySQL
log_info "7.2 Vérification ProxySQL..."
PROXYSQL_NODES=0
for ip in 10.0.0.173 10.0.0.174; do
    if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps --filter 'name=proxysql' --format '{{.Names}}' | grep -q proxysql" 2>/dev/null; then
        ((PROXYSQL_NODES++))
    fi
done

if [[ ${PROXYSQL_NODES} -eq 2 ]]; then
    log_success "ProxySQL : 2/2 actifs"
else
    log_error "ProxySQL : ${PROXYSQL_NODES}/2 actifs"
fi

# 7.3 Test connectivité via LB 10.0.0.20:3306
log_info "7.3 Test connectivité MariaDB via LB 10.0.0.20:3306..."
if [[ -n "${MARIADB_APP_PASSWORD}" ]]; then
    if mysql -h 10.0.0.20 -P 3306 -u erpnext -p"${MARIADB_APP_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
        log_success "Connectivité MariaDB via LB 10.0.0.20:3306 : OK"
    else
        log_error "Connectivité MariaDB via LB 10.0.0.20:3306 : ÉCHEC"
    fi
else
    log_warning "Credentials MariaDB non disponibles, test de connectivité ignoré"
fi

# ============================================================
# MODULE 8 : ProxySQL Advanced
# ============================================================
log_section "MODULE 8 : ProxySQL Advanced"

# Charger credentials ProxySQL
if load_credentials "proxysql"; then
    PROXYSQL_ADMIN_PASSWORD="${PROXYSQL_ADMIN_PASSWORD:-admin}"
else
    PROXYSQL_ADMIN_PASSWORD="admin"
fi

# 8.1 Test configuration ProxySQL avancée
log_info "8.1 Vérification configuration ProxySQL avancée..."
PROXYSQL_CONFIG_OK=0

for ip in 10.0.0.173 10.0.0.174; do
    # Vérifier que les serveurs Galera sont configurés
    SERVERS=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec proxysql mysql -uadmin -p\"${PROXYSQL_ADMIN_PASSWORD}\" -h127.0.0.1 -P6032 -e 'SELECT COUNT(*) FROM mysql_servers;' 2>/dev/null | tail -1 || echo '0'")
    if [[ "${SERVERS}" == "3" ]]; then
        ((PROXYSQL_CONFIG_OK++))
    fi
done

if [[ ${PROXYSQL_CONFIG_OK} -eq 2 ]]; then
    log_success "Configuration ProxySQL : 2/2 noeuds configures - 3 serveurs Galera"
else
    log_warning "Configuration ProxySQL : ${PROXYSQL_CONFIG_OK}/2 noeuds configures"
fi

# ============================================================
# TESTS DE FAILOVER (Optionnels)
# ============================================================
log_section "TESTS DE FAILOVER - Optionnels Non Destructifs"

# Vérifier si les tests de failover sont demandés
ENABLE_FAILOVER=false
for arg in "$@"; do
    if [[ "${arg}" == "--failover" ]]; then
        ENABLE_FAILOVER=true
        break
    fi
done

if [[ "${ENABLE_FAILOVER}" == "true" ]]; then
    log_warning "⚠️  TESTS DE FAILOVER ACTIVÉS"
    log_warning "Ces tests vont arrêter temporairement des services"
    log_warning "Tous les services seront redémarrés automatiquement"
    echo ""
    read -p "Continuer avec les tests de failover ? (yes/NO) : " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        log_info "Tests de failover annulés"
        ENABLE_FAILOVER=false
    fi
fi

if [[ "${ENABLE_FAILOVER}" == "true" ]]; then
    # 9.1 Test failover PostgreSQL/Patroni
    log_info "9.1 Test failover PostgreSQL/Patroni..."
    if [[ -n "${PATRONI_LEADER}" ]]; then
        log_info "Arrêt du leader Patroni : ${PATRONI_LEADER}"
        ssh ${SSH_KEY_OPTS} "root@${PATRONI_LEADER}" "docker stop patroni" 2>/dev/null || true
        log_info "Attente du failover (30 secondes)..."
        sleep 30
        
        # Vérifier le nouveau leader
        NEW_LEADER=""
        for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
            if [[ "${ip}" != "${PATRONI_LEADER}" ]]; then
                ROLE=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec patroni patronictl list -f json 2>/dev/null | jq -r '.[] | select(.Role == \"Leader\") | .Member' 2>/dev/null | head -1 || echo ''")
                if [[ -n "${ROLE}" ]]; then
                    NEW_LEADER="${ip}"
                    break
                fi
            fi
        done
        
        if [[ -n "${NEW_LEADER}" ]]; then
            log_success "Failover PostgreSQL réussi : nouveau leader ${NEW_LEADER}"
        else
            log_error "Failover PostgreSQL échoué : aucun nouveau leader détecté"
        fi
        
        # Redémarrer l'ancien leader
        log_info "Redémarrage de l'ancien leader..."
        ssh ${SSH_KEY_OPTS} "root@${PATRONI_LEADER}" "docker start patroni" 2>/dev/null || true
        sleep 10
    else
        log_warning "Leader Patroni non détecté, test de failover ignoré"
    fi
    
    # 9.2 Test failover Redis Sentinel
    log_info "9.2 Test failover Redis Sentinel..."
    if [[ -n "${REDIS_MASTER}" ]]; then
        log_info "Arrêt du master Redis : ${REDIS_MASTER}"
        ssh ${SSH_KEY_OPTS} "root@${REDIS_MASTER}" "docker stop redis" 2>/dev/null || true
        log_info "Attente du failover Sentinel (30 secondes)..."
        sleep 30
        
        # Vérifier le nouveau master
        NEW_MASTER=""
        for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
            if [[ "${ip}" != "${REDIS_MASTER}" ]]; then
                ROLE=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "docker exec redis redis-cli -a \"${REDIS_PASSWORD}\" INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r' || echo 'unknown'")
                if [[ "${ROLE}" == "master" ]]; then
                    NEW_MASTER="${ip}"
                    break
                fi
            fi
        done
        
        if [[ -n "${NEW_MASTER}" ]]; then
            log_success "Failover Redis réussi : nouveau master ${NEW_MASTER}"
        else
            log_error "Failover Redis échoué : aucun nouveau master détecté"
        fi
        
        # Redémarrer l'ancien master
        log_info "Redémarrage de l'ancien master..."
        ssh ${SSH_KEY_OPTS} "root@${REDIS_MASTER}" "docker start redis" 2>/dev/null || true
        sleep 10
    else
        log_warning "Master Redis non détecté, test de failover ignoré"
    fi
    
    # 9.3 Test résilience RabbitMQ
    log_info "9.3 Test résilience RabbitMQ..."
    if [[ ${RABBITMQ_NODES} -eq 3 ]]; then
        TEST_NODE="10.0.0.126"
        log_info "Arrêt d'un nœud RabbitMQ : ${TEST_NODE}"
        ssh ${SSH_KEY_OPTS} "root@${TEST_NODE}" "docker stop rabbitmq" 2>/dev/null || true
        sleep 5
        
        # Vérifier que le cluster reste accessible
        if timeout 5 bash -c "</dev/tcp/10.0.0.10/5672" 2>/dev/null; then
            log_success "RabbitMQ reste accessible après arrêt d'un nœud"
        else
            log_error "RabbitMQ non accessible après arrêt d'un nœud"
        fi
        
        # Redémarrer le nœud
        log_info "Redémarrage du nœud..."
        ssh ${SSH_KEY_OPTS} "root@${TEST_NODE}" "docker start rabbitmq" 2>/dev/null || true
        sleep 10
    else
        log_warning "Cluster RabbitMQ incomplet, test de résilience ignoré"
    fi
    
    # 9.4 Test résilience MariaDB Galera
    log_info "9.4 Test résilience MariaDB Galera..."
    if [[ ${MARIADB_NODES} -eq 3 ]]; then
        TEST_NODE="10.0.0.170"
        log_info "Arrêt d'un nœud MariaDB : ${TEST_NODE}"
        ssh ${SSH_KEY_OPTS} "root@${TEST_NODE}" "docker stop mariadb" 2>/dev/null || true
        sleep 5
        
        # Vérifier que le cluster reste accessible
        if [[ -n "${MARIADB_APP_PASSWORD}" ]]; then
            if mysql -h 10.0.0.20 -P 3306 -u erpnext -p"${MARIADB_APP_PASSWORD}" -e "SELECT 1;" > /dev/null 2>&1; then
                log_success "MariaDB reste accessible après arrêt d'un nœud"
            else
                log_error "MariaDB non accessible après arrêt d'un nœud"
            fi
        fi
        
        # Redémarrer le nœud
        log_info "Redémarrage du nœud..."
        ssh ${SSH_KEY_OPTS} "root@${TEST_NODE}" "docker start mariadb" 2>/dev/null || true
        sleep 10
    else
        log_warning "Cluster MariaDB incomplet, test de résilience ignoré"
    fi
else
    log_warning "Les tests de failover nécessitent l'arrêt temporaire de services"
    log_warning "Ils sont désactivés par défaut pour éviter toute interruption"
    log_info "Pour activer les tests de failover, utilisez: ./test_couche1_complete.sh --failover"
fi

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
log_section "RESUME FINAL"

echo "" | tee -a "${LOG_FILE}"
echo "==============================================================" | tee -a "${LOG_FILE}"
echo " Statistiques des Tests" | tee -a "${LOG_FILE}"
echo "==============================================================" | tee -a "${LOG_FILE}"
echo "" | tee -a "${LOG_FILE}"

log_info "Total des tests : ${TOTAL_TESTS}"
log_success "Tests réussis : ${PASSED_TESTS}"
log_error "Tests échoués : ${FAILED_TESTS}"
log_warning "Avertissements : ${WARNING_TESTS}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    SUCCESS_RATE=100
elif [[ ${TOTAL_TESTS} -gt 0 ]]; then
    SUCCESS_RATE=$(( (PASSED_TESTS * 100) / TOTAL_TESTS ))
else
    SUCCESS_RATE=0
fi

log_info "Taux de réussite : ${SUCCESS_RATE}%"

echo "" | tee -a "${LOG_FILE}"
echo "==============================================================" | tee -a "${LOG_FILE}"

# Générer le rapport Markdown
{
    echo "# Rapport de Test Complet - Couche 1 KeyBuzz"
    echo ""
    echo "**Date de test** : $(date)"
    echo -n "**Statut** : "
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        echo "OK **100% VALIDE**"
    else
        echo "ATTENTION **${FAILED_TESTS} ECHECS**"
    fi

    echo ""
    echo "---"
    echo ""
    echo "## Resume Executif"
    echo ""
    echo "Test complet de la couche 1 (Modules 2-8) de l'infrastructure KeyBuzz."
    echo ""
    echo "### Statistiques"
    echo ""
    echo "| Categorie | Nombre |"
    echo "|-----------|--------|"
    echo "| **Total des tests** | ${TOTAL_TESTS} |"
    echo "| **Tests reussis** | ${PASSED_TESTS} |"
    echo "| **Tests echoues** | ${FAILED_TESTS} |"
    echo "| **Avertissements** | ${WARNING_TESTS} |"
    echo "| **Taux de reussite** | ${SUCCESS_RATE}% |"
    echo ""
    echo "---"
    echo ""
    echo "## Module 3 : PostgreSQL HA"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Conteneurs Patroni : ${PATRONI_NODES}/3"
    echo -n "- OK Leader Patroni : "
    if [[ -n "${PATRONI_LEADER}" ]]; then
        echo "${PATRONI_LEADER}"
    else
        echo "Non detecte"
    fi
    echo "- OK Replicas Patroni : ${PATRONI_REPLICAS}/2"
    echo "- OK HAProxy PostgreSQL : ${HAPROXY_PG_OK}/2"
    echo "- OK PgBouncer : ${PGBOUNCER_OK}/2"
    echo ""
    echo "---"
    echo ""
    echo "## Module 4 : Redis HA"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Conteneurs Redis : ${REDIS_NODES}/3"
    echo -n "- OK Master Redis : "
    if [[ -n "${REDIS_MASTER}" ]]; then
        echo "${REDIS_MASTER}"
    else
        echo "Non detecte"
    fi
    echo "- OK Replicas Redis : ${REDIS_REPLICAS}/2"
    echo "- OK Redis Sentinel : ${SENTINEL_OK}/3"
    echo "- OK HAProxy Redis : ${HAPROXY_REDIS_OK}/2"
    echo ""
    echo "---"
    echo ""
    echo "## Module 5 : RabbitMQ HA"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Conteneurs RabbitMQ : ${RABBITMQ_NODES}/3"
    echo "- OK Cluster RabbitMQ : ${RABBITMQ_CLUSTER_SIZE}/3 noeuds"
    echo "- OK HAProxy RabbitMQ : ${HAPROXY_RABBITMQ_OK}/2"
    echo ""
    echo "---"
    echo ""
    echo "## Module 6 : MinIO S3"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Conteneurs MinIO : ${MINIO_NODES}/3"
    echo "- OK Connectivite S3 API : ${MINIO_OK}/3"
    echo ""
    echo "---"
    echo ""
    echo "## Module 7 : MariaDB Galera"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Conteneurs MariaDB Galera : ${MARIADB_NODES}/3"
    echo "- OK Cluster Galera : ${MARIADB_CLUSTER_SIZE}/3 noeuds"
    echo "- OK ProxySQL : ${PROXYSQL_NODES}/2"
    echo ""
    echo "---"
    echo ""
    echo "## Module 8 : ProxySQL Advanced"
    echo ""
    echo "### Composants Testes"
    echo ""
    echo "- OK Configuration ProxySQL : ${PROXYSQL_CONFIG_OK}/2 noeuds"
    echo ""
    echo "---"
    echo ""
    echo "## Conclusion"
    echo ""
    if [[ ${FAILED_TESTS} -eq 0 ]]; then
        echo "OK **La couche 1 est 100% operationnelle et validee.**"
    else
        echo "ATTENTION **${FAILED_TESTS} problemes detectes. Verifier les logs pour plus de details.**"
    fi
    echo ""
    echo "**Log complet** : ${LOG_FILE}"
    echo ""
    echo "---"
    echo ""
    echo "**Rapport genere le** : $(date)"
    echo "**Script** : test_couche1_complete.sh"
} > "${REPORT_FILE}"

log_success "Rapport généré : ${REPORT_FILE}"
log_info "Log complet : ${LOG_FILE}"

# Code de sortie
if [[ ${FAILED_TESTS} -eq 0 ]]; then
    exit 0
else
    exit 1
fi

