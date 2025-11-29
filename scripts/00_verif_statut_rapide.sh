#!/usr/bin/env bash
#
# 00_verif_statut_rapide.sh - Verification rapide du statut de tous les modules
#
# Ce script verifie rapidement l'etat de tous les modules de l'infrastructure
# en utilisant uniquement des caracteres ASCII pour eviter les problemes d'encodage
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5"

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
echo " [KeyBuzz] Verification Statut Rapide - Tous les Modules"
echo "=============================================================="
echo ""

TOTAL=0
PASSED=0
FAILED=0

# MODULE 3: PostgreSQL HA
echo "--- MODULE 3: PostgreSQL HA (Patroni + HAProxy + PgBouncer) ---"
for hostname in db-master-01 db-slave-01 db-slave-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        echo "  [FAIL] ${hostname} (IP non trouvee)"
        FAILED=$((FAILED + 1))
        TOTAL=$((TOTAL + 1))
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q patroni" 2>/dev/null; then
        echo "  [OK] Patroni sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] Patroni sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# HAProxy
for hostname in haproxy-01 haproxy-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q haproxy" 2>/dev/null; then
        echo "  [OK] HAProxy sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] HAProxy sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# Test ports HAProxy via LB 10.0.0.10
if test_port "10.0.0.10" "5432"; then
    echo "  [OK] HAProxy PostgreSQL (10.0.0.10:5432)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] HAProxy PostgreSQL (10.0.0.10:5432)"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

if test_port "10.0.0.10" "6432"; then
    echo "  [OK] HAProxy PgBouncer (10.0.0.10:6432)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] HAProxy PgBouncer (10.0.0.10:6432)"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# MODULE 4: Redis HA
echo ""
echo "--- MODULE 4: Redis HA (Master-Replica + Sentinel + HAProxy) ---"
for hostname in redis-01 redis-02 redis-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q redis" 2>/dev/null; then
        echo "  [OK] Redis sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] Redis sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# Test Redis via HAProxy
if test_port "10.0.0.10" "6379"; then
    echo "  [OK] Redis via HAProxy (10.0.0.10:6379)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] Redis via HAProxy (10.0.0.10:6379)"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# MODULE 5: RabbitMQ HA
echo ""
echo "--- MODULE 5: RabbitMQ HA (Quorum Cluster) ---"
for hostname in queue-01 queue-02 queue-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q rabbitmq" 2>/dev/null; then
        echo "  [OK] RabbitMQ sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] RabbitMQ sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# Test RabbitMQ via HAProxy
if test_port "10.0.0.10" "5672"; then
    echo "  [OK] RabbitMQ via HAProxy (10.0.0.10:5672)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] RabbitMQ via HAProxy (10.0.0.10:5672)"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# MODULE 6: MinIO Distributed
echo ""
echo "--- MODULE 6: MinIO Distributed (3 noeuds) ---"
for hostname in minio-01 minio-02 minio-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q minio" 2>/dev/null; then
        echo "  [OK] MinIO sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] MinIO sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# MODULE 7: MariaDB Galera
echo ""
echo "--- MODULE 7: MariaDB Galera HA ---"
for hostname in maria-01 maria-02 maria-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q mariadb" 2>/dev/null; then
        echo "  [OK] MariaDB sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] MariaDB sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# MODULE 8: ProxySQL
echo ""
echo "--- MODULE 8: ProxySQL ---"
for hostname in proxysql-01 proxysql-02; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "docker ps 2>/dev/null | grep -q proxysql" 2>/dev/null; then
        echo "  [OK] ProxySQL sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] ProxySQL sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# Test ProxySQL via LB 10.0.0.20
if test_port "10.0.0.20" "3306"; then
    echo "  [OK] ProxySQL via LB (10.0.0.20:3306)"
    PASSED=$((PASSED + 1))
else
    echo "  [FAIL] ProxySQL via LB (10.0.0.20:3306)"
    FAILED=$((FAILED + 1))
fi
TOTAL=$((TOTAL + 1))

# MODULE 9: K3s HA
echo ""
echo "--- MODULE 9: K3s HA (3 Masters + 5 Workers) ---"
for hostname in k3s-master-01 k3s-master-02 k3s-master-03; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s 2>/dev/null | grep -q active" 2>/dev/null; then
        echo "  [OK] K3s master sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] K3s master sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

for hostname in k3s-worker-01 k3s-worker-02 k3s-worker-03 k3s-worker-04 k3s-worker-05; do
    ip=$(get_ip "${hostname}")
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    if ssh ${SSH_OPTS} root@"${ip}" "systemctl is-active k3s-agent 2>/dev/null | grep -q active" 2>/dev/null; then
        echo "  [OK] K3s worker sur ${hostname} (${ip})"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] K3s worker sur ${hostname} (${ip})"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# Resume final
echo ""
echo "=============================================================="
echo " RESUME FINAL"
echo "=============================================================="
echo "  Total des verifications: ${TOTAL}"
echo "  Verifications reussies: ${PASSED}"
echo "  Verifications echouees: ${FAILED}"

if [[ ${TOTAL} -gt 0 ]]; then
    SUCCESS_RATE=$((PASSED * 100 / TOTAL))
    echo "  Taux de succes: ${SUCCESS_RATE}%"
    
    if [[ ${SUCCESS_RATE} -ge 95 ]]; then
        echo "  [OK] Infrastructure OK"
        exit 0
    elif [[ ${SUCCESS_RATE} -ge 80 ]]; then
        echo "  [WARN] Infrastructure partiellement OK"
        exit 1
    else
        echo "  [FAIL] Infrastructure necessite des corrections"
        exit 1
    fi
else
    echo "  [FAIL] Aucune verification effectuee"
    exit 1
fi

