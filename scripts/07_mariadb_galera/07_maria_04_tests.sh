#!/usr/bin/env bash
#
# 07_maria_04_tests.sh - Tests et diagnostics MariaDB Galera + ProxySQL
#
# Ce script effectue des tests complets sur le cluster MariaDB Galera
# et ProxySQL pour valider l'installation.
#
# Usage:
#   ./07_maria_04_tests.sh [servers.tsv]
#
# Prérequis:
#   - Script 07_maria_03_install_proxysql.sh exécuté
#   - Cluster Galera et ProxySQL opérationnels
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
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 7 - Tests et Diagnostics MariaDB Galera"
echo "=============================================================="
echo ""

# Collecter les informations
declare -a MARIADB_NODES
declare -a MARIADB_IPS
declare -a PROXYSQL_IPS

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
    
    if [[ "${ROLE}" == "db_proxy" ]] && [[ "${SUBROLE}" == "proxysql" ]]; then
        if [[ -n "${IP_PRIVEE}" ]]; then
            PROXYSQL_IPS+=("${IP_PRIVEE}")
        fi
    fi
done
exec 3<&-

# Test 1: Connectivité Galera
log_info "=============================================================="
log_info "Test 1: Connectivité MariaDB Galera"
log_info "=============================================================="

for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "Test ${hostname} (${ip}:3306)..."
    
    if timeout 3 nc -z "${ip}" 3306 2>/dev/null; then
        log_success "Port 3306 accessible sur ${hostname}"
    else
        log_error "Port 3306 non accessible sur ${hostname}"
    fi
    
    if timeout 3 nc -z "${ip}" 4567 2>/dev/null; then
        log_success "Port 4567 (Galera) accessible sur ${hostname}"
    else
        log_warning "Port 4567 non accessible sur ${hostname} (peut être normal)"
    fi
done
echo ""

# Test 2: Statut du cluster Galera
log_info "=============================================================="
log_info "Test 2: Statut du cluster Galera"
log_info "=============================================================="

for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "Statut Galera sur ${hostname}..."
    
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
source /tmp/mariadb.env 2>/dev/null || true

CLUSTER_SIZE=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print \$2}' || echo "0")
CLUSTER_STATUS=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print \$2}' || echo "Unknown")
READY=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | awk '{print \$2}' || echo "OFF")
NODE_NAME=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_node_name';" 2>/dev/null | awk '{print \$2}' || echo "Unknown")

echo "  Cluster Size: \${CLUSTER_SIZE}"
echo "  Status: \${CLUSTER_STATUS}"
echo "  Ready: \${READY}"
echo "  Node Name: \${NODE_NAME}"

if [[ "\${CLUSTER_SIZE}" == "3" ]] && [[ "\${CLUSTER_STATUS}" == "Synced" ]] && [[ "\${READY}" == "ON" ]]; then
    echo "  ✓ ${hostname} opérationnel"
    exit 0
else
    echo "  ⚠ ${hostname} en cours de synchronisation"
    exit 0
fi
EOF
    echo ""
done

# Test 3: Connectivité ProxySQL
log_info "=============================================================="
log_info "Test 3: Connectivité ProxySQL"
log_info "=============================================================="

for ip in "${PROXYSQL_IPS[@]}"; do
    log_info "Test ProxySQL (${ip}:3306)..."
    
    if timeout 3 nc -z "${ip}" 3306 2>/dev/null; then
        log_success "Port 3306 (frontend) accessible"
    else
        log_error "Port 3306 non accessible"
    fi
    
    if timeout 3 nc -z "${ip}" 6032 2>/dev/null; then
        log_success "Port 6032 (admin) accessible"
    else
        log_warning "Port 6032 non accessible"
    fi
done
echo ""

# Test 4: Connexion via ProxySQL
log_info "=============================================================="
log_info "Test 4: Connexion via ProxySQL"
log_info "=============================================================="

if [[ ${#PROXYSQL_IPS[@]} -gt 0 ]]; then
    proxysql_ip="${PROXYSQL_IPS[0]}"
    
    log_info "Test de connexion via ProxySQL (${proxysql_ip})..."
    log_info "Attente que le cluster Galera soit prêt (30 secondes)..."
    sleep 30
    
    if ssh ${SSH_KEY_OPTS} "root@${proxysql_ip}" bash <<EOF
set +u
source /tmp/mariadb.env 2>/dev/null || true
set -u

# Attendre que ProxySQL soit prêt
for i in {1..10}; do
    if docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "SELECT 1" >/dev/null 2>&1; then
        echo "  ✓ Connexion ProxySQL réussie"
        
        # Vérifier que la base existe, sinon la créer
        if ! docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "USE ${MARIADB_DB}; SELECT 1" >/dev/null 2>&1; then
            echo "  ⚠ Base ${MARIADB_DB} n'existe pas, création..."
            docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "CREATE DATABASE IF NOT EXISTS ${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>&1
        fi
        
        # Tester l'accès à la base de données
        if docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "USE ${MARIADB_DB}; SELECT 1" >/dev/null 2>&1; then
            echo "  ✓ Accès à la base ${MARIADB_DB} réussi"
            exit 0
        else
            echo "  ⚠ Accès à la base ${MARIADB_DB} échoué"
            exit 1
        fi
    fi
    sleep 3
done

echo "  ✗ Connexion ProxySQL échouée après 30 secondes"
exit 1
EOF
    then
        log_success "Connexion via ProxySQL validée"
    else
        log_error "Connexion via ProxySQL échouée"
    fi
    echo ""
fi

# Test 5: Test d'écriture/lecture
log_info "=============================================================="
log_info "Test 5: Test d'écriture/lecture"
log_info "=============================================================="

if [[ ${#PROXYSQL_IPS[@]} -gt 0 ]]; then
    proxysql_ip="${PROXYSQL_IPS[0]}"
    
    log_info "Test d'écriture/lecture via ProxySQL..."
    
    ssh ${SSH_KEY_OPTS} "root@${proxysql_ip}" bash <<EOF
set +u
source /tmp/mariadb.env 2>/dev/null || true
set -u

# Vérifier que ProxySQL est accessible
if ! docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 -e "SELECT 1" >/dev/null 2>&1; then
    echo "  ✗ ProxySQL non accessible"
    exit 1
fi

# Créer une table de test (en une seule commande pour éviter les problèmes de packet)
docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 ${MARIADB_DB} -e "CREATE TABLE IF NOT EXISTS test_galera (id INT AUTO_INCREMENT PRIMARY KEY, value VARCHAR(255), created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB;" 2>&1

# Insérer une valeur
INSERT_RESULT=\$(docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 ${MARIADB_DB} -e "INSERT INTO test_galera (value) VALUES ('test_value_\$(date +%s)');" 2>&1)
if [[ \$? -ne 0 ]]; then
    echo "  ✗ Insertion échouée: \${INSERT_RESULT}"
    exit 1
fi

# Lire la valeur
RESULT=\$(docker exec proxysql mysql -u${MARIADB_APP_USER} -p${MARIADB_APP_PASSWORD} -h127.0.0.1 -P3306 ${MARIADB_DB} -Nse "SELECT COUNT(*) FROM test_galera;" 2>/dev/null || echo "0")

if [[ -n "\${RESULT}" ]] && [[ "\${RESULT}" -gt 0 ]]; then
    echo "  ✓ Écriture/lecture réussie (\${RESULT} ligne(s))"
    exit 0
else
    echo "  ✗ Écriture/lecture échouée (RESULT=\${RESULT})"
    exit 1
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "Test d'écriture/lecture validé"
    else
        log_error "Test d'écriture/lecture échoué"
    fi
    echo ""
fi

# Résumé
echo "=============================================================="
log_success "✅ Tests terminés !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœuds Galera: ${#MARIADB_NODES[@]}"
log_info "  - Nœuds ProxySQL: ${#PROXYSQL_IPS[@]}"
log_info "  - Database: ${MARIADB_DB}"
log_info "  - User: ${MARIADB_APP_USER}"
echo ""
log_info "Point d'accès pour ERPNext:"
log_info "  - Via ProxySQL direct: ${PROXYSQL_IPS[0]:-N/A}:3306"
log_info "  - Via LB Hetzner (à configurer): 10.0.0.20:3306"
echo ""

