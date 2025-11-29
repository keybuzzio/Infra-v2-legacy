#!/usr/bin/env bash
#
# 00_diagnostic_postgres_redis.sh - Diagnostic détaillé PostgreSQL et Redis
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALL_DIR="/opt/keybuzz-installer"

# Charger les credentials
source "${INSTALL_DIR}/credentials/postgres.env" 2>/dev/null || true
source "${INSTALL_DIR}/credentials/redis.env" 2>/dev/null || true

echo "=============================================================="
echo " Diagnostic PostgreSQL et Redis"
echo "=============================================================="
echo ""

# PostgreSQL
echo "=== PostgreSQL (10.0.0.120) ==="
echo "1. Conteneur:"
ssh ${SSH_OPTS} root@10.0.0.120 "docker ps | grep patroni || echo '  Aucun conteneur patroni'" 2>/dev/null || echo "  Erreur connexion"
echo ""

echo "2. Test connexion directe:"
PG_USER="${POSTGRES_SUPERUSER:-postgres}"
ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni psql -U ${PG_USER} -c 'SELECT version();' 2>&1 | head -3" 2>/dev/null || echo "  ERREUR"
echo ""

echo "3. Patroni API:"
ssh ${SSH_OPTS} root@10.0.0.120 "curl -s http://localhost:8008/patroni 2>/dev/null | head -5 || echo '  ERREUR'" 2>/dev/null || echo "  Erreur connexion"
echo ""

echo "4. Patroni cluster status:"
ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni patronictl list 2>&1 | head -10" 2>/dev/null || echo "  ERREUR"
echo ""

# Redis
echo "=== Redis (10.0.0.123) ==="
echo "1. Conteneurs:"
ssh ${SSH_OPTS} root@10.0.0.123 "docker ps | grep -E 'redis|sentinel' || echo '  Aucun conteneur redis'" 2>/dev/null || echo "  Erreur connexion"
echo ""

echo "2. Test connexion Redis (sans auth):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli ping 2>&1" 2>/dev/null || echo "  ERREUR"
echo ""

echo "3. Test connexion Redis (avec auth):"
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli -a '${REDIS_PASSWORD}' ping 2>&1" 2>/dev/null || echo "  ERREUR"
else
    echo "  REDIS_PASSWORD non défini"
fi
echo ""

echo "4. Info réplication Redis:"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli INFO replication 2>&1 | grep -E 'role:|connected_slaves:' || echo '  ERREUR'" 2>/dev/null || echo "  Erreur connexion"
echo ""

echo "5. Sentinel:"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis-sentinel redis-cli -p 26379 ping 2>&1" 2>/dev/null || echo "  ERREUR"
echo ""

# PgBouncer
echo "=== PgBouncer (10.0.0.11) ==="
echo "1. Conteneur:"
ssh ${SSH_OPTS} root@10.0.0.11 "docker ps | grep pgbouncer || echo '  Aucun conteneur pgbouncer'" 2>/dev/null || echo "  Erreur connexion"
echo ""

echo "2. Test connexion:"
PG_USER="${POSTGRES_SUPERUSER:-postgres}"
ssh ${SSH_OPTS} root@10.0.0.11 "docker exec pgbouncer psql -h localhost -p 6432 -U ${PG_USER} -d postgres -c 'SELECT 1;' 2>&1" 2>/dev/null || echo "  ERREUR"
echo ""

