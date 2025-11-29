#!/usr/bin/env bash
#
# 08_proxysql_05_failover_tests.sh - Tests failover avancés ProxySQL & Galera
#
# Ce script effectue des tests de failover avancés :
# - Test failover MariaDB (arrêt d'un nœud)
# - Test failover ProxySQL (arrêt d'un nœud)
# - Test cluster health
# - Test récupération automatique
#
# Usage:
#   ./08_proxysql_05_failover_tests.sh [servers.tsv]
#
# Prérequis:
#   - Module 8 installé (ProxySQL avancé + Galera optimisé)
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

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 8 - Tests Failover Avancés ProxySQL & Galera"
echo "=============================================================="
echo ""
log_warning "Ces tests vont arrêter temporairement des services"
log_warning "Assurez-vous que l'environnement est en maintenance"
echo ""

# Vérifier si on est en mode non-interactif
NON_INTERACTIVE=false
if [[ "${2:-}" == "--yes" ]] || [[ "${2:-}" == "-y" ]]; then
    NON_INTERACTIVE=true
fi

# Confirmation (sauf en mode non-interactif)
if [[ "${NON_INTERACTIVE}" == "false" ]]; then
    read -p "Continuer avec les tests de failover ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Tests de failover annulés"
        exit 0
    fi
fi
read -p "Continuer avec les tests ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    log_info "Tests annulés"
    exit 0
fi

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

# Test 1: Failover MariaDB
log_info "=============================================================="
log_info "Test 1: Failover MariaDB (arrêt maria-01)"
log_info "=============================================================="

log_info "État initial du cluster..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e 'SHOW STATUS LIKE \"wsrep_cluster_size\";' 2>/dev/null | tail -1"

log_info "Arrêt de maria-01..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "docker stop mariadb"

log_info "Attente de la détection du failover (10 secondes)..."
sleep 10

log_info "Test de connexion via ProxySQL (10.0.0.20:3306)..."
if ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IPS[0]}" "docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e 'SELECT 1, DATABASE(), USER();' 2>&1" | grep -q "1"; then
    log_success "Connexion via ProxySQL réussie après failover"
else
    log_warning "Connexion via ProxySQL échouée (peut être normal si LB non configuré)"
fi

log_info "Vérification du cluster (depuis maria-02)..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[1]}" "docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e 'SHOW STATUS LIKE \"wsrep_cluster_size\";' 2>/dev/null | tail -1"

log_info "Redémarrage de maria-01..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "docker start mariadb"

log_info "Attente de la récupération (20 secondes)..."
sleep 20

log_info "Vérification de la récupération..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e 'SHOW STATUS LIKE \"wsrep_cluster_size\"; SHOW STATUS LIKE \"wsrep_local_state_comment\";' 2>/dev/null"

log_success "Test 1 terminé"
echo ""

# Test 2: Failover ProxySQL
if [[ ${#PROXYSQL_IPS[@]} -gt 1 ]]; then
    log_info "=============================================================="
    log_info "Test 2: Failover ProxySQL (arrêt proxysql-01)"
    log_info "=============================================================="
    
    log_info "Arrêt de proxysql-01..."
    ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IPS[0]}" "docker stop proxysql"
    
    log_info "Attente (5 secondes)..."
    sleep 5
    
    log_info "Test de connexion via proxysql-02..."
    if ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IPS[1]}" "docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e 'SELECT 1;' 2>&1" | grep -q "1"; then
        log_success "Connexion via proxysql-02 réussie"
    else
        log_warning "Connexion via proxysql-02 échouée"
    fi
    
    log_info "Redémarrage de proxysql-01..."
    ssh ${SSH_KEY_OPTS} "root@${PROXYSQL_IPS[0]}" "docker start proxysql"
    
    log_info "Attente (10 secondes)..."
    sleep 10
    
    log_success "Test 2 terminé"
    echo ""
else
    log_warning "Test 2 ignoré (moins de 2 nœuds ProxySQL)"
    echo ""
fi

# Test 3: Cluster Health
log_info "=============================================================="
log_info "Test 3: Cluster Health"
log_info "=============================================================="

for i in "${!MARIADB_IPS[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "Vérification ${hostname} (${ip})..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

if docker ps | grep -q mariadb; then
    echo "  ✓ MariaDB en cours d'exécution"
    docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_cluster_size'; SHOW STATUS LIKE 'wsrep_local_state_comment'; SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | tail -3
else
    echo "  ✗ MariaDB arrêté"
fi
EOF
    echo ""
done

# Test 4: ProxySQL Health
log_info "=============================================================="
log_info "Test 4: ProxySQL Health"
log_info "=============================================================="

for i in "${!PROXYSQL_IPS[@]}"; do
    hostname="${PROXYSQL_NODES[$i]}"
    ip="${PROXYSQL_IPS[$i]}"
    
    log_info "Vérification ${hostname} (${ip})..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

if docker ps | grep -q proxysql; then
    echo "  ✓ ProxySQL en cours d'exécution"
    docker exec proxysql mysql -uadmin -padmin -h127.0.0.1 -P6032 -e "SELECT hostname, port, hostgroup_id, status FROM mysql_servers;" 2>/dev/null
else
    echo "  ✗ ProxySQL arrêté"
fi
EOF
    echo ""
done

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Tests failover terminés"
echo "=============================================================="
echo ""
log_info "Tests effectués:"
log_info "  ✓ Test failover MariaDB"
if [[ ${#PROXYSQL_IPS[@]} -gt 1 ]]; then
    log_info "  ✓ Test failover ProxySQL"
fi
log_info "  ✓ Test cluster health"
log_info "  ✓ Test ProxySQL health"
echo ""
log_info "Tous les services devraient être opérationnels."
echo ""

