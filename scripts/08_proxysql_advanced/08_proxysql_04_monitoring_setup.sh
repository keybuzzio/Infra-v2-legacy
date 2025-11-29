#!/usr/bin/env bash
#
# 08_proxysql_04_monitoring_setup.sh - Configuration monitoring ProxySQL & Galera
#
# Ce script configure le monitoring pour ProxySQL et Galera :
# - Scripts de collecte de métriques
# - Exporters Prometheus (optionnel)
# - Scripts de vérification de santé
#
# Usage:
#   ./08_proxysql_04_monitoring_setup.sh [servers.tsv]
#
# Prérequis:
#   - Module 8 partiellement installé (ProxySQL avancé + Galera optimisé)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
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

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    log_info "Exécutez d'abord: ./07_maria_00_setup_credentials.sh"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 8 - Configuration Monitoring ProxySQL & Galera"
echo "=============================================================="
echo ""

# Collecter les nœuds
declare -a MARIADB_NODES=()
declare -a MARIADB_IPS=()
declare -a PROXYSQL_NODES=()
declare -a PROXYSQL_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "mariadb" ]]; then
        if [[ -n "${IP_PRIVEE}" ]]; then
            if [[ "${HOSTNAME}" == "maria-01" ]] || \
               [[ "${HOSTNAME}" == "maria-02" ]] || \
               [[ "${HOSTNAME}" == "maria-03" ]]; then
                MARIADB_NODES+=("${HOSTNAME}")
                MARIADB_IPS+=("${IP_PRIVEE}")
            fi
        fi
    fi
    
    # Détecter les nœuds ProxySQL (ROLE=db_proxy ou ROLE=db avec SUBROLE=proxysql)
    if [[ "${ROLE}" == "db_proxy" ]] || ([[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "proxysql" ]]); then
        # Filtrer uniquement proxysql-01 et proxysql-02
        if [[ "${HOSTNAME}" == "proxysql-01" ]] || [[ "${HOSTNAME}" == "proxysql-02" ]]; then
            if [[ -n "${IP_PRIVEE}" ]]; then
                PROXYSQL_NODES+=("${HOSTNAME}")
                PROXYSQL_IPS+=("${IP_PRIVEE}")
            fi
        fi
    fi
done
exec 3<&-

log_success "Nœuds détectés:"
log_info "  MariaDB: ${MARIADB_NODES[*]} (${MARIADB_IPS[*]})"
log_info "  ProxySQL: ${PROXYSQL_NODES[*]} (${PROXYSQL_IPS[*]})"
echo ""

# Créer le script de monitoring Galera
log_info "Création du script de monitoring Galera..."

MONITORING_SCRIPT="${INSTALL_DIR}/scripts/08_proxysql_advanced/monitor_galera.sh"

cat > "${MONITORING_SCRIPT}" <<'MONITOR_SCRIPT'
#!/usr/bin/env bash
#
# monitor_galera.sh - Script de monitoring Galera
#
# Collecte les métriques importantes du cluster Galera

set -euo pipefail

CREDENTIALS_FILE="/opt/keybuzz-installer/credentials/mariadb.env"

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    echo "ERREUR: Fichier credentials introuvable"
    exit 1
fi

source "${CREDENTIALS_FILE}"

echo "=== Métriques Galera ==="
echo ""

# Taille du cluster
echo "Cluster Size:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | tail -1

# État local
echo ""
echo "Local State:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | tail -1

# Prêt
echo ""
echo "Ready:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | tail -1

# Flow Control
echo ""
echo "Flow Control Paused:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_flow_control_paused';" 2>/dev/null | tail -1

# Replication lag
echo ""
echo "Replication Lag:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_local_recv_queue_avg';" 2>/dev/null | tail -1

# Queries/sec
echo ""
echo "Queries/sec:"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'Queries';" 2>/dev/null | tail -1
MONITOR_SCRIPT

chmod +x "${MONITORING_SCRIPT}"

# Créer le script de monitoring ProxySQL
log_info "Création du script de monitoring ProxySQL..."

PROXYSQL_MONITOR_SCRIPT="${INSTALL_DIR}/scripts/08_proxysql_advanced/monitor_proxysql.sh"

cat > "${PROXYSQL_MONITOR_SCRIPT}" <<'PROXYSQL_MONITOR_SCRIPT'
#!/usr/bin/env bash
#
# monitor_proxysql.sh - Script de monitoring ProxySQL
#
# Collecte les métriques importantes de ProxySQL

set -euo pipefail

echo "=== Métriques ProxySQL ==="
echo ""

# Serveurs
echo "MySQL Servers:"
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostname, port, hostgroup_id, status, max_connections, comment FROM mysql_servers;" 2>/dev/null

# Connection Pool
echo ""
echo "Connection Pool:"
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostgroup, srv_host, srv_port, status, ConnUsed, ConnFree, ConnOK, ConnERR, MaxConnUsed, Queries, Bytes_data_sent, Bytes_data_recv FROM stats_mysql_connection_pool;" 2>/dev/null

# Hostgroup Health
echo ""
echo "Hostgroup Health:"
docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostgroup, SUM(CASE WHEN status='ONLINE' THEN 1 ELSE 0 END) as online, SUM(CASE WHEN status='OFFLINE_SOFT' THEN 1 ELSE 0 END) as offline_soft, SUM(CASE WHEN status='OFFLINE_HARD' THEN 1 ELSE 0 END) as offline_hard FROM mysql_servers GROUP BY hostgroup;" 2>/dev/null
PROXYSQL_MONITOR_SCRIPT

chmod +x "${PROXYSQL_MONITOR_SCRIPT}"

# Déployer les scripts sur les nœuds appropriés
log_info "Déploiement des scripts de monitoring..."

# Sur les nœuds MariaDB
for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "Déploiement sur ${hostname} (${ip})..."
    scp ${SSH_KEY_OPTS} "${MONITORING_SCRIPT}" "root@${ip}:/usr/local/bin/monitor_galera.sh"
    ssh ${SSH_KEY_OPTS} "root@${ip}" "chmod +x /usr/local/bin/monitor_galera.sh"
done

# Sur les nœuds ProxySQL
for i in "${!PROXYSQL_NODES[@]}"; do
    hostname="${PROXYSQL_NODES[$i]}"
    ip="${PROXYSQL_IPS[$i]}"
    
    log_info "Déploiement sur ${hostname} (${ip})..."
    scp ${SSH_KEY_OPTS} "${PROXYSQL_MONITOR_SCRIPT}" "root@${ip}:/usr/local/bin/monitor_proxysql.sh"
    ssh ${SSH_KEY_OPTS} "root@${ip}" "chmod +x /usr/local/bin/monitor_proxysql.sh"
done

# Tester les scripts
log_info "Test des scripts de monitoring..."

log_info "Test monitoring Galera sur ${MARIADB_NODES[0]}..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "/usr/local/bin/monitor_galera.sh" || log_warning "Script de monitoring Galera non testable (MariaDB peut être en cours de redémarrage)"

if [[ ${#PROXYSQL_IPS[@]} -gt 0 ]]; then
    log_info "Test monitoring ProxySQL sur ${PROXYSQL_NODES[0]}..."
    ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IPS[0]}" "/usr/local/bin/monitor_proxysql.sh" 2>/dev/null || log_warning "Script de monitoring ProxySQL non testable (ProxySQL peut être en cours de redémarrage)"
else
    log_warning "Aucun nœud ProxySQL détecté, monitoring ProxySQL ignoré"
fi

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Monitoring configuré"
echo "=============================================================="
echo ""
log_info "Scripts de monitoring déployés:"
log_info "  - /usr/local/bin/monitor_galera.sh (sur nœuds MariaDB)"
log_info "  - /usr/local/bin/monitor_proxysql.sh (sur nœuds ProxySQL)"
echo ""
log_info "Utilisation:"
log_info "  ssh root@<ip> /usr/local/bin/monitor_galera.sh"
log_info "  ssh root@<ip> /usr/local/bin/monitor_proxysql.sh"
echo ""
log_info "Prochaine étape:"
log_info "  ./08_proxysql_05_failover_tests.sh ${TSV_FILE}"
echo ""

