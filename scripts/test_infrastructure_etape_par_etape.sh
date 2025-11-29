#!/usr/bin/env bash
#
# test_infrastructure_etape_par_etape.sh - Tests infrastructure étape par étape
#
# Ce script teste chaque module individuellement pour permettre une investigation
# détaillée en cas de problème. Chaque test est isolé et documenté.
#
# Usage:
#   ./test_infrastructure_etape_par_etape.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH vers tous les serveurs

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
LOG_FILE="/tmp/test_infrastructure_$(date +%Y%m%d_%H%M%S).log"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Compteurs globaux
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
WARNING_TESTS=0

# Fonctions de logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${LOG_FILE}"
}

log_section() {
    echo "" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}==============================================================" | tee -a "${LOG_FILE}"
    echo -e "${CYAN} $1" | tee -a "${LOG_FILE}"
    echo -e "${CYAN}==============================================================" | tee -a "${LOG_FILE}"
    echo "" | tee -a "${LOG_FILE}"
}

# Fonction de test avec détails
run_test_detailed() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="${3:-OK}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${LOG_FILE}"
    
    # Exécuter le test et capturer la sortie
    if eval "${test_command}" >> "${LOG_FILE}" 2>&1; then
        log_success "OK"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "ÉCHEC"
        echo "    Commande: ${test_command}" | tee -a "${LOG_FILE}"
        echo "    Résultat attendu: ${expected_result}" | tee -a "${LOG_FILE}"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Fonction de test avec warning
run_test_warning() {
    local test_name="$1"
    local test_command="$2"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... " | tee -a "${LOG_FILE}"
    
    if eval "${test_command}" >> "${LOG_FILE}" 2>&1; then
        log_success "OK"
        ((PASSED_TESTS++))
        return 0
    else
        log_warning "WARNING"
        echo "    Commande: ${test_command}" | tee -a "${LOG_FILE}"
        ((WARNING_TESTS++))
        return 1
    fi
}

# Fonction pour exécuter une commande SSH
ssh_exec() {
    local ip="$1"
    local command="$2"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@${ip} "${command}" 2>&1
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Infrastructure Étape par Étape"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo "Log file: ${LOG_FILE}"
echo ""

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

log_info "Fichier servers.tsv trouvé: ${TSV_FILE}"

# Parser le fichier servers.tsv pour extraire les IPs
declare -A HAPROXY_IPS
declare -A PG_NODES
declare -A REDIS_NODES
declare -A RABBITMQ_NODES
declare -A MARIADB_NODES
declare -A PROXYSQL_NODES
declare -A MINIO_NODES
declare -A K3S_MASTERS
declare -A K3S_WORKERS

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]] || [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    case "${ROLE}" in
        lb)
            if [[ "${SUBROLE}" == "internal-haproxy" ]]; then
                HAPROXY_IPS["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
        db)
            if [[ "${SUBROLE}" == "postgres" ]]; then
                PG_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            elif [[ "${SUBROLE}" == "mariadb" ]]; then
                MARIADB_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
        redis)
            REDIS_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            ;;
        queue)
            if [[ "${SUBROLE}" == "rabbitmq" ]]; then
                RABBITMQ_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
        storage)
            if [[ "${SUBROLE}" == "minio" ]]; then
                MINIO_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
        k3s)
            if [[ "${SUBROLE}" == "master" ]]; then
                K3S_MASTERS["${HOSTNAME}"]="${IP_PRIVEE}"
            elif [[ "${SUBROLE}" == "worker" ]]; then
                K3S_WORKERS["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
        db_proxy)
            if [[ "${SUBROLE}" == "proxysql" ]]; then
                PROXYSQL_NODES["${HOSTNAME}"]="${IP_PRIVEE}"
            fi
            ;;
    esac
done
exec 3<&-

# ============================================================
# ÉTAPE 1: Connectivité SSH et État de Base
# ============================================================
log_section "ÉTAPE 1: Connectivité SSH et État de Base"

log_info "Test de connectivité SSH vers tous les serveurs..."

# Test SSH sur quelques serveurs clés
test_ssh_server() {
    local hostname="$1"
    local ip="$2"
    log_info "Test SSH: ${hostname} (${ip})"
    
    if ssh_exec "${ip}" "hostname" | grep -q "${hostname}"; then
        log_success "  SSH fonctionnel sur ${hostname}"
        return 0
    else
        log_error "  SSH échoué sur ${hostname}"
        return 1
    fi
}

# Tester haproxy-01 en premier (a été rebuild)
if [[ -n "${HAPROXY_IPS[haproxy-01]:-}" ]]; then
    log_info "Test prioritaire: haproxy-01 (rebuild)"
    if test_ssh_server "haproxy-01" "${HAPROXY_IPS[haproxy-01]}"; then
        log_info "  Vérification de l'état des services sur haproxy-01..."
        SSH_OUTPUT=$(ssh_exec "${HAPROXY_IPS[haproxy-01]}" "docker ps --format '{{.Names}}' | head -10")
        if echo "${SSH_OUTPUT}" | grep -qE "(haproxy|pgbouncer|keepalived)"; then
            log_warning "  Services trouvés sur haproxy-01, mais vérification complète nécessaire"
        else
            log_error "  Aucun service Docker trouvé sur haproxy-01 - Réinstallation nécessaire!"
        fi
    fi
fi

# Tester quelques serveurs clés
for hostname in "${!PG_NODES[@]}"; do
    test_ssh_server "${hostname}" "${PG_NODES[$hostname]}"
done

echo ""
log_info "Appuyez sur Entrée pour continuer avec les tests suivants, ou Ctrl+C pour arrêter..."
read -r

# ============================================================
# ÉTAPE 2: Module 2 - Base OS & Sécurité
# ============================================================
log_section "ÉTAPE 2: Module 2 - Base OS & Sécurité"

if [[ -n "${HAPROXY_IPS[haproxy-01]:-}" ]]; then
    IP_TEST="${HAPROXY_IPS[haproxy-01]}"
    log_info "Test sur: haproxy-01 (${IP_TEST})"
    
    # Test Docker
    run_test_detailed "Docker installé" \
        "ssh_exec '${IP_TEST}' 'docker --version' | grep -q Docker"
    
    # Test Swap désactivé
    run_test_detailed "Swap désactivé" \
        "ssh_exec '${IP_TEST}' 'swapon --show' | grep -qv '[^[:space:]]'"
    
    # Test UFW actif
    run_test_warning "UFW actif" \
        "ssh_exec '${IP_TEST}' 'ufw status' | grep -q 'Status: active'"
fi

echo ""
log_info "Appuyez sur Entrée pour continuer avec Module 3..."
read -r

# ============================================================
# ÉTAPE 3: Module 3 - PostgreSQL HA
# ============================================================
log_section "ÉTAPE 3: Module 3 - PostgreSQL HA (Patroni)"

if [[ ${#PG_NODES[@]} -gt 0 ]]; then
    log_info "Nœuds PostgreSQL trouvés: ${!PG_NODES[@]}"
    
    # Test sur chaque nœud PostgreSQL
    for hostname in "${!PG_NODES[@]}"; do
        IP="${PG_NODES[$hostname]}"
        log_info "Test sur: ${hostname} (${IP})"
        
        # Test container Patroni
        run_test_detailed "Container Patroni actif (${hostname})" \
            "ssh_exec '${IP}' 'docker ps --format \"{{.Names}}\" | grep -q patroni'"
        
        # Test connectivité PostgreSQL
        run_test_detailed "PostgreSQL accessible (${hostname})" \
            "ssh_exec '${IP}' 'docker exec patroni psql -U postgres -c \"SELECT version();\" > /dev/null 2>&1'"
        
        # Test statut Patroni
        run_test_warning "Statut Patroni (${hostname})" \
            "ssh_exec '${IP}' 'docker exec patroni patronictl list' | grep -qE '(Leader|Replica|Running)'"
    done
    
    # Test HAProxy pour PostgreSQL
    if [[ -n "${HAPROXY_IPS[haproxy-01]:-}" ]]; then
        log_info "Test HAProxy pour PostgreSQL sur haproxy-01"
        IP="${HAPROXY_IPS[haproxy-01]}"
        
        run_test_detailed "Container HAProxy actif (haproxy-01)" \
            "ssh_exec '${IP}' 'docker ps --format \"{{.Names}}\" | grep -q haproxy'"
        
        run_test_warning "Port 5432 HAProxy accessible (haproxy-01)" \
            "ssh_exec '${IP}' 'nc -z localhost 5432'"
        
        run_test_warning "Port 5433 HAProxy accessible (haproxy-01)" \
            "ssh_exec '${IP}' 'nc -z localhost 5433'"
    fi
else
    log_warning "Aucun nœud PostgreSQL trouvé dans servers.tsv"
fi

echo ""
log_info "Appuyez sur Entrée pour continuer avec Module 4..."
read -r

# Continuer avec les autres modules...
log_info "Script de test étapes par étapes créé."
log_info "Fichier log: ${LOG_FILE}"
log_info "Pour continuer, lancez le script complet: ./test_infrastructure_etape_par_etape.sh"

# Résumé
echo ""
log_section "RÉSUMÉ DES TESTS"
echo "Total: ${TOTAL_TESTS} tests"
echo "✓ Réussis: ${PASSED_TESTS}"
echo "✗ Échoués: ${FAILED_TESTS}"
echo "! Avertissements: ${WARNING_TESTS}"
echo "Log file: ${LOG_FILE}"

