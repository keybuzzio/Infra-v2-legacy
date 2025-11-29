#!/usr/bin/env bash
#
# diagnostic_proxysql.sh - Diagnostic complet ProxySQL
#

set -euo pipefail

PROXYSQL_IP="${1:-10.0.0.173}"
MARIADB_IP="${2:-10.0.0.170}"

echo "=============================================================="
echo " Diagnostic ProxySQL"
echo "=============================================================="
echo ""

echo "1. État des serveurs MariaDB dans ProxySQL:"
ssh -o StrictHostKeyChecking=no root@${PROXYSQL_IP} "docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e 'SELECT hostgroup_id, hostname, port, status, weight FROM mysql_servers;'"
echo ""

echo "2. Utilisateurs configurés dans ProxySQL:"
ssh -o StrictHostKeyChecking=no root@${PROXYSQL_IP} "docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e 'SELECT username, active, default_hostgroup FROM mysql_users;'"
echo ""

echo "3. Vérification utilisateur erpnext dans MariaDB:"
ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} "source /tmp/mariadb.env 2>/dev/null && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e \"SELECT User, Host FROM mysql.user WHERE User='erpnext';\""
echo ""

echo "4. Test connexion directe MariaDB avec erpnext:"
ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} "source /tmp/mariadb.env 2>/dev/null && docker exec mariadb mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -e 'SELECT 1, DATABASE(), USER();' 2>&1 || echo 'ERREUR'"
echo ""

echo "5. Test connexion via ProxySQL:"
ssh -o StrictHostKeyChecking=no root@${PROXYSQL_IP} "source /tmp/mariadb.env 2>/dev/null && docker exec proxysql mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e 'SELECT 1, DATABASE(), USER();' 2>&1 || echo 'ERREUR'"
echo ""

echo "6. Logs ProxySQL (dernières lignes):"
ssh -o StrictHostKeyChecking=no root@${PROXYSQL_IP} "docker logs proxysql 2>&1 | tail -20"
echo ""

