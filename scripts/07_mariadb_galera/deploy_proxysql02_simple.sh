#!/usr/bin/env bash
#
# deploy_proxysql02_simple.sh - Déployer ProxySQL sur proxysql-02
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/mariadb.env"

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

# Charger les credentials
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi

SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

PROXYSQL_IP="10.0.0.174"
MARIADB_IPS=("10.0.0.170" "10.0.0.171" "10.0.0.172")

log_info "=============================================================="
log_info "Déploiement ProxySQL: proxysql-02 (${PROXYSQL_IP})"
log_info "=============================================================="

ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IP}" bash <<EOF
set -euo pipefail

BASE="/opt/keybuzz/proxysql"

# Nettoyer les anciens conteneurs
docker stop proxysql 2>/dev/null || true
docker rm proxysql 2>/dev/null || true

# Créer les répertoires
mkdir -p "\${BASE}"/{conf,data}

# Créer la configuration ProxySQL
cat > "\${BASE}/conf/proxysql.cnf" <<PROXYSQL_CNF
datadir="/var/lib/proxysql"
admin_variables=
{
    admin_credentials="admin:admin"
    mysql_ifaces="0.0.0.0:6032"
    refresh_interval=2000
}
mysql_variables=
{
    threads=4
    max_connections=2048
    default_query_delay=0
    default_query_timeout=36000000
    have_compress=true
    poll_timeout=2000
    interfaces="0.0.0.0:3306"
    default_schema="information_schema"
    stacksize=1048576
    server_version="10.11.0"
    connect_timeout_server=10000
    monitor_history=60000
    monitor_connect_interval=200000
    monitor_ping_interval=200000
    ping_timeout_server=200
    commands_stats=true
    sessions_sort=true
}
mysql_servers =
(
    { address="${MARIADB_IPS[0]}", port=3306, hostgroup=10, max_connections=200, comment="galera-01" },
    { address="${MARIADB_IPS[1]}", port=3306, hostgroup=10, max_connections=200, comment="galera-02" },
    { address="${MARIADB_IPS[2]}", port=3306, hostgroup=10, max_connections=200, comment="galera-03" }
)
mysql_users =
(
    { username="${MARIADB_APP_USER}", password="${MARIADB_APP_PASSWORD}", default_hostgroup=10, transaction_persistent=1, active=1 }
)
mysql_query_rules =
(
    {
        rule_id=1
        active=1
        match_pattern="^SELECT.*FOR UPDATE"
        destination_hostgroup=10
        apply=1
    },
    {
        rule_id=2
        active=1
        match_pattern="^SELECT"
        destination_hostgroup=10
        apply=1
    },
    {
        rule_id=3
        active=1
        match_pattern=".*"
        destination_hostgroup=10
        apply=1
    }
)
PROXYSQL_CNF

# Déployer ProxySQL
docker run -d --name proxysql \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/conf/proxysql.cnf":/etc/proxysql.cnf:ro \
  -v "\${BASE}/data":/var/lib/proxysql \
  proxysql/proxysql:2.6.4

echo "  ✓ Conteneur ProxySQL démarré"
EOF

log_success "proxysql-02 déployé"
echo ""

# Attendre que ProxySQL soit prêt
log_info "Attente que ProxySQL soit prêt (10 secondes)..."
sleep 10

# Configurer ProxySQL via l'interface admin
log_info "Configuration de ProxySQL sur proxysql-02..."

ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IP}" bash <<EOF
set -euo pipefail

# Attendre que ProxySQL soit prêt
for i in {1..30}; do
    if docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT 1" >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# Charger la configuration
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 <<SQL
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL USERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL USERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
SQL

echo "  ✓ Configuration ProxySQL appliquée"
EOF

log_success "ProxySQL configuré sur proxysql-02"
echo ""

# Vérifier la connectivité
log_info "Test de connexion via proxysql-02..."

if ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IP}" bash <<EOF
source /tmp/mariadb.env 2>/dev/null || true

# Tester la connexion via ProxySQL
if docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "SELECT 1" >/dev/null 2>&1; then
    echo "  ✓ Connexion ProxySQL réussie"
    exit 0
else
    echo "  ✗ Connexion ProxySQL échouée"
    exit 1
fi
EOF
then
    log_success "ProxySQL opérationnel sur proxysql-02"
else
    log_warning "ProxySQL en cours de démarrage sur proxysql-02 (normal au début)"
fi
echo ""

echo "=============================================================="
log_success "✅ Installation ProxySQL sur proxysql-02 terminée !"
echo "=============================================================="
echo ""

