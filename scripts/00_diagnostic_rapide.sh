#!/usr/bin/env bash
#
# 00_diagnostic_rapide.sh - Diagnostic rapide des services
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=== Diagnostic Rapide ==="
echo ""

# PostgreSQL
echo "PostgreSQL (10.0.0.120):"
ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni psql -U postgres -c 'SELECT version();' 2>&1 | head -1" || echo "  ERREUR"
echo ""

# Redis
echo "Redis (10.0.0.123):"
ssh ${SSH_OPTS} root@10.0.0.123 "docker exec redis redis-cli ping 2>&1" || echo "  ERREUR"
echo ""

# MariaDB
echo "MariaDB (10.0.0.170):"
ssh ${SSH_OPTS} root@10.0.0.170 "source /opt/keybuzz-installer/credentials/mariadb.env 2>/dev/null && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e 'SELECT 1;' 2>&1 | head -1" || echo "  ERREUR"
echo ""

# ProxySQL
echo "ProxySQL (10.0.0.173):"
ssh ${SSH_OPTS} root@10.0.0.173 "source /opt/keybuzz-installer/credentials/mariadb.env 2>/dev/null && docker exec proxysql mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e 'SELECT 1;' 2>&1 | head -1" || echo "  ERREUR"
echo ""

