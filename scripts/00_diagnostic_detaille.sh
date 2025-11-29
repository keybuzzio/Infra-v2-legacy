#!/usr/bin/env bash
#
# 00_diagnostic_detaille.sh - Diagnostic détaillé des services
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
INSTALL_DIR="/opt/keybuzz-installer"

# Charger les credentials
source "${INSTALL_DIR}/credentials/postgres.env" 2>/dev/null || true
source "${INSTALL_DIR}/credentials/redis.env" 2>/dev/null || true

echo "=============================================================="
echo " Diagnostic Détaillé"
echo "=============================================================="
echo ""

# PostgreSQL
echo "=== PostgreSQL (10.0.0.120) ==="
echo "1. Test avec utilisateur postgres:"
ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni psql -U postgres -d postgres -c 'SELECT version();' 2>&1 | head -3" || echo "  ERREUR"
echo ""

echo "2. Test avec utilisateur ${POSTGRES_SUPERUSER:-kb_admin}:"
if [[ -n "${POSTGRES_SUPERUSER:-}" ]]; then
    ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni psql -U ${POSTGRES_SUPERUSER} -d postgres -c 'SELECT version();' 2>&1 | head -3" || echo "  ERREUR"
else
    echo "  POSTGRES_SUPERUSER non défini"
fi
echo ""

# Redis - Vérifier comment Redis est configuré
echo "=== Redis (10.0.0.123) ==="
echo "1. Configuration Redis (bind/port):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli CONFIG GET bind 2>&1" || echo "  ERREUR"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli CONFIG GET port 2>&1" || echo "  ERREUR"
echo ""

echo "2. Test connexion Redis (sans IP, socket Unix):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli ping 2>&1" || echo "  ERREUR"
echo ""

echo "3. Test connexion Redis (avec auth, sans IP):"
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli -a '${REDIS_PASSWORD}' ping 2>&1" || echo "  ERREUR"
else
    echo "  REDIS_PASSWORD non défini"
fi
echo ""

echo "4. Test connexion Redis (avec IP interne du serveur):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 ping 2>&1" || echo "  ERREUR"
if [[ -n "${REDIS_PASSWORD:-}" ]]; then
    ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 -a '${REDIS_PASSWORD}' ping 2>&1" || echo "  ERREUR"
fi
echo ""

echo "5. Info réplication (sans IP):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli INFO replication 2>&1 | grep -E 'role:|connected_slaves:' || echo '  ERREUR'" || echo "  Erreur connexion"
echo ""

# Sentinel
echo "6. Sentinel (sans IP):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis-sentinel redis-cli -p 26379 ping 2>&1" || echo "  ERREUR"
echo ""

echo "7. Sentinel (avec IP):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis-sentinel redis-cli -h 10.0.0.123 -p 26379 ping 2>&1" || echo "  ERREUR"
echo ""

# PgBouncer
echo "=== PgBouncer (10.0.0.11) ==="
echo "1. Test avec utilisateur postgres:"
ssh ${SSH_OPTS} root@10.0.0.11 "docker exec pgbouncer psql -h 127.0.0.1 -p 6432 -U postgres -d postgres -c 'SELECT 1;' 2>&1" || echo "  ERREUR"
echo ""

echo "2. Test avec utilisateur ${POSTGRES_SUPERUSER:-kb_admin}:"
if [[ -n "${POSTGRES_SUPERUSER:-}" ]] && [[ -n "${POSTGRES_SUPERPASS:-}" ]]; then
    ssh ${SSH_OPTS} root@10.0.0.11 "PGPASSWORD='${POSTGRES_SUPERPASS}' docker exec -e PGPASSWORD='${POSTGRES_SUPERPASS}' pgbouncer psql -h 127.0.0.1 -p 6432 -U ${POSTGRES_SUPERUSER} -d postgres -c 'SELECT 1;' 2>&1" || echo "  ERREUR"
else
    echo "  Credentials non définis"
fi
echo ""

