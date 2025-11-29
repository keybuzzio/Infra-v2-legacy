#!/usr/bin/env bash
#
# 08_proxysql_02_apply_config.sh - Application configuration ProxySQL avancée
#
# Ce script applique la configuration ProxySQL avancée générée par
# 08_proxysql_01_generate_config.sh sur tous les nœuds ProxySQL.
#
# Usage:
#   ./08_proxysql_02_apply_config.sh [servers.tsv]
#
# Prérequis:
#   - Script 08_proxysql_01_generate_config.sh exécuté
#   - Module 7 installé (ProxySQL basique)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CONFIG_DIR="${INSTALL_DIR}/config/proxysql_advanced"
PROXYSQL_SQL="${CONFIG_DIR}/apply_proxysql_config.sql"

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

if [[ ! -f "${PROXYSQL_SQL}" ]]; then
    log_error "Script SQL introuvable: ${PROXYSQL_SQL}"
    log_info "Exécutez d'abord: ./08_proxysql_01_generate_config.sh"
    exit 1
fi

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 8 - Application Configuration ProxySQL Avancée"
echo "=============================================================="
echo ""

# Collecter les nœuds ProxySQL
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

if [[ ${#PROXYSQL_IPS[@]} -lt 1 ]]; then
    log_error "Au moins 1 nœud ProxySQL requis, trouvé: ${#PROXYSQL_IPS[@]}"
    log_info "Vérifiez que les nœuds ProxySQL sont correctement listés dans servers.tsv"
    log_info "Rôle: db, SubRôle: proxysql"
    exit 1
fi

log_success "Nœuds ProxySQL détectés: ${PROXYSQL_NODES[*]} (${PROXYSQL_IPS[*]})"
echo ""

# Copier le script SQL sur chaque nœud et l'appliquer
for i in "${!PROXYSQL_NODES[@]}"; do
    hostname="${PROXYSQL_NODES[$i]}"
    ip="${PROXYSQL_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Application configuration: ${hostname} (${ip})"
    log_info "=============================================================="
    
    # Copier le script SQL
    log_info "Copie du script SQL..."
    scp ${SSH_KEY_OPTS} "${PROXYSQL_SQL}" "root@${ip}:/tmp/apply_proxysql_config.sql"
    
    # Appliquer la configuration
    log_info "Application de la configuration ProxySQL..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
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
        log_success "${hostname}: Configuration appliquée avec succès"
    else
        log_error "${hostname}: Échec de l'application de la configuration"
        exit 1
    fi
    
    # Vérifier la configuration
    log_info "Vérification de la configuration..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
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
done

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Configuration ProxySQL avancée appliquée sur tous les nœuds"
echo "=============================================================="
echo ""
log_info "Prochaine étape:"
log_info "  ./08_proxysql_03_optimize_galera.sh ${TSV_FILE}"
echo ""

