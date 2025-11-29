#!/usr/bin/env bash
#
# 00_test_3_problemes.sh - Test des 3 problèmes restants
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALL_DIR="/opt/keybuzz-installer"

# Charger les credentials
source "${INSTALL_DIR}/credentials/postgres.env" 2>/dev/null || true
source "${INSTALL_DIR}/credentials/redis.env" 2>/dev/null || true

echo "=============================================================="
echo " Test des 3 Problèmes Restants"
echo "=============================================================="
echo ""

# 1. PostgreSQL - Réplication (parsing JSON)
echo "=== 1. PostgreSQL - Réplication ==="
LEADER_COUNT=0
REPLICA_COUNT=0
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    echo "  ${ip}:"
    ROLE=$(ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get(\"role\", \"unknown\"))' 2>/dev/null || curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '\"role\":\"[^\"]*\"' | cut -d'\"' -f4" 2>/dev/null || echo "unknown")
    echo "    Rôle: ${ROLE}"
    if [[ "${ROLE}" == "primary" ]]; then
        LEADER_COUNT=$((LEADER_COUNT + 1))
    elif [[ "${ROLE}" == "replica" ]] || [[ "${ROLE}" == "standby_leader" ]]; then
        REPLICA_COUNT=$((REPLICA_COUNT + 1))
    fi
done
echo "  Résultat: ${LEADER_COUNT} primary, ${REPLICA_COUNT} réplicas"
if [[ ${LEADER_COUNT} -eq 1 ]] && [[ ${REPLICA_COUNT} -ge 1 ]]; then
    echo "  ✓ OK"
else
    echo "  ✗ ÉCHEC"
fi
echo ""

# 2. Redis - Sentinel
echo "=== 2. Redis - Sentinel ==="
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    echo "  ${ip}:"
    # Essayer 127.0.0.1
    RESULT1=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 ping 2>&1" || echo "ERROR")
    echo "    127.0.0.1: ${RESULT1}"
    
    # Essayer IP interne
    RESULT2=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis-sentinel redis-cli -h ${ip} -p 26379 ping 2>&1" || echo "ERROR")
    echo "    ${ip}: ${RESULT2}"
    
    # Essayer sans IP (socket Unix)
    RESULT3=$(ssh ${SSH_OPTS} root@${ip} "docker exec redis-sentinel redis-cli -p 26379 ping 2>&1" || echo "ERROR")
    echo "    socket: ${RESULT3}"
done
echo ""

# 3. PgBouncer
echo "=== 3. PgBouncer ==="
for ip in 10.0.0.11 10.0.0.12; do
    echo "  ${ip}:"
    
    # Test 1: Avec PGPASSWORD
    ssh ${SSH_OPTS} root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/postgres.env 2>/dev/null
echo "    Test 1 (PGPASSWORD):"
PGPASSWORD="\${POSTGRES_SUPERPASS}" docker exec -e PGPASSWORD="\${POSTGRES_SUPERPASS}" pgbouncer psql -h 127.0.0.1 -p 6432 -U \${POSTGRES_SUPERUSER} -d postgres -c "SELECT 1;" 2>&1 | head -3 || echo "    ERREUR"
EOF
    
    # Test 2: Avec connection string
    ssh ${SSH_OPTS} root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/postgres.env 2>/dev/null
echo "    Test 2 (connection string):"
docker exec pgbouncer psql "host=127.0.0.1 port=6432 user=\${POSTGRES_SUPERUSER} password=\${POSTGRES_SUPERPASS} dbname=postgres" -c "SELECT 1;" 2>&1 | head -3 || echo "    ERREUR"
EOF
    
    # Test 3: Vérifier que PgBouncer peut se connecter à PostgreSQL
    echo "    Test 3 (connectivité PgBouncer -> PostgreSQL):"
    ssh ${SSH_OPTS} root@${ip} "docker exec pgbouncer nc -zv 10.0.0.10 5432 2>&1 | head -2 || echo '    ERREUR'"
done
echo ""

