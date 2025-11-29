#!/usr/bin/env bash
#
# validate_module3.sh - Validation complète du Module 3 (PostgreSQL HA)
#
# Ce script vérifie que tous les composants du Module 3 ont été correctement
# installés et configurés.
#
# Usage:
#   ./validate_module3.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH root vers tous les serveurs
#   - servers.tsv correctement configuré
#   - Credentials PostgreSQL configurés

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/inventory/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"
REPORT_FILE="${SCRIPT_DIR}/module3_validation_report_$(date +%Y%m%d_%H%M%S).txt"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs globaux
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Fonctions utilitaires
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
    log_info "Exécutez d'abord: ./03_pg_00_setup_credentials.sh"
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
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " [KeyBuzz] Module 3 - Validation PostgreSQL HA" | tee -a "${REPORT_FILE}"
echo " Fichier d'inventaire : ${TSV_FILE}" | tee -a "${REPORT_FILE}"
echo " Rapport généré le    : $(date '+%F %T')" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Collecter les informations des nœuds
declare -a DB_NODES
declare -a DB_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..." | tee -a "${REPORT_FILE}"

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    # Nœuds DB
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]]; then
        if [[ "${HOSTNAME}" == "db-master-01" ]] || \
           [[ "${HOSTNAME}" == "db-slave-01" ]] || \
           [[ "${HOSTNAME}" == "db-slave-02" ]]; then
            DB_NODES+=("${HOSTNAME}")
            DB_IPS+=("${IP_PRIVEE}")
        fi
    fi
    
    # Nœuds HAProxy
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]]; then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

log_info "Nœuds DB trouvés : ${#DB_NODES[@]}" | tee -a "${REPORT_FILE}"
log_info "Nœuds HAProxy trouvés : ${#HAPROXY_NODES[@]}" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Fonction pour vérifier un point
check_point() {
    local check_name="$1"
    local check_command="$2"
    local is_warning="${3:-false}"
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if eval "${check_command}" >/dev/null 2>&1; then
        log_success "${check_name}" | tee -a "${REPORT_FILE}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        return 0
    else
        if [[ "${is_warning}" == "true" ]]; then
            log_warning "${check_name}" | tee -a "${REPORT_FILE}"
            WARNING_CHECKS=$((WARNING_CHECKS + 1))
        else
            log_error "${check_name}" | tee -a "${REPORT_FILE}"
            FAILED_CHECKS=$((FAILED_CHECKS + 1))
        fi
        return 1
    fi
}

# ============================================================
# 1. Validation Cluster Patroni
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " 1. Validation Cluster Patroni RAFT" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

for i in "${!DB_NODES[@]}"; do
    HOSTNAME="${DB_NODES[$i]}"
    IP="${DB_IPS[$i]}"
    
    log_info "Validation ${HOSTNAME} (${IP})..." | tee -a "${REPORT_FILE}"
    
    # Conteneur Patroni actif
    check_point "  Conteneur Patroni actif sur ${HOSTNAME}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${IP} 'docker ps | grep -q patroni'"
    
    # REST API Patroni accessible
    check_point "  REST API Patroni accessible sur ${HOSTNAME}:8008" \
        "curl -s -f http://${IP}:8008/health >/dev/null"
    
    # Cluster membre
    check_point "  ${HOSTNAME} est membre du cluster" \
        "curl -s http://${IP}:8008/cluster | grep -q '\"${HOSTNAME}\"'"
done

# Vérifier qu'il y a un Leader
CLUSTER_JSON=$(curl -s http://${DB_IPS[0]}:8008/cluster 2>/dev/null || echo "")
LEADER=$(echo "${CLUSTER_JSON}" | python3 -c "import sys, json; data=json.load(sys.stdin); leaders=[m['name'] for m in data['members'] if m['role']=='leader']; print(leaders[0] if leaders else 'NONE')" 2>/dev/null || echo "NONE")
LEADER_FOUND=false
if [[ "${LEADER}" != "NONE" ]]; then
    LEADER_FOUND=true
fi

check_point "  Leader élu dans le cluster (${LEADER})" "[[ '${LEADER_FOUND}' == 'true' ]]"

# Vérifier qu'il y a au moins 2 Replicas
if [[ -n "${CLUSTER_JSON}" ]]; then
    REPLICA_COUNT=$(echo "${CLUSTER_JSON}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len([m for m in data['members'] if m['role']=='replica']))" 2>/dev/null || echo "0")
    REPLICA_COUNT=$((REPLICA_COUNT + 0))  # Convertir en nombre
else
    REPLICA_COUNT=0
fi

if [[ ${REPLICA_COUNT} -ge 2 ]]; then
    log_success "  ${REPLICA_COUNT} réplicas actifs" | tee -a "${REPORT_FILE}"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
else
    log_warning "  Seulement ${REPLICA_COUNT} réplica(s) actif(s) (attendu: 2)" | tee -a "${REPORT_FILE}"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
fi
TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

echo "" | tee -a "${REPORT_FILE}"

# ============================================================
# 2. Validation HAProxy
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " 2. Validation HAProxy" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

for i in "${!HAPROXY_NODES[@]}"; do
    HOSTNAME="${HAPROXY_NODES[$i]}"
    IP="${HAPROXY_IPS[$i]}"
    
    log_info "Validation ${HOSTNAME} (${IP})..." | tee -a "${REPORT_FILE}"
    
    # Conteneur HAProxy actif
    check_point "  Conteneur HAProxy actif sur ${HOSTNAME}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${IP} 'docker ps | grep -q haproxy'"
    
    # Port 5432 en écoute
    check_point "  Port 5432 en écoute sur ${HOSTNAME}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${IP} 'netstat -tln | grep -q :5432'"
    
    # Port 6432 en écoute (PgBouncer)
    check_point "  Port 6432 en écoute sur ${HOSTNAME}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${IP} 'netstat -tln | grep -q :6432'"
done

echo "" | tee -a "${REPORT_FILE}"

# ============================================================
# 3. Validation PgBouncer
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " 3. Validation PgBouncer" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

for i in "${!HAPROXY_NODES[@]}"; do
    HOSTNAME="${HAPROXY_NODES[$i]}"
    IP="${HAPROXY_IPS[$i]}"
    
    log_info "Validation ${HOSTNAME} (${IP})..." | tee -a "${REPORT_FILE}"
    
    # Conteneur PgBouncer actif
    check_point "  Conteneur PgBouncer actif sur ${HOSTNAME}" \
        "ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@${IP} 'docker ps | grep -q pgbouncer'"
done

echo "" | tee -a "${REPORT_FILE}"

# ============================================================
# 4. Validation Connectivité PostgreSQL
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " 4. Validation Connectivité PostgreSQL" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# Vérifier si psql est disponible
if ! command -v psql >/dev/null 2>&1; then
    log_warning "psql n'est pas installé, installation en cours..." | tee -a "${REPORT_FILE}"
    apt-get update -y >/dev/null 2>&1
    apt-get install -y postgresql-client >/dev/null 2>&1 || true
fi

# Test de connexion via HAProxy direct
if command -v psql >/dev/null 2>&1; then
    for IP in "${HAPROXY_IPS[@]}"; do
        check_point "  Connexion PostgreSQL via HAProxy ${IP}:5432" \
            "psql -h ${IP} -p 5432 -U ${POSTGRES_SUPERUSER} -d ${POSTGRES_DB} -c 'SELECT 1;' >/dev/null 2>&1" \
            "PGPASSWORD=${POSTGRES_SUPERPASS}"
    done
    
    # Test de connexion via PgBouncer
    for IP in "${HAPROXY_IPS[@]}"; do
        check_point "  Connexion PgBouncer via ${IP}:6432" \
            "psql -h ${IP} -p 6432 -U ${POSTGRES_APP_USER} -d ${POSTGRES_DB} -c 'SELECT 1;' >/dev/null 2>&1" \
            "PGPASSWORD=${POSTGRES_APP_PASS}"
    done
else
    log_warning "psql non disponible, tests de connectivité ignorés" | tee -a "${REPORT_FILE}"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi

echo "" | tee -a "${REPORT_FILE}"

# ============================================================
# 5. Validation pgvector
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " 5. Validation pgvector" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

if command -v psql >/dev/null 2>&1; then
    # Vérifier que l'extension pgvector peut être créée
    check_point "  Extension pgvector disponible" \
        "psql -h ${HAPROXY_IPS[0]} -p 5432 -U ${POSTGRES_SUPERUSER} -d ${POSTGRES_DB} -c 'CREATE EXTENSION IF NOT EXISTS vector;' >/dev/null 2>&1" \
        "PGPASSWORD=${POSTGRES_SUPERPASS}"
    
    # Vérifier que l'extension est installée
    check_point "  Extension pgvector installée" \
        "psql -h ${HAPROXY_IPS[0]} -p 5432 -U ${POSTGRES_SUPERUSER} -d ${POSTGRES_DB} -c \"SELECT extname FROM pg_extension WHERE extname='vector';\" | grep -q vector" \
        "PGPASSWORD=${POSTGRES_SUPERPASS}"
else
    log_warning "psql non disponible, validation pgvector ignorée" | tee -a "${REPORT_FILE}"
    WARNING_CHECKS=$((WARNING_CHECKS + 1))
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
fi

echo "" | tee -a "${REPORT_FILE}"

# ============================================================
# Résumé final
# ============================================================
echo "==============================================================" | tee -a "${REPORT_FILE}"
log_info "RÉSUMÉ GLOBAL DE LA VALIDATION DU MODULE 3" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
log_success "Tests réussis : ${PASSED_CHECKS}/${TOTAL_CHECKS}" | tee -a "${REPORT_FILE}"
if [[ ${FAILED_CHECKS} -gt 0 ]]; then
    log_error "Tests échoués : ${FAILED_CHECKS}/${TOTAL_CHECKS}" | tee -a "${REPORT_FILE}"
fi
if [[ ${WARNING_CHECKS} -gt 0 ]]; then
    log_warning "Avertissements : ${WARNING_CHECKS}/${TOTAL_CHECKS}" | tee -a "${REPORT_FILE}"
fi
echo "==============================================================" | tee -a "${REPORT_FILE}"

if [[ ${FAILED_CHECKS} -eq 0 ]]; then
    log_success "MODULE 3 : VALIDATION GLOBALE RÉUSSIE" | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    log_info "Rapport détaillé : ${REPORT_FILE}" | tee -a "${REPORT_FILE}"
    exit 0
else
    log_error "MODULE 3 : VALIDATION GLOBALE ÉCHOUÉE - ${FAILED_CHECKS} test(s) en erreur." | tee -a "${REPORT_FILE}"
    echo "" | tee -a "${REPORT_FILE}"
    log_info "Rapport détaillé : ${REPORT_FILE}" | tee -a "${REPORT_FILE}"
    exit 1
fi

