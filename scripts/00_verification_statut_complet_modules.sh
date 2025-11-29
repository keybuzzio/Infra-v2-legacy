#!/usr/bin/env bash
#
# 00_verification_statut_complet_modules.sh - Vérification complète du statut de tous les modules
#
# Ce script vérifie le statut réel de tous les modules de l'infrastructure KeyBuzz
# selon le design définitif.
#
# Usage:
#   ./00_verification_statut_complet_modules.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Tous les modules installés (2-9)

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

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

# Compteurs
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check_result() {
    local check_name="$1"
    local result="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [[ "${result}" == "PASS" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_success "${check_name}"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        log_error "${check_name}"
    fi
}

# Fonction pour tester un port TCP
test_port() {
    local ip="$1"
    local port="$2"
    timeout 2 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null
}

# Fonction pour parser servers.tsv
get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Vérification Statut Complet - Tous les Modules"
echo "=============================================================="
echo ""
log_info "Vérification selon le design définitif de l'infrastructure"
echo ""

# Charger les credentials
CREDENTIALS_PG="${INSTALL_DIR}/credentials/postgres.env"
CREDENTIALS_REDIS="${INSTALL_DIR}/credentials/redis.env"
CREDENTIALS_MARIA="${INSTALL_DIR}/credentials/mariadb.env"
CREDENTIALS_MINIO="${INSTALL_DIR}/credentials/minio.env"

if [[ -f "${CREDENTIALS_PG}" ]]; then
    source "${CREDENTIALS_PG}"
fi

if [[ -f "${CREDENTIALS_REDIS}" ]]; then
    source "${CREDENTIALS_REDIS}"
fi

if [[ -f "${CREDENTIALS_MARIA}" ]]; then
    source "${CREDENTIALS_MARIA}"
fi

if [[ -f "${CREDENTIALS_MINIO}" ]]; then
    source "${CREDENTIALS_MINIO}"
fi

# Variables par défaut
POSTGRES_USER="${POSTGRES_USER:-postgres}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
MARIA_ROOT_PASSWORD="${MARIA_ROOT_PASSWORD:-}"

# ═══════════════════════════════════════════════════════════════
# MODULE 3: PostgreSQL HA (Patroni + HAProxy + PgBouncer)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 3: PostgreSQL HA (Patroni + HAProxy + PgBouncer)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 3.1 Vérifier Patroni sur les 3 nœuds
log_info "Vérification Patroni containers..."
for hostname in db-master-01 db-slave-01 db-slave-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        check_result "Patroni ${hostname} (IP non trouvée)" "FAIL"
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=patroni --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "Patroni container running on ${hostname} (${ip})" "PASS"
    else
        check_result "Patroni container on ${hostname} (${ip})" "FAIL"
    fi
done

# 3.2 Vérifier l'état du cluster Patroni
log_info "Vérification état cluster Patroni..."
DB_MASTER_IP=$(get_ip "db-master-01")
if [[ -n "${DB_MASTER_IP}" ]]; then
    CLUSTER_STATUS=$(ssh ${SSH_OPTS} root@"${DB_MASTER_IP}" "docker exec patroni patronictl list 2>/dev/null" || echo "")
    if echo "${CLUSTER_STATUS}" | grep -q "Leader"; then
        check_result "Patroni cluster has a leader" "PASS"
        REPLICAS=$(echo "${CLUSTER_STATUS}" | grep -c "Replica.*streaming" || echo "0")
        if [[ "${REPLICAS}" == "2" ]]; then
            check_result "Patroni streaming replicas: ${REPLICAS}/2" "PASS"
        else
            check_result "Patroni streaming replicas: ${REPLICAS}/2" "FAIL"
        fi
    else
        check_result "Patroni cluster status (no leader)" "FAIL"
    fi
fi

# 3.3 Vérifier HAProxy sur haproxy-01 et haproxy-02
log_info "Vérification HAProxy containers..."
for hostname in haproxy-01 haproxy-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=haproxy --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "HAProxy container running on ${hostname} (${ip})" "PASS"
    else
        check_result "HAProxy container on ${hostname} (${ip})" "FAIL"
    fi
done

# 3.4 Vérifier les ports HAProxy (10.0.0.10)
log_info "Vérification ports HAProxy via LB 10.0.0.10..."
if test_port "10.0.0.10" "5432"; then
    check_result "HAProxy PostgreSQL port 5432 (10.0.0.10:5432)" "PASS"
else
    check_result "HAProxy PostgreSQL port 5432 (10.0.0.10:5432)" "FAIL"
fi

if test_port "10.0.0.10" "6432"; then
    check_result "HAProxy PgBouncer port 6432 (10.0.0.10:6432)" "PASS"
else
    check_result "HAProxy PgBouncer port 6432 (10.0.0.10:6432)" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════
# MODULE 4: Redis HA (Master-Replica + Sentinel + HAProxy)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 4: Redis HA (Master-Replica + Sentinel + HAProxy)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 4.1 Vérifier Redis containers
log_info "Vérification Redis containers..."
for hostname in redis-01 redis-02 redis-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=redis --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "Redis container running on ${hostname} (${ip})" "PASS"
    else
        check_result "Redis container on ${hostname} (${ip})" "FAIL"
    fi
done

# 4.2 Vérifier Sentinel
log_info "Vérification Redis Sentinel..."
REDIS_01_IP=$(get_ip "redis-01")
if [[ -n "${REDIS_01_IP}" ]]; then
    if ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker ps --filter name=sentinel --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "Sentinel container running on redis-01" "PASS"
    else
        check_result "Sentinel container on redis-01" "FAIL"
    fi
    
    # Détecter le master Redis
    MASTER_INFO=$(ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name keybuzz-master 2>/dev/null" || echo "")
    if [[ -n "${MASTER_INFO}" ]]; then
        check_result "Redis master detected via Sentinel" "PASS"
    else
        check_result "Redis master detection via Sentinel" "FAIL"
    fi
fi

# 4.3 Vérifier Redis via HAProxy (10.0.0.10:6379)
log_info "Vérification Redis via HAProxy (10.0.0.10:6379)..."
if test_port "10.0.0.10" "6379"; then
    check_result "Redis port 6379 via HAProxy (10.0.0.10:6379)" "PASS"
    
    # Test PING Redis
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        if redis-cli -h 10.0.0.10 -p 6379 -a "${REDIS_PASSWORD}" PING 2>/dev/null | grep -q "PONG"; then
            check_result "Redis PING via HAProxy (10.0.0.10:6379)" "PASS"
        else
            check_result "Redis PING via HAProxy (10.0.0.10:6379)" "FAIL"
        fi
    fi
else
    check_result "Redis port 6379 via HAProxy (10.0.0.10:6379)" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════
# MODULE 5: RabbitMQ HA (Quorum Cluster)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 5: RabbitMQ HA (Quorum Cluster)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 5.1 Vérifier RabbitMQ containers
log_info "Vérification RabbitMQ containers..."
for hostname in queue-01 queue-02 queue-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=rabbitmq --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "RabbitMQ container running on ${hostname} (${ip})" "PASS"
    else
        check_result "RabbitMQ container on ${hostname} (${ip})" "FAIL"
    fi
done

# 5.2 Vérifier RabbitMQ via HAProxy (10.0.0.10:5672)
log_info "Vérification RabbitMQ via HAProxy (10.0.0.10:5672)..."
if test_port "10.0.0.10" "5672"; then
    check_result "RabbitMQ AMQP port 5672 via HAProxy (10.0.0.10:5672)" "PASS"
else
    check_result "RabbitMQ AMQP port 5672 via HAProxy (10.0.0.10:5672)" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════
# MODULE 6: MinIO Distributed (3 nœuds)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 6: MinIO Distributed (3 nœuds)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 6.1 Vérifier MinIO containers
log_info "Vérification MinIO containers..."
for hostname in minio-01 minio-02 minio-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=minio --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "MinIO container running on ${hostname} (${ip})" "PASS"
    else
        check_result "MinIO container on ${hostname} (${ip})" "FAIL"
    fi
done

# 6.2 Vérifier MinIO port 9000
log_info "Vérification MinIO port 9000..."
MINIO_01_IP=$(get_ip "minio-01")
if [[ -n "${MINIO_01_IP}" ]]; then
    if test_port "${MINIO_01_IP}" "9000"; then
        check_result "MinIO port 9000 on minio-01 (${MINIO_01_IP}:9000)" "PASS"
    else
        check_result "MinIO port 9000 on minio-01 (${MINIO_01_IP}:9000)" "FAIL"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# MODULE 7: MariaDB Galera HA
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 7: MariaDB Galera HA"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 7.1 Vérifier MariaDB containers
log_info "Vérification MariaDB Galera containers..."
for hostname in maria-01 maria-02 maria-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=mariadb --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "MariaDB container running on ${hostname} (${ip})" "PASS"
    else
        check_result "MariaDB container on ${hostname} (${ip})" "FAIL"
    fi
done

# ═══════════════════════════════════════════════════════════════
# MODULE 8: ProxySQL
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 8: ProxySQL"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 8.1 Vérifier ProxySQL containers
log_info "Vérification ProxySQL containers..."
for hostname in proxysql-01 proxysql-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps --filter name=proxysql --format '{{.Status}}' 2>/dev/null | grep -q 'Up'" 2>/dev/null; then
        check_result "ProxySQL container running on ${hostname} (${ip})" "PASS"
    else
        check_result "ProxySQL container on ${hostname} (${ip})" "FAIL"
    fi
done

# 8.2 Vérifier ProxySQL via LB 10.0.0.20:3306
log_info "Vérification ProxySQL via LB 10.0.0.20:3306..."
if test_port "10.0.0.20" "3306"; then
    check_result "ProxySQL port 3306 via LB (10.0.0.20:3306)" "PASS"
else
    check_result "ProxySQL port 3306 via LB (10.0.0.20:3306)" "FAIL"
fi

# ═══════════════════════════════════════════════════════════════
# MODULE 9: K3s HA (3 Masters + 5 Workers)
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " MODULE 9: K3s HA (3 Masters + 5 Workers)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# 9.1 Vérifier K3s masters
log_info "Vérification K3s masters..."
for hostname in k3s-master-01 k3s-master-02 k3s-master-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s 2>/dev/null | grep -q 'active'" 2>/dev/null; then
        check_result "K3s service active on ${hostname} (${ip})" "PASS"
    else
        check_result "K3s service on ${hostname} (${ip})" "FAIL"
    fi
done

# 9.2 Vérifier K3s workers
log_info "Vérification K3s workers..."
for hostname in k3s-worker-01 k3s-worker-02 k3s-worker-03 k3s-worker-04 k3s-worker-05; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s-agent 2>/dev/null | grep -q 'active'" 2>/dev/null; then
        check_result "K3s-agent service active on ${hostname} (${ip})" "PASS"
    else
        check_result "K3s-agent service on ${hostname} (${ip})" "FAIL"
    fi
done

# 9.3 Vérifier le cluster K3s (via kubectl sur master-01)
log_info "Vérification cluster K3s..."
K3S_MASTER_01_IP=$(get_ip "k3s-master-01")
if [[ -n "${K3S_MASTER_01_IP}" ]]; then
    NODES_READY=$(ssh ${SSH_OPTS} root@"${K3S_MASTER_01_IP}" "kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || echo '0'")
    if [[ "${NODES_READY}" -ge "8" ]]; then
        check_result "K3s cluster nodes ready: ${NODES_READY}/8+" "PASS"
    else
        check_result "K3s cluster nodes ready: ${NODES_READY}/8+" "FAIL"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# RÉSUMÉ FINAL
# ═══════════════════════════════════════════════════════════════

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo " RÉSUMÉ FINAL"
echo "═══════════════════════════════════════════════════════════════"
echo ""
log_info "Total des vérifications: ${TOTAL_CHECKS}"
log_success "Vérifications réussies: ${PASSED_CHECKS}"
if [[ ${FAILED_CHECKS} -gt 0 ]]; then
    log_error "Vérifications échouées: ${FAILED_CHECKS}"
else
    log_success "Vérifications échouées: ${FAILED_CHECKS}"
fi

SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
echo ""
if [[ ${SUCCESS_RATE} -ge 95 ]]; then
    log_success "Taux de succès: ${SUCCESS_RATE}% - Infrastructure OK ✅"
    exit 0
elif [[ ${SUCCESS_RATE} -ge 80 ]]; then
    log_warning "Taux de succès: ${SUCCESS_RATE}% - Infrastructure partiellement OK ⚠️"
    exit 1
else
    log_error "Taux de succès: ${SUCCESS_RATE}% - Infrastructure nécessite des corrections ❌"
    exit 1
fi

