#!/usr/bin/env bash
#
# 00_verification_complete_apres_redemarrage.sh - Verification complete de tous les modules apres redemarrage
#
# Ce script verifie l'etat de tous les modules de l'infrastructure apres un redemarrage
# Utilise uniquement des caracteres ASCII pour eviter les problemes d'encodage
#
# Usage:
#   ./00_verification_complete_apres_redemarrage.sh [servers.tsv]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Fonction pour tester un port TCP
test_port() {
    local ip="$1"
    local port="$2"
    timeout 3 bash -c "echo > /dev/tcp/${ip}/${port}" 2>/dev/null
}

# Fonction pour parser servers.tsv
get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

# Fonction pour tester l'acces SSH
test_ssh() {
    local ip="$1"
    if ssh ${SSH_OPTS} root@"${ip}" "echo OK" 2>/dev/null | grep -q "OK"; then
        return 0
    else
        return 1
    fi
}

# Compteurs globaux
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check_result() {
    local check_name="$1"
    local result="$2"
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [[ "${result}" == "PASS" ]]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        echo "  [OK] ${check_name}"
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        echo "  [FAIL] ${check_name}"
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Verification Complete - Tous les Modules"
echo " Apres Redemarrage de tous les serveurs"
echo "=============================================================="
echo ""

# Phase 1: Verification acces SSH
echo "--- PHASE 1: Verification Acces SSH ---"
SSH_ACCESSIBLE=0
SSH_INACCESSIBLE=0

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${HOSTNAME}" == "install-01" ]]; then
        continue
    fi
    if [[ -z "${IP_PRIVEE}" ]] || [[ -z "${HOSTNAME}" ]]; then
        continue
    fi
    
    if test_ssh "${IP_PRIVEE}" "${HOSTNAME}"; then
        SSH_ACCESSIBLE=$((SSH_ACCESSIBLE + 1))
    else
        SSH_INACCESSIBLE=$((SSH_INACCESSIBLE + 1))
        echo "  [FAIL] SSH: ${HOSTNAME} (${IP_PRIVEE})"
    fi
done < "${TSV_FILE}"

echo "  Serveurs accessibles: ${SSH_ACCESSIBLE}"
if [[ ${SSH_INACCESSIBLE} -gt 0 ]]; then
    echo "  Serveurs inaccessibles: ${SSH_INACCESSIBLE}"
fi
echo ""

# Phase 2: Module 3 - PostgreSQL HA
echo "--- PHASE 2: Module 3 - PostgreSQL HA (Patroni + HAProxy + PgBouncer) ---"

# 2.1 Patroni containers
for hostname in db-master-01 db-slave-01 db-slave-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q patroni" 2>/dev/null; then
        check_result "Patroni container on ${hostname} (${ip})" "PASS"
    else
        check_result "Patroni container on ${hostname} (${ip})" "FAIL"
    fi
done

# 2.2 HAProxy containers
for hostname in haproxy-01 haproxy-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q haproxy" 2>/dev/null; then
        check_result "HAProxy container on ${hostname} (${ip})" "PASS"
    else
        check_result "HAProxy container on ${hostname} (${ip})" "FAIL"
    fi
done

# 2.3 Ports HAProxy via LB 10.0.0.10
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

# 2.4 Cluster Patroni
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

echo ""

# Phase 3: Module 4 - Redis HA
echo "--- PHASE 3: Module 4 - Redis HA (Master-Replica + Sentinel + HAProxy) ---"

# 3.1 Redis containers
for hostname in redis-01 redis-02 redis-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q redis" 2>/dev/null; then
        check_result "Redis container on ${hostname} (${ip})" "PASS"
    else
        check_result "Redis container on ${hostname} (${ip})" "FAIL"
    fi
done

# 3.2 Sentinel
REDIS_01_IP=$(get_ip "redis-01")
if [[ -n "${REDIS_01_IP}" ]]; then
    if ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker ps 2>/dev/null | grep -q sentinel" 2>/dev/null; then
        check_result "Sentinel container on redis-01" "PASS"
    else
        check_result "Sentinel container on redis-01" "FAIL"
    fi
    
    # Detecter le master Redis
    MASTER_INFO=$(ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name keybuzz-master 2>/dev/null" || echo "")
    if [[ -n "${MASTER_INFO}" ]]; then
        check_result "Redis master detected via Sentinel" "PASS"
        MASTER_IP=$(echo "${MASTER_INFO}" | head -1)
        echo "    Master Redis: ${MASTER_IP}"
    else
        check_result "Redis master detection via Sentinel" "FAIL"
    fi
fi

# 3.3 Redis via HAProxy
if test_port "10.0.0.10" "6379"; then
    check_result "Redis port 6379 via HAProxy (10.0.0.10:6379)" "PASS"
else
    check_result "Redis port 6379 via HAProxy (10.0.0.10:6379)" "FAIL"
fi

echo ""

# Phase 4: Module 5 - RabbitMQ HA
echo "--- PHASE 4: Module 5 - RabbitMQ HA (Quorum Cluster) ---"

# 4.1 RabbitMQ containers
for hostname in queue-01 queue-02 queue-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q rabbitmq" 2>/dev/null; then
        check_result "RabbitMQ container on ${hostname} (${ip})" "PASS"
    else
        check_result "RabbitMQ container on ${hostname} (${ip})" "FAIL"
    fi
done

# 4.2 RabbitMQ via HAProxy
if test_port "10.0.0.10" "5672"; then
    check_result "RabbitMQ AMQP port 5672 via HAProxy (10.0.0.10:5672)" "PASS"
else
    check_result "RabbitMQ AMQP port 5672 via HAProxy (10.0.0.10:5672)" "FAIL"
fi

echo ""

# Phase 5: Module 6 - MinIO Distributed
echo "--- PHASE 5: Module 6 - MinIO Distributed (3 noeuds) ---"

# 5.1 MinIO containers
for hostname in minio-01 minio-02 minio-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q minio" 2>/dev/null; then
        check_result "MinIO container on ${hostname} (${ip})" "PASS"
    else
        check_result "MinIO container on ${hostname} (${ip})" "FAIL"
    fi
done

# 5.2 MinIO port 9000
MINIO_01_IP=$(get_ip "minio-01")
if [[ -n "${MINIO_01_IP}" ]]; then
    if test_port "${MINIO_01_IP}" "9000"; then
        check_result "MinIO port 9000 on minio-01 (${MINIO_01_IP}:9000)" "PASS"
    else
        check_result "MinIO port 9000 on minio-01 (${MINIO_01_IP}:9000)" "FAIL"
    fi
fi

echo ""

# Phase 6: Module 7 - MariaDB Galera
echo "--- PHASE 6: Module 7 - MariaDB Galera HA ---"

# 6.1 MariaDB containers
for hostname in maria-01 maria-02 maria-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q mariadb" 2>/dev/null; then
        check_result "MariaDB container on ${hostname} (${ip})" "PASS"
    else
        check_result "MariaDB container on ${hostname} (${ip})" "FAIL"
    fi
done

echo ""

# Phase 7: Module 8 - ProxySQL
echo "--- PHASE 7: Module 8 - ProxySQL ---"

# 7.1 ProxySQL containers
for hostname in proxysql-01 proxysql-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q proxysql" 2>/dev/null; then
        check_result "ProxySQL container on ${hostname} (${ip})" "PASS"
    else
        check_result "ProxySQL container on ${hostname} (${ip})" "FAIL"
    fi
done

# 7.2 ProxySQL via LB 10.0.0.20
if test_port "10.0.0.20" "3306"; then
    check_result "ProxySQL port 3306 via LB (10.0.0.20:3306)" "PASS"
else
    check_result "ProxySQL port 3306 via LB (10.0.0.20:3306)" "FAIL"
fi

echo ""

# Phase 8: Module 9 - K3s HA
echo "--- PHASE 8: Module 9 - K3s HA (3 Masters + 5 Workers) ---"

# 8.1 K3s masters
for hostname in k3s-master-01 k3s-master-02 k3s-master-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s 2>/dev/null | grep -q active" 2>/dev/null; then
        check_result "K3s service active on ${hostname} (${ip})" "PASS"
    else
        check_result "K3s service on ${hostname} (${ip})" "FAIL"
    fi
done

# 8.2 K3s workers
for hostname in k3s-worker-01 k3s-worker-02 k3s-worker-03 k3s-worker-04 k3s-worker-05; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s-agent 2>/dev/null | grep -q active" 2>/dev/null; then
        check_result "K3s-agent service active on ${hostname} (${ip})" "PASS"
    else
        check_result "K3s-agent service on ${hostname} (${ip})" "FAIL"
    fi
done

# 8.3 Cluster K3s
K3S_MASTER_01_IP=$(get_ip "k3s-master-01")
if [[ -n "${K3S_MASTER_01_IP}" ]]; then
    NODES_READY=$(ssh ${SSH_OPTS} root@"${K3S_MASTER_01_IP}" "kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || echo '0'")
    if [[ "${NODES_READY}" -ge "8" ]]; then
        check_result "K3s cluster nodes ready: ${NODES_READY}/8+" "PASS"
    else
        check_result "K3s cluster nodes ready: ${NODES_READY}/8+" "FAIL"
    fi
fi

echo ""

# Resume final
echo "=============================================================="
echo " RESUME FINAL"
echo "=============================================================="
echo "  Total des verifications: ${TOTAL_CHECKS}"
echo "  Verifications reussies: ${PASSED_CHECKS}"
echo "  Verifications echouees: ${FAILED_CHECKS}"

if [[ ${TOTAL_CHECKS} -gt 0 ]]; then
    SUCCESS_RATE=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    echo "  Taux de succes: ${SUCCESS_RATE}%"
    echo ""
    
    if [[ ${SUCCESS_RATE} -ge 95 ]]; then
        echo "  [OK] Infrastructure OK - Pret pour Module 10"
        exit 0
    elif [[ ${SUCCESS_RATE} -ge 80 ]]; then
        echo "  [WARN] Infrastructure partiellement OK - Verifications necessaires"
        exit 1
    else
        echo "  [FAIL] Infrastructure necessite des corrections"
        exit 1
    fi
else
    echo "  [FAIL] Aucune verification effectuee"
    exit 1
fi

