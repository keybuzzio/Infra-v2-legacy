#!/usr/bin/env bash
#
# 03_pg_06_diagnostics.sh - Diagnostics et tests du cluster PostgreSQL HA
#
# Ce script effectue une série de tests pour valider le bon fonctionnement
# du cluster PostgreSQL HA (Patroni, HAProxy, PgBouncer).
#
# Usage:
#   ./03_pg_06_diagnostics.sh [servers.tsv]
#
# Prérequis:
#   - Cluster Patroni installé
#   - HAProxy installé
#   - PgBouncer installé
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"

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

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Vérifier que psql est installé
if ! command -v psql >/dev/null 2>&1; then
    log_info "Installation de postgresql-client..."
    apt-get update -y
    apt-get install -y postgresql-client
fi

# LB Hetzner IP
LB_IP="10.0.0.10"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 3 - Diagnostics PostgreSQL HA"
echo "=============================================================="
echo ""

# Fonction de test
run_test() {
    local test_name=$1
    local test_command=$2
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    log_info "Test: ${test_name}"
    
    if eval "${test_command}" >/dev/null 2>&1; then
        log_success "${test_name}"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "${test_name}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

# Collecter les informations des nœuds
declare -a DB_NODES
declare -a DB_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]]; then
        DB_NODES+=("${HOSTNAME}")
        DB_IPS+=("${IP_PRIVEE}")
    fi
    
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]]; then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

echo "--------------------------------------------------------------"
echo "1. Tests de Connectivité"
echo "--------------------------------------------------------------"

# Test connectivité DB nodes
for i in "${!DB_NODES[@]}"; do
    run_test "Connectivité SSH vers ${DB_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 root@${DB_IPS[$i]} 'echo OK'"
done

# Test connectivité HAProxy nodes
for i in "${!HAPROXY_NODES[@]}"; do
    run_test "Connectivité SSH vers ${HAPROXY_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 root@${HAPROXY_IPS[$i]} 'echo OK'"
done

echo ""

echo "--------------------------------------------------------------"
echo "2. Tests Patroni Cluster"
echo "--------------------------------------------------------------"

# Test services Patroni
for i in "${!DB_NODES[@]}"; do
    run_test "Service Patroni actif sur ${DB_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${DB_IPS[$i]} 'systemctl is-active --quiet patroni-docker.service'"
    
    run_test "Conteneur Patroni running sur ${DB_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${DB_IPS[$i]} 'docker ps | grep -q patroni'"
    
    run_test "API Patroni accessible sur ${DB_NODES[$i]}" \
        "curl -s -f http://${DB_IPS[$i]}:8008/health >/dev/null"
done

# Test statut cluster
if [[ ${#DB_IPS[@]} -gt 0 ]]; then
    run_test "Statut cluster Patroni" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${DB_IPS[0]} 'docker exec patroni patronictl -c /etc/patroni/patroni.yml list >/dev/null 2>&1'"
fi

echo ""

echo "--------------------------------------------------------------"
echo "3. Tests HAProxy"
echo "--------------------------------------------------------------"

# Test services HAProxy
for i in "${!HAPROXY_NODES[@]}"; do
    run_test "Service HAProxy actif sur ${HAPROXY_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${HAPROXY_IPS[$i]} 'systemctl is-active --quiet haproxy-docker.service'"
    
    run_test "Conteneur HAProxy running sur ${HAPROXY_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${HAPROXY_IPS[$i]} 'docker ps | grep -q haproxy'"
    
    run_test "Port 5432 accessible sur ${HAPROXY_NODES[$i]}" \
        "nc -z -w2 ${HAPROXY_IPS[$i]} 5432"
done

echo ""

echo "--------------------------------------------------------------"
echo "4. Tests PgBouncer"
echo "--------------------------------------------------------------"

# Test services PgBouncer
for i in "${!HAPROXY_NODES[@]}"; do
    run_test "Service PgBouncer actif sur ${HAPROXY_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${HAPROXY_IPS[$i]} 'systemctl is-active --quiet pgbouncer-docker.service'"
    
    run_test "Conteneur PgBouncer running sur ${HAPROXY_NODES[$i]}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes root@${HAPROXY_IPS[$i]} 'docker ps | grep -q pgbouncer'"
    
    run_test "Port 6432 accessible sur ${HAPROXY_NODES[$i]}" \
        "nc -z -w2 ${HAPROXY_IPS[$i]} 6432"
done

echo ""

echo "--------------------------------------------------------------"
echo "5. Tests PostgreSQL"
echo "--------------------------------------------------------------"

# Test connexion directe via HAProxy
CONNECTION_STRING_DIRECT="postgresql://${POSTGRES_SUPERUSER}:${POSTGRES_SUPERPASS}@${LB_IP}:5432/${POSTGRES_DB}"

run_test "Connexion PostgreSQL via HAProxy (${LB_IP}:5432)" \
    "psql '${CONNECTION_STRING_DIRECT}' -c 'SELECT version();'"

run_test "Requête SELECT via HAProxy" \
    "psql '${CONNECTION_STRING_DIRECT}' -c 'SELECT now();'"

# Test connexion via PgBouncer
CONNECTION_STRING_PGBOUNCER="postgresql://${POSTGRES_APP_USER}:${POSTGRES_APP_PASS}@${LB_IP}:6432/${POSTGRES_DB}"

run_test "Connexion PostgreSQL via PgBouncer (${LB_IP}:6432)" \
    "psql '${CONNECTION_STRING_PGBOUNCER}' -c 'SELECT 1;'"

# Test pgvector
run_test "Extension pgvector installée" \
    "psql '${CONNECTION_STRING_DIRECT}' -t -c \"SELECT extname FROM pg_extension WHERE extname='vector';\" | grep -q vector"

echo ""

# Résumé
echo "=============================================================="
echo " [KeyBuzz] Résumé des Diagnostics"
echo "=============================================================="
echo ""
echo "Total tests     : ${TOTAL_TESTS}"
log_success "Tests réussis  : ${PASSED_TESTS}"
log_error "Tests échoués   : ${FAILED_TESTS}"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    echo "=============================================================="
    log_success "✅ TOUS LES TESTS SONT RÉUSSIS !"
    echo "Le cluster PostgreSQL HA est opérationnel."
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_error "⚠️  CERTAINS TESTS ONT ÉCHOUÉ"
    echo "Veuillez vérifier les erreurs ci-dessus."
    echo "=============================================================="
    exit 1
fi


