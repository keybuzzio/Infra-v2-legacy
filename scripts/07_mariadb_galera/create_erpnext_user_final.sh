#!/usr/bin/env bash
#
# create_erpnext_user_final.sh - Créer l'utilisateur erpnext sur le cluster Galera
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/mariadb.env"
MARIADB_IP="${1:-10.0.0.170}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Vérifier les credentials
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Vérifier que les variables sont définies
if [[ -z "${MARIADB_ROOT_PASSWORD:-}" ]] || [[ -z "${MARIADB_APP_USER:-}" ]] || [[ -z "${MARIADB_APP_PASSWORD:-}" ]] || [[ -z "${MARIADB_DB:-}" ]]; then
    log_error "Variables manquantes dans ${CREDENTIALS_FILE}"
    exit 1
fi

log_info "=============================================================="
log_info "Création de l'utilisateur erpnext sur le cluster Galera"
log_info "=============================================================="
echo ""

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi

SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

log_info "Connexion à ${MARIADB_IP}..."

# Créer l'utilisateur et la base de données
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IP}" bash <<EOF
set -euo pipefail

# Variables (échappées pour SSH)
MARIADB_ROOT_PASSWORD='${MARIADB_ROOT_PASSWORD}'
MARIADB_APP_USER='${MARIADB_APP_USER}'
MARIADB_APP_PASSWORD='${MARIADB_APP_PASSWORD}'
MARIADB_DB='${MARIADB_DB}'

echo "1. Vérification des utilisateurs existants..."
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';" 2>&1 || true
echo ""

echo "2. Suppression de l'utilisateur existant (si présent)..."
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'%';" 2>&1 || true
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'localhost';" 2>&1 || true
echo ""

echo "3. Création de la base de données..."
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "CREATE DATABASE IF NOT EXISTS \${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1
if [ \$? -eq 0 ]; then
    echo "  ✓ Base de données créée"
else
    echo "  ✗ Erreur lors de la création de la base de données"
    exit 1
fi
echo ""

echo "4. Création de l'utilisateur..."
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE USER '\${MARIADB_APP_USER}'@'%' IDENTIFIED BY '\${MARIADB_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \${MARIADB_DB}.* TO '\${MARIADB_APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

if [ \$? -eq 0 ]; then
    echo "  ✓ Utilisateur créé"
else
    echo "  ✗ Erreur lors de la création de l'utilisateur"
    exit 1
fi
echo ""

echo "5. Vérification de l'utilisateur créé..."
docker exec mariadb mysql -uroot -p"\${MARIADB_ROOT_PASSWORD}" -e "SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';" 2>&1
echo ""

echo "6. Test de connexion directe..."
docker exec mariadb mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h127.0.0.1 -e "SELECT 1 as test, DATABASE() as db, USER() as user;" 2>&1
if [ \$? -eq 0 ]; then
    echo "  ✓ Connexion directe réussie"
else
    echo "  ✗ Erreur de connexion directe"
    exit 1
fi
echo ""

echo "7. Test de connexion depuis l'extérieur (simulation ProxySQL)..."
docker exec mariadb mysql -u\${MARIADB_APP_USER} -p\${MARIADB_APP_PASSWORD} -h10.0.0.170 -e "SELECT 1 as test, DATABASE() as db, USER() as user;" 2>&1
if [ \$? -eq 0 ]; then
    echo "  ✓ Connexion externe réussie"
else
    echo "  ⚠ Connexion externe échouée (peut être normal selon la configuration réseau)"
fi
echo ""

EOF

if [ $? -eq 0 ]; then
    log_success "Utilisateur erpnext créé avec succès sur le cluster Galera"
    echo ""
    log_info "L'utilisateur sera répliqué automatiquement sur tous les nœuds du cluster Galera"
    log_info "ProxySQL devrait maintenant pouvoir se connecter au cluster"
    exit 0
else
    log_error "Échec de la création de l'utilisateur erpnext"
    exit 1
fi

