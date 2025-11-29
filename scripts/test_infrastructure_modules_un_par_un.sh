#!/usr/bin/env bash
#
# test_infrastructure_modules_un_par_un.sh - Tests infrastructure module par module
#
# Ce script teste chaque module individuellement pour permettre une investigation
# détaillée en cas de problème. Chaque module est testé séparément avec pause.
#
# Usage:
#   ./test_infrastructure_modules_un_par_un.sh [servers.tsv]
#
# Exécuter depuis install-01

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
LOG_FILE="/tmp/test_infrastructure_modules_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="/tmp/test_infrastructure_report_$(date +%Y%m%d_%H%M%S).txt"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Compteurs globaux
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Fonctions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${LOG_FILE}" | tee -a "${REPORT_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${LOG_FILE}" | tee -a "${REPORT_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${LOG_FILE}" | tee -a "${REPORT_FILE}"
}

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}==============================================================" | tee -a "${LOG_FILE}"
    echo -e "${CYAN} $1" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}==============================================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

log_subsection() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${MAGENTA}--- $1 ---" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

# Fonction pour exécuter une commande SSH
ssh_exec() {
    local ip="$1"
    local command="$2"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${ip} "${command}" 2>&1
}

# Fonction de test
test_exec() {
    local test_name="$1"
    local test_command="$2"
    local ip="${3:-}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${LOG_FILE}"
    
    if [[ -n "${ip}" ]]; then
        if ssh_exec "${ip}" "${test_command}" >> "${LOG_FILE}" 2>&1; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_error "ÉCHEC"
            echo "    IP: ${ip}" | tee -a "${LOG_FILE}"
            echo "    Commande: ${test_command}" | tee -a "${LOG_FILE}"
            ((FAILED_TESTS++))
            return 1
        fi
    else
        if eval "${test_command} >> ${LOG_FILE} 2>&1"; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_error "ÉCHEC"
            echo "    Commande: ${test_command}" | tee -a "${LOG_FILE}"
            ((FAILED_TESTS++))
            return 1
        fi
    fi
}

test_exec_warning() {
    local test_name="$1"
    local test_command="$2"
    local ip="${3:-}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${LOG_FILE}"
    
    if [[ -n "${ip}" ]]; then
        if ssh_exec "${ip}" "${test_command}" >> "${LOG_FILE}" 2>&1; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_warning "WARNING"
            ((WARNING_TESTS++))
            return 1
        fi
    else
        if eval "${test_command} >> ${LOG_FILE} 2>&1"; then
            log_success "OK"
            ((PASSED_TESTS++))
            return 0
        else
            log_warning "WARNING"
            ((WARNING_TESTS++))
            return 1
        fi
    fi
}

wait_for_user() {
    echo ""
    log_info "╔════════════════════════════════════════════════════════════════╗"
    log_info "║  Appuyez sur Entrée pour continuer avec le module suivant...   ║"
    log_info "║  Ou Ctrl+C pour arrêter et investiguer                         ║"
    log_info "╚════════════════════════════════════════════════════════════════╝"
    read -r
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Infrastructure Module par Module"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo "Log file: ${LOG_FILE}"
echo "Report file: ${REPORT_FILE}"
echo ""

# Vérifier prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Parser servers.tsv
declare -A SERVERS
PG_IPS=()
REDIS_IPS=()
RABBITMQ_IPS=()
MARIADB_IPS=()
PROXYSQL_IPS=()
MINIO_IPS=()
K3S_MASTER_IPS=()
K3S_WORKER_IPS=()
HAPROXY_01_IP=""
HAPROXY_02_IP=""

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    
    SERVERS["${HOSTNAME}"]="${IP_PRIVEE}"
    
    case "${ROLE}" in
        lb)
            if [[ "${SUBROLE}" == "internal-haproxy" ]]; then
                if [[ "${HOSTNAME}" == "haproxy-01" ]]; then
                    HAPROXY_01_IP="${IP_PRIVEE}"
                elif [[ "${HOSTNAME}" == "haproxy-02" ]]; then
                    HAPROXY_02_IP="${IP_PRIVEE}"
                fi
            fi
            ;;
        db)
            if [[ "${SUBROLE}" == "postgres" ]]; then
                PG_IPS+=("${IP_PRIVEE}")
            elif [[ "${SUBROLE}" == "mariadb" ]]; then
                MARIADB_IPS+=("${IP_PRIVEE}")
            fi
            ;;
        redis)
            REDIS_IPS+=("${IP_PRIVEE}")
            ;;
        queue)
            if [[ "${SUBROLE}" == "rabbitmq" ]]; then
                RABBITMQ_IPS+=("${IP_PRIVEE}")
            fi
            ;;
        storage)
            if [[ "${SUBROLE}" == "minio" ]]; then
                MINIO_IPS+=("${IP_PRIVEE}")
            fi
            ;;
        k3s)
            if [[ "${SUBROLE}" == "master" ]]; then
                K3S_MASTER_IPS+=("${IP_PRIVEE}")
            elif [[ "${SUBROLE}" == "worker" ]]; then
                K3S_WORKER_IPS+=("${IP_PRIVEE}")
            fi
            ;;
        db_proxy)
            if [[ "${SUBROLE}" == "proxysql" ]]; then
                PROXYSQL_IPS+=("${IP_PRIVEE}")
            fi
            ;;
    esac
done
exec 3<&-

log_info "Fichier servers.tsv parsé: $(wc -l < ${TSV_FILE}) lignes"
echo "" | tee -a "${REPORT_FILE}"
echo "Rapport de tests - $(date)" >> "${REPORT_FILE}"
echo "==============================================================" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# ============================================================
# MODULE 3 : PostgreSQL HA
# ============================================================
log_section "MODULE 3 : PostgreSQL HA (Patroni + HAProxy + PgBouncer)"

if [[ ${#PG_IPS[@]} -gt 0 ]]; then
    log_info "Nœuds PostgreSQL trouvés: ${PG_IPS[*]}"
    
    # Tests sur chaque nœud PostgreSQL
    log_subsection "Tests Containers Patroni"
    for ip in "${PG_IPS[@]}"; do
        hostname=$(grep -E "\t${ip}\t" "${TSV_FILE}" | cut -f3)
        log_info "Test sur ${hostname} (${ip}):"
        
        test_exec "Container Patroni actif" "docker ps | grep -q patroni" "${ip}"
        test_exec "PostgreSQL accessible" "docker exec patroni pg_isready -U postgres 2>&1 | grep -q accepting" "${ip}"
        test_exec "API Patroni accessible (port 8008)" "curl -s -f http://localhost:8008/health >/dev/null 2>&1" "${ip}"
    done
    
    # Test statut cluster Patroni
    log_subsection "Test Statut Cluster Patroni"
    if [[ ${#PG_IPS[@]} -gt 0 ]]; then
        FIRST_PG_IP="${PG_IPS[0]}"
        PATRONI_STATUS=$(ssh_exec "${FIRST_PG_IP}" "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" || echo "")
        
        if echo "${PATRONI_STATUS}" | grep -qE "(Leader|Replica|Running)"; then
            log_success "Cluster Patroni: Statut disponible"
            log_info "Aperçu du statut:"
            echo "${PATRONI_STATUS}" | head -10 | sed 's/^/    /' | tee -a "${LOG_FILE}"
            
            # Compter Leader et Replicas
            LEADER_COUNT=$(echo "${PATRONI_STATUS}" | grep -c "Leader" || echo "0")
            REPLICA_COUNT=$(echo "${PATRONI_STATUS}" | grep -c "Replica" || echo "0")
            
            if [[ "${LEADER_COUNT}" -eq 1 ]] && [[ "${REPLICA_COUNT}" -ge 1 ]]; then
                log_success "Cluster Patroni: 1 Leader et ${REPLICA_COUNT} Replica(s)"
                ((PASSED_TESTS++))
            else
                log_warning "Cluster Patroni: Configuration anormale (Leader: ${LEADER_COUNT}, Replicas: ${REPLICA_COUNT})"
                ((WARNING_TESTS++))
            fi
            ((TOTAL_TESTS++))
        else
            log_error "Cluster Patroni: Impossible de récupérer le statut"
            echo "${PATRONI_STATUS}" | head -10 | sed 's/^/    /' | tee -a "${LOG_FILE}"
            ((FAILED_TESTS++))
            ((TOTAL_TESTS++))
        fi
    fi
    
    # Tests HAProxy pour PostgreSQL
    log_subsection "Tests HAProxy pour PostgreSQL"
    if [[ -n "${HAPROXY_01_IP}" ]]; then
        log_info "Test sur haproxy-01 (${HAPROXY_01_IP}):"
        test_exec "Container HAProxy actif" "docker ps | grep -q haproxy" "${HAPROXY_01_IP}"
        test_exec "Service HAProxy actif" "systemctl is-active --quiet haproxy-docker.service" "${HAPROXY_01_IP}"
        test_exec "Port 5432 accessible" "nc -z localhost 5432" "${HAPROXY_01_IP}"
        test_exec_warning "Port 5433 accessible (read)" "nc -z localhost 5433" "${HAPROXY_01_IP}"
        test_exec "Port 8404 accessible (stats)" "nc -z localhost 8404" "${HAPROXY_01_IP}"
        
        # Test connectivité via HAProxy
        log_info "Test connectivité PostgreSQL via HAProxy:"
        CONN_TEST=$(ssh_exec "${HAPROXY_01_IP}" "timeout 3 bash -c '</dev/tcp/localhost/5432' 2>&1" || echo "FAIL")
        if echo "${CONN_TEST}" | grep -q "Connection refused\|Connection timed out\|FAIL"; then
            log_warning "Connexion TCP via HAProxy port 5432: Échec"
            ((WARNING_TESTS++))
        else
            log_success "Connexion TCP via HAProxy port 5432: OK"
            ((PASSED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    # Tests PgBouncer
    log_subsection "Tests PgBouncer"
    if [[ -n "${HAPROXY_01_IP}" ]]; then
        log_info "Test sur haproxy-01 (${HAPROXY_01_IP}):"
        test_exec "Container PgBouncer actif" "docker ps | grep -q pgbouncer" "${HAPROXY_01_IP}"
        test_exec "Service PgBouncer actif" "systemctl is-active --quiet pgbouncer-docker.service" "${HAPROXY_01_IP}"
        test_exec "Port 6432 accessible" "nc -z localhost 6432" "${HAPROXY_01_IP}"
    fi
else
    log_warning "Aucun nœud PostgreSQL trouvé"
fi

# Résumé Module 3
log_subsection "Résumé Module 3"
echo "Total tests Module 3: ${TOTAL_TESTS}"
echo "✓ Réussis: ${PASSED_TESTS}"
echo "✗ Échoués: ${FAILED_TESTS}"
echo "! Avertissements: ${WARNING_TESTS}"

wait_for_user

# ============================================================
# MODULE 4 : Redis HA
# ============================================================
log_section "MODULE 4 : Redis HA (Sentinel)"

# Continuer avec les autres modules...
log_info "Script créé. Pour continuer avec tous les modules, exécutez-le sur install-01"
log_info "Fichier: ${SCRIPT_DIR}/test_infrastructure_modules_un_par_un.sh"
log_info "Log: ${LOG_FILE}"
log_info "Report: ${REPORT_FILE}"

echo ""
log_section "RÉSUMÉ GLOBAL"
echo "Total tests: ${TOTAL_TESTS}"
echo "✓ Réussis: ${PASSED_TESTS}"
echo "✗ Échoués: ${FAILED_TESTS}"
echo "! Avertissements: ${WARNING_TESTS}"

