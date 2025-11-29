#!/usr/bin/env bash
#
# 00_test_redis_pg_direct.sh - Tests directs Redis et PostgreSQL
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALL_DIR="/opt/keybuzz-installer"

# Charger les credentials
source "${INSTALL_DIR}/credentials/postgres.env" 2>/dev/null || true
source "${INSTALL_DIR}/credentials/redis.env" 2>/dev/null || true

echo "=== Tests Redis ==="
echo ""

# Redis - Test avec credentials chargés
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    echo "Redis ${ip}:"
    ssh ${SSH_OPTS} root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null
if [[ -n "\${REDIS_PASSWORD:-}" ]]; then
    docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} ping 2>&1
    docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} INFO replication 2>&1 | grep -E "role:|connected_slaves:" | head -2
else
    echo "  REDIS_PASSWORD non défini"
fi
EOF
    echo ""
done

echo "=== Tests PostgreSQL Réplication ==="
echo ""

# PostgreSQL - Vérifier les rôles
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    echo "PostgreSQL ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "curl -s http://localhost:8008/patroni 2>/dev/null | grep -o '\"role\":\"[^\"]*\"' | cut -d'\"' -f4" || echo "  ERREUR"
    echo ""
done

echo "=== Test PgBouncer ==="
echo ""

# PgBouncer
ssh ${SSH_OPTS} root@10.0.0.11 bash <<EOF
source /opt/keybuzz-installer/credentials/postgres.env 2>/dev/null
if [[ -n "\${POSTGRES_SUPERUSER:-}" ]] && [[ -n "\${POSTGRES_SUPERPASS:-}" ]]; then
    PGPASSWORD="\${POSTGRES_SUPERPASS}" docker exec -e PGPASSWORD="\${POSTGRES_SUPERPASS}" pgbouncer psql -h 127.0.0.1 -p 6432 -U \${POSTGRES_SUPERUSER} -d postgres -c "SELECT 1;" 2>&1
else
    echo "  Credentials non définis"
fi
EOF

