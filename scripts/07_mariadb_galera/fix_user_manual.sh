#!/usr/bin/env bash
#
# fix_user_manual.sh - Créer l'utilisateur erpnext manuellement
#

set -euo pipefail

MARIADB_IP="${1:-10.0.0.170}"

# Lire les credentials depuis install-01
CREDENTIALS_FILE="/opt/keybuzz-installer/credentials/mariadb.env"
source "${CREDENTIALS_FILE}"

echo "Création manuelle de l'utilisateur ${MARIADB_APP_USER}..."
echo "Base de données: ${MARIADB_DB}"
echo ""

ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} <<EOF
source /tmp/mariadb.env

# Afficher les credentials pour debug
echo "MARIADB_APP_USER: \${MARIADB_APP_USER}"
echo "MARIADB_DB: \${MARIADB_DB}"
echo "MARIADB_ROOT_PASSWORD: \${MARIADB_ROOT_PASSWORD:0:5}..."
echo ""

# Créer la base
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1

# Supprimer l'utilisateur existant
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'%';" 2>&1 || true
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'localhost';" 2>&1 || true

# Créer l'utilisateur
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "CREATE USER '\${MARIADB_APP_USER}'@'%' IDENTIFIED BY '\${MARIADB_APP_PASSWORD}';" 2>&1

# Accorder les privilèges
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "GRANT ALL PRIVILEGES ON \${MARIADB_DB}.* TO '\${MARIADB_APP_USER}'@'%';" 2>&1

# Flush
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "FLUSH PRIVILEGES;" 2>&1

# Vérifier
echo ""
echo "Utilisateurs créés:"
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';" 2>&1

# Tester
echo ""
echo "Test de connexion:"
docker exec mariadb mysql -u"\${MARIADB_APP_USER}" -p"\${MARIADB_APP_PASSWORD}" -h127.0.0.1 -e "SELECT 1, DATABASE(), USER();" 2>&1 || echo "ERREUR"
EOF

