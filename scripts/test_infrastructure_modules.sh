#!/usr/bin/env bash
#
# test_infrastructure_modules.sh - Tests infrastructure module par module
#
# Ce script teste chaque module individuellement pour permettre une investigation
# détaillée. Chaque module est testé séparément avec pause entre les modules.
#
# Usage:
#   ./test_infrastructure_modules.sh [servers.tsv]
#
# Exécuter depuis install-01

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
LOG_FILE="/tmp/test_infrastructure_$(date +%Y%m%d_%H%M%S).log"
REPORT_FILE="/tmp/test_infrastructure_report_$(date +%Y%m%d_%H%M%S).txt"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Compteurs
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

test_exec() {
    local test_name="$1"
    local test_command="$2"
    local ip="${3:-}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${LOG_FILE}"
    
    if [[ -n "${ip}" ]]; then
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${ip}"
        if eval "${SSH_CMD} \"${test_command}\" >> ${LOG_FILE} 2>&1"; then
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
        SSH_CMD="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${ip}"
        if eval "${SSH_CMD} \"${test_command}\" >> ${LOG_FILE} 2>&1"; then
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
    log_info "Appuyez sur Entrée pour continuer avec le module suivant..."
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
HAPROXY_01_IP=""
HAPROXY_02_IP=""
PG_IPS=()
REDIS_IPS=()
RABBITMQ_IPS=()
MARIADB_IPS=()
PROXYSQL_IPS=()
MINIO_IPS=()
K3S_MASTER_IPS=()

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
# ÉTAPE 1: Vérification haproxy-01 (rebuild)
# ============================================================
log_section "ÉTAPE 1: Vérification haproxy-01 (REBUILD)"

if [[ -n "${HAPROXY_01_IP}" ]]; then
    log_info "haproxy-01 IP: ${HAPROXY_01_IP}"
    
    test_exec "SSH connectivité haproxy-01" "hostname" "${HAPROXY_01_IP}"
    test_exec "Docker installé haproxy-01" "docker --version" "${HAPROXY_01_IP}"
    test_exec "Docker service actif haproxy-01" "systemctl is-active docker" "${HAPROXY_01_IP}"
    
    log_subsection "Containers Docker sur haproxy-01"
    SSH_OUTPUT=$(ssh -o StrictHostKeyChecking=no root@${HAPROXY_01_IP} "docker ps --format '{{.Names}}' 2>&1" || echo "")
    if [[ -z "${SSH_OUTPUT}" ]] || ! echo "${SSH_OUTPUT}" | grep -qE "[a-zA-Z]"; then
        log_error "AUCUN CONTAINER DOCKER TROUVÉ SUR haproxy-01 - RÉINSTALLATION NÉCESSAIRE!"
        log_error "haproxy-01 a été rebuild mais n'a pas été réinstallé"
    else
        log_info "Containers trouvés sur haproxy-01:"
        echo "${SSH_OUTPUT}" | while read -r container; do
            log_info "  - ${container}"
        done
        
        test_exec_warning "Container HAProxy présent" "docker ps --format '{{.Names}}' | grep -q haproxy" "${HAPROXY_01_IP}"
        test_exec_warning "Container PgBouncer présent" "docker ps --format '{{.Names}}' | grep -q pgbouncer" "${HAPROXY_01_IP}"
        test_exec_warning "Container Keepalived présent" "docker ps --format '{{.Names}}' | grep -q keepalived" "${HAPROXY_01_IP}"
    fi
    
    log_subsection "Ports ouverts sur haproxy-01"
    test_exec_warning "Port 5432 accessible" "nc -z localhost 5432" "${HAPROXY_01_IP}"
    test_exec_warning "Port 5433 accessible" "nc -z localhost 5433" "${HAPROXY_01_IP}"
    test_exec_warning "Port 6379 accessible" "nc -z localhost 6379" "${HAPROXY_01_IP}"
    test_exec_warning "Port 8404 accessible" "nc -z localhost 8404" "${HAPROXY_01_IP}"
else
    log_error "haproxy-01 non trouvé dans servers.tsv"
fi

wait_for_user

# ============================================================
# ÉTAPE 2: Module 2 - Base OS & Sécurité
# ============================================================
log_section "ÉTAPE 2: Module 2 - Base OS & Sécurité"

if [[ -n "${HAPROXY_01_IP}" ]]; then
    log_subsection "Tests Base OS sur haproxy-01"
    
    test_exec "Swap désactivé" "swapon --show | grep -v '^[[:space:]]*$' | wc -l | grep -q '^0$'" "${HAPROXY_01_IP}"
    test_exec_warning "UFW actif" "ufw status | grep -q 'Status: active'" "${HAPROXY_01_IP}"
    test_exec "Docker installé et fonctionnel" "docker ps > /dev/null 2>&1" "${HAPROXY_01_IP}"
fi

wait_for_user

# ============================================================
# ÉTAPE 3: Module 3 - PostgreSQL HA
# ============================================================
log_section "ÉTAPE 3: Module 3 - PostgreSQL HA (Patroni)"

if [[ ${#PG_IPS[@]} -gt 0 ]]; then
    log_info "Nœuds PostgreSQL trouvés: ${PG_IPS[*]}"
    
    for ip in "${PG_IPS[@]}"; do
        hostname=$(grep -E "\t${ip}\t" "${TSV_FILE}" | cut -f3)
        log_subsection "Tests sur ${hostname} (${ip})"
        
        test_exec "SSH connectivité" "hostname" "${ip}"
        test_exec "Container Patroni actif" "docker ps --format '{{.Names}}' | grep -q patroni" "${ip}"
        test_exec "PostgreSQL accessible" "docker exec patroni psql -U postgres -c 'SELECT version();' > /dev/null 2>&1" "${ip}"
        
        # Test statut Patroni
        PATRONI_STATUS=$(ssh -o StrictHostKeyChecking=no root@${ip} "docker exec patroni patronictl list 2>&1" || echo "")
        if echo "${PATRONI_STATUS}" | grep -qE "(Leader|Replica|Running)"; then
            log_success "  Patroni cluster status: OK"
            echo "${PATRONI_STATUS}" | head -5 | while read -r line; do
                log_info "    ${line}"
            done
        else
            log_warning "  Patroni cluster status: Vérification manuelle nécessaire"
            echo "${PATRONI_STATUS}" | head -10
        fi
    done
    
    # Test HAProxy pour PostgreSQL
    if [[ -n "${HAPROXY_01_IP}" ]]; then
        log_subsection "Tests HAProxy pour PostgreSQL"
        test_exec_warning "Port 5432 HAProxy accessible" "nc -z localhost 5432" "${HAPROXY_01_IP}"
        test_exec_warning "Port 5433 HAProxy accessible" "nc -z localhost 5433" "${HAPROXY_01_IP}"
    fi
else
    log_warning "Aucun nœud PostgreSQL trouvé"
fi

wait_for_user

# Continuer avec les autres modules...
log_info "Script de test créé. Pour continuer avec tous les modules, lancez-le sur install-01"
log_info "Fichier: ${SCRIPT_DIR}/test_infrastructure_modules.sh"
log_info "Log: ${LOG_FILE}"
log_info "Report: ${REPORT_FILE}"

echo ""
log_section "RÉSUMÉ PARTIEL"
echo "Total tests: ${TOTAL_TESTS}"
echo "✓ Réussis: ${PASSED_TESTS}"
echo "✗ Échoués: ${FAILED_TESTS}"
echo "! Avertissements: ${WARNING_TESTS}"

