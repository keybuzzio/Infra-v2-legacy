#!/usr/bin/env bash
#
# fix_user_erpnext.sh - Créer l'utilisateur erpnext dans MariaDB
#

set -euo pipefail

MARIADB_IP="${1:-10.0.0.170}"
CREDENTIALS_FILE="/opt/keybuzz-installer/credentials/mariadb.env"

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    echo "ERREUR: Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

echo "Création de l'utilisateur ${MARIADB_APP_USER} dans MariaDB..."

ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} bash <<EOF
source /tmp/mariadb.env 2>/dev/null || source /opt/keybuzz-installer/credentials/mariadb.env

docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} <<SQL
CREATE DATABASE IF NOT EXISTS \${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '\${MARIADB_APP_USER}'@'%' IDENTIFIED BY '\${MARIADB_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \${MARIADB_DB}.* TO '\${MARIADB_APP_USER}'@'%';
FLUSH PRIVILEGES;
SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';
SQL

echo "Test de connexion avec l'utilisateur \${MARIADB_APP_USER}..."
docker exec mariadb mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -e "SELECT 1, DATABASE(), USER();" 2>&1 || echo "ERREUR connexion"
EOF

echo ""
echo "Utilisateur créé. Vérification..."
ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} "source /tmp/mariadb.env 2>/dev/null || source /opt/keybuzz-installer/credentials/mariadb.env && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e \"SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';\""

