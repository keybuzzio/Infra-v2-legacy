#!/usr/bin/env bash
#
# Script pour appliquer la configuration ProxySQL avancée à proxysql-02
#

set -euo pipefail

INSTALL_DIR="/opt/keybuzz-installer"
CONFIG_DIR="${INSTALL_DIR}/config/proxysql_advanced"
PROXYSQL_SQL="${CONFIG_DIR}/apply_proxysql_config.sql"
PROXYSQL_IP="10.0.0.174"
PROXYSQL_HOSTNAME="proxysql-02"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_info "Application configuration ProxySQL avancée sur ${PROXYSQL_HOSTNAME} (${PROXYSQL_IP})"

# Copier le script SQL
log_info "Copie du script SQL..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "${PROXYSQL_SQL}" "root@${PROXYSQL_IP}:/tmp/apply_proxysql_config.sql"

# Appliquer la configuration
log_info "Application de la configuration ProxySQL..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@${PROXYSQL_IP}" bash <<EOF
set -euo pipefail

# Vérifier que ProxySQL est en cours d'exécution
if ! docker ps | grep -q proxysql; then
    echo "ERREUR: ProxySQL n'est pas en cours d'exécution"
    exit 1
fi

# Appliquer le script SQL
docker exec -i proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 < /tmp/apply_proxysql_config.sql

echo "  ✓ Configuration appliquée"
EOF

if [ $? -eq 0 ]; then
    log_success "${PROXYSQL_HOSTNAME}: Configuration appliquée avec succès"
else
    echo "ERREUR: Échec de l'application de la configuration"
    exit 1
fi

# Vérifier la configuration
log_info "Vérification de la configuration..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "root@${PROXYSQL_IP}" bash <<EOF
set -euo pipefail

echo "=== Serveurs Galera ==="
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostname, port, hostgroup_id, status, max_connections, comment FROM mysql_servers;"

echo ""
echo "=== Utilisateurs ==="
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT username, default_hostgroup, max_connections, transaction_persistent, active FROM mysql_users;"

echo ""
echo "=== Query Rules ==="
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT rule_id, active, match_pattern, destination_hostgroup FROM mysql_query_rules;"

echo ""
echo "=== Variables Galera ==="
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT * FROM global_variables WHERE variable_name LIKE 'mysql-galera%' OR variable_name LIKE 'mysql-server_advanced%';"
EOF

echo ""
log_success "✅ Configuration ProxySQL avancée appliquée sur ${PROXYSQL_HOSTNAME}"

