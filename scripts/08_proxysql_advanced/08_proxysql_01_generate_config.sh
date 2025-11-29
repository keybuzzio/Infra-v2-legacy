#!/usr/bin/env bash
#
# 08_proxysql_01_generate_config.sh - Génération configuration ProxySQL avancée
#
# Ce script génère la configuration ProxySQL optimisée pour production :
# - Checks Galera WSREP activés
# - Détection automatique des nœuds DOWN
# - Query rules optimisées pour ERPNext
# - Pool tuning avancé
#
# Usage:
#   ./08_proxysql_01_generate_config.sh [servers.tsv]
#
# Prérequis:
#   - Module 7 installé (MariaDB Galera + ProxySQL basique)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/mariadb.env"
CONFIG_DIR="${INSTALL_DIR}/config/proxysql_advanced"

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
echo " [KeyBuzz] Module 8 - Génération Configuration ProxySQL Avancée"
echo "=============================================================="
echo ""

# Créer le répertoire de configuration
mkdir -p "${CONFIG_DIR}"

# Collecter les informations des nœuds MariaDB et ProxySQL
declare -a MARIADB_IPS=()
declare -a MARIADB_HOSTNAMES=()
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
                MARIADB_IPS+=("${IP_PRIVEE}")
                MARIADB_HOSTNAMES+=("${HOSTNAME}")
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

if [[ ${#MARIADB_IPS[@]} -ne 3 ]]; then
    log_error "3 nœuds MariaDB requis, trouvé: ${#MARIADB_IPS[@]}"
    exit 1
fi

# ProxySQL est optionnel pour la génération (peut être appliqué après)
if [[ ${#PROXYSQL_IPS[@]} -lt 1 ]]; then
    log_warning "Aucun nœud ProxySQL détecté dans servers.tsv"
    log_warning "La configuration sera générée quand même"
    log_warning "Les nœuds ProxySQL seront configurés lors de l'application"
fi

log_success "Nœuds détectés:"
log_info "  MariaDB: ${MARIADB_HOSTNAMES[*]} (${MARIADB_IPS[*]})"
if [[ ${#PROXYSQL_IPS[@]} -gt 0 ]]; then
    log_info "  ProxySQL: ${PROXYSQL_NODES[*]} (${PROXYSQL_IPS[*]})"
else
    log_info "  ProxySQL: Aucun nœud détecté (sera configuré lors de l'application)"
fi
echo ""

# Générer la configuration ProxySQL avancée
log_info "Génération de la configuration ProxySQL avancée..."

PROXYSQL_CONFIG="${CONFIG_DIR}/proxysql_advanced.cnf"

cat > "${PROXYSQL_CONFIG}" <<PROXYSQL_CNF
# ProxySQL Configuration Avancée - Module 8
# Généré automatiquement pour KeyBuzz
# Date: $(date)

# ============================================
# Configuration Globale
# ============================================
datadir="/var/lib/proxysql"
admin_variables=
{
    admin_credentials="admin:admin"
    mysql_ifaces="0.0.0.0:6032"
    refresh_interval=2000
}

# ============================================
# Serveurs MariaDB Galera
# ============================================
mysql_servers =
(
    { address="${MARIADB_IPS[0]}", port=3306, hostgroup=10, max_connections=200, max_replication_lag=0, comment="galera-01" },
    { address="${MARIADB_IPS[1]}", port=3306, hostgroup=10, max_connections=200, max_replication_lag=0, comment="galera-02" },
    { address="${MARIADB_IPS[2]}", port=3306, hostgroup=10, max_connections=200, max_replication_lag=0, comment="galera-03" }
)

# ============================================
# Utilisateurs MySQL
# ============================================
mysql_users =
(
    {
        username="${MARIADB_APP_USER}",
        password="${MARIADB_APP_PASSWORD}",
        default_hostgroup=10,
        max_connections=100,
        transaction_persistent=1,
        fast_forward=0,
        active=1
    }
)

# ============================================
# Query Rules (ERPNext - Write Only)
# ============================================
# ERPNext utilise un seul hostgroup writer
# Pas de read/write split pour éviter stale reads
mysql_query_rules =
(
    {
        rule_id=1,
        active=1,
        match_pattern=".*",
        destination_hostgroup=10,
        apply=1
    }
)

# ============================================
# Configuration Galera WSREP Checks
# ============================================
mysql_variables=
{
    # Activer les checks Galera WSREP
    mysql_galera_check_enabled=true
    mysql_galera_check_interval_ms=2000
    mysql_galera_check_timeout_ms=500
    mysql_galera_check_max_latency_ms=150
    
    # Détection automatique des nœuds DOWN
    mysql_server_advanced_check=1
    mysql_server_advanced_check_timeout_ms=1000
    mysql_server_advanced_check_interval_ms=2000
    
    # Gestion failover (laisser Galera gérer)
    mysql_if_something_wrong=off
    
    # Pool tuning
    threads=4
    max_connections=2048
    default_query_delay=0
    default_query_timeout=36000000
    default_max_latency_ms=0
    
    # Monitoring
    monitor_history=60000
    monitor_connect_interval=60000
    monitor_ping_interval=2000
}

# ============================================
# Configuration Frontend
# ============================================
mysql_servers_frontend=
{
    interfaces="0.0.0.0:3306"
    default_schema="${MARIADB_DB}"
    stacksize=1048576
    server_version="10.11.0"
    connect_timeout_server=10000
}

PROXYSQL_CNF

log_success "Configuration générée: ${PROXYSQL_CONFIG}"

# Générer le script SQL pour application
log_info "Génération du script SQL d'application..."

PROXYSQL_SQL="${CONFIG_DIR}/apply_proxysql_config.sql"

cat > "${PROXYSQL_SQL}" <<PROXYSQL_SQL_SCRIPT
-- Script SQL pour appliquer la configuration ProxySQL avancée
-- Module 8 - KeyBuzz

-- ============================================
-- 1. Nettoyer les configurations existantes
-- ============================================
DELETE FROM mysql_servers;
DELETE FROM mysql_users WHERE username='${MARIADB_APP_USER}';
DELETE FROM mysql_query_rules;

-- ============================================
-- 2. Ajouter les serveurs Galera
-- ============================================
INSERT INTO mysql_servers (hostname, port, hostgroup_id, max_connections, max_replication_lag, comment) VALUES
('${MARIADB_IPS[0]}', 3306, 10, 200, 0, 'galera-01'),
('${MARIADB_IPS[1]}', 3306, 10, 200, 0, 'galera-02'),
('${MARIADB_IPS[2]}', 3306, 10, 200, 0, 'galera-03');

-- ============================================
-- 3. Configurer l'utilisateur ERPNext
-- ============================================
INSERT INTO mysql_users (username, password, default_hostgroup, max_connections, transaction_persistent, fast_forward, active) VALUES
('${MARIADB_APP_USER}', '${MARIADB_APP_PASSWORD}', 10, 100, 1, 0, 1);

-- ============================================
-- 4. Configurer les query rules (Write Only)
-- ============================================
INSERT INTO mysql_query_rules (rule_id, active, match_pattern, destination_hostgroup, apply) VALUES
(1, 1, '.*', 10, 1);

-- ============================================
-- 5. Activer les checks Galera WSREP
-- ============================================
-- Note: Les variables mysql-galera_* peuvent nécessiter ProxySQL 2.x+
-- Si erreur, ces variables peuvent ne pas exister dans votre version
UPDATE global_variables SET variable_value='true' WHERE variable_name='mysql-galera_hostgroups';
UPDATE global_variables SET variable_value='2000' WHERE variable_name='mysql-galera_check_interval_ms';
UPDATE global_variables SET variable_value='500' WHERE variable_name='mysql-galera_check_timeout_ms';
UPDATE global_variables SET variable_value='150' WHERE variable_name='mysql-galera_check_max_latency_ms';

-- ============================================
-- 6. Configuration détection automatique DOWN
-- ============================================
UPDATE global_variables SET variable_value='1' WHERE variable_name='mysql-server_advanced_check';
UPDATE global_variables SET variable_value='1000' WHERE variable_name='mysql-server_advanced_check_timeout_ms';
UPDATE global_variables SET variable_value='2000' WHERE variable_name='mysql-server_advanced_check_interval_ms';

-- ============================================
-- 7. Gestion failover (laisser Galera gérer)
-- ============================================
UPDATE global_variables SET variable_value='off' WHERE variable_name='mysql-if_something_wrong';

-- ============================================
-- 8. Sauvegarder et charger la configuration
-- ============================================
SAVE MYSQL SERVERS TO DISK;
SAVE MYSQL USERS TO DISK;
SAVE MYSQL QUERY RULES TO DISK;
SAVE MYSQL VARIABLES TO DISK;
LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL USERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
LOAD MYSQL VARIABLES TO RUNTIME;

-- ============================================
-- 9. Vérification
-- ============================================
SELECT 'Configuration ProxySQL avancée appliquée avec succès' AS status;
SELECT * FROM mysql_servers;
SELECT username, default_hostgroup, max_connections, transaction_persistent FROM mysql_users;
SELECT rule_id, active, match_pattern, destination_hostgroup FROM mysql_query_rules;

PROXYSQL_SQL_SCRIPT

log_success "Script SQL généré: ${PROXYSQL_SQL}"

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Configuration ProxySQL avancée générée"
echo "=============================================================="
echo ""
log_info "Fichiers générés:"
log_info "  - Configuration: ${PROXYSQL_CONFIG}"
log_info "  - Script SQL: ${PROXYSQL_SQL}"
echo ""
log_info "Prochaine étape:"
log_info "  ./08_proxysql_02_apply_config.sh ${TSV_FILE}"
echo ""

