#!/usr/bin/env bash
#
# fix_user_erpnext_complete.sh - Corriger complètement l'utilisateur erpnext
#

set -euo pipefail

MARIADB_IP="${1:-10.0.0.170}"

echo "=============================================================="
echo " Correction utilisateur erpnext"
echo "=============================================================="
echo ""

ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} bash <<'EOF'
source /tmp/mariadb.env 2>/dev/null || source /opt/keybuzz-installer/credentials/mariadb.env

echo "1. Vérification utilisateurs existants:"
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e "SELECT User, Host FROM mysql.user WHERE User='${MARIADB_APP_USER}';" 2>&1 || true
echo ""

echo "2. Suppression de l'utilisateur existant (tous les hosts):"
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e "DROP USER IF EXISTS '${MARIADB_APP_USER}'@'%';" 2>&1 || true
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e "DROP USER IF EXISTS '${MARIADB_APP_USER}'@'localhost';" 2>&1 || true
echo ""

echo "3. Création de la base de données:"
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e "CREATE DATABASE IF NOT EXISTS ${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1 || true
echo ""

echo "4. Création de l'utilisateur avec le bon mot de passe:"
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} <<SQL
CREATE USER '${MARIADB_APP_USER}'@'%' IDENTIFIED BY '${MARIADB_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON ${MARIADB_DB}.* TO '${MARIADB_APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL
echo ""

echo "5. Vérification de l'utilisateur créé:"
docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e "SELECT User, Host FROM mysql.user WHERE User='${MARIADB_APP_USER}';" 2>&1
echo ""

echo "6. Test de connexion directe:"
docker exec mariadb mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -e "SELECT 1, DATABASE(), USER();" 2>&1 || echo "ERREUR"
echo ""

echo "7. Test de connexion depuis l'extérieur (simulation ProxySQL):"
docker exec mariadb mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h10.0.0.170 -e "SELECT 1, DATABASE(), USER();" 2>&1 || echo "ERREUR"
echo ""
EOF

echo "Correction terminée."

