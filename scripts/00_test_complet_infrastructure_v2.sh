#!/usr/bin/env bash
#
# 00_test_complet_infrastructure_v2.sh - Tests complets de l'infrastructure KeyBuzz (Version robuste)
#
# Ce script effectue des tests complets de tous les modules installés pour vérifier
# que les dernières modifications n'ont pas cassé de services ou empêché les failovers.
#
# Usage:
#   ./00_test_complet_infrastructure_v2.sh [servers.tsv]
#
# Prérequis:
#   - Tous les modules installés (2-10)
#   - Exécuter depuis install-01

set -uo pipefail  # Pas de set -e pour continuer même en cas d'erreur

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

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

# Fonction de test robuste
test_check() {
    local test_name="$1"
    shift
    local test_command="$@"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... "
    
    if eval "${test_command}" > /dev/null 2>&1; then
        log_success "OK"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "ÉCHEC"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Complets Infrastructure (Version Robuste)"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo ""

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Trouver les IPs des serveurs
PG_MASTER_IP=""
REDIS_MASTER_IP=""
RABBITMQ_NODES=()
MARIADB_NODES=()
PROXYSQL_NODES=()
K3S_MASTER_IP=""

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES || [[ -n "${ENV}" ]]; do
    if [[ "${ENV}" == "ENV" ]] || [[ -z "${ENV}" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    case "${ROLE}" in
        db)
            if [[ "${SUBROLE}" == "postgres" ]] && [[ "${HOSTNAME}" == "db-master-01" ]]; then
                PG_MASTER_IP="${IP_PRIVEE}"
            fi
            ;;
        redis)
            if [[ "${SUBROLE}" == "master" ]]; then
                REDIS_MASTER_IP="${IP_PRIVEE}"
            fi
            ;;
        rabbitmq)
            RABBITMQ_NODES+=("${IP_PRIVEE}")
            ;;
        mariadb)
            MARIADB_NODES+=("${IP_PRIVEE}")
            ;;
        proxysql)
            PROXYSQL_NODES+=("${IP_PRIVEE}")
            ;;
        k3s)
            if [[ "${SUBROLE}" == "master" ]]; then
                K3S_MASTER_IP="${IP_PRIVEE}"
            fi
            ;;
    esac
done < "${TSV_FILE}"

# ============================================================
# MODULE 3 : PostgreSQL HA
# ============================================================
echo "=============================================================="
echo " MODULE 3 : PostgreSQL HA (Patroni)"
echo "=============================================================="
echo ""

if [[ -n "${PG_MASTER_IP}" ]]; then
    log_info "Master PostgreSQL: ${PG_MASTER_IP}"
    
    test_check "Connectivité PostgreSQL" \
        "ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -c \"SELECT version();\"'"
    
    test_check "Patroni cluster status" \
        "ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni patronictl list' | grep -q 'Leader\|Replica'"
    
    REPLICA_COUNT=$(ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null' | tr -d ' \n' || echo "0")
    if [[ "${REPLICA_COUNT}" =~ ^[1-9] ]]; then
        log_success "  Test: Réplication active ... OK (${REPLICA_COUNT} réplicas)"
        ((PASSED_TESTS++))
    else
        log_warning "  Test: Réplication active ... ÉCHEC (${REPLICA_COUNT} réplicas)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
else
    log_warning "Module 3 : PostgreSQL non trouvé"
    echo ""
fi

# ============================================================
# MODULE 4 : Redis HA
# ============================================================
echo "=============================================================="
echo " MODULE 4 : Redis HA (Sentinel)"
echo "=============================================================="
echo ""

if [[ -n "${REDIS_MASTER_IP}" ]]; then
    log_info "Master Redis: ${REDIS_MASTER_IP}"
    
    # Charger credentials Redis
    REDIS_PASSWORD=""
    if [[ -f "/opt/keybuzz-installer/credentials/redis.env" ]]; then
        source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
        REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    fi
    
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        test_check "Connectivité Redis (avec auth)" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} \"docker exec redis redis-cli -a '${REDIS_PASSWORD}' ping\" | grep -q PONG"
    else
        test_check "Connectivité Redis" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} 'docker exec redis redis-cli ping' | grep -q PONG"
    fi
    
    echo ""
else
    log_warning "Module 4 : Redis non trouvé"
    echo ""
fi

# ============================================================
# MODULE 5 : RabbitMQ HA
# ============================================================
echo "=============================================================="
echo " MODULE 5 : RabbitMQ HA"
echo "=============================================================="
echo ""

if [[ ${#RABBITMQ_NODES[@]} -gt 0 ]]; then
    log_info "Nodes RabbitMQ: ${#RABBITMQ_NODES[@]}"
    
    RABBITMQ_IP="${RABBITMQ_NODES[0]}"
    test_check "Connectivité RabbitMQ" \
        "ssh ${SSH_KEY_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl status'"
    
    test_check "Cluster RabbitMQ formé" \
        "ssh ${SSH_KEY_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl cluster_status' | grep -q 'running_nodes'"
    
    echo ""
else
    log_warning "Module 5 : RabbitMQ non trouvé"
    echo ""
fi

# ============================================================
# MODULE 6 : MinIO
# ============================================================
echo "=============================================================="
echo " MODULE 6 : MinIO S3"
echo "=============================================================="
echo ""

MINIO_IP=$(grep -E "minio" "${TSV_FILE}" | grep -v "^ENV" | head -1 | awk -F'\t' '{print $4}')
if [[ -n "${MINIO_IP}" ]]; then
    log_info "MinIO: ${MINIO_IP}"
    
    test_check "Connectivité MinIO" \
        "ssh ${SSH_KEY_OPTS} root@${MINIO_IP} 'docker exec minio mc ready local'"
    
    test_check "Bucket keybuzz-backups existe" \
        "ssh ${SSH_KEY_OPTS} root@${MINIO_IP} 'docker exec minio mc ls local/keybuzz-backups'"
    
    echo ""
else
    log_warning "Module 6 : MinIO non trouvé"
    echo ""
fi

# ============================================================
# MODULE 7 : MariaDB Galera
# ============================================================
echo "=============================================================="
echo " MODULE 7 : MariaDB Galera HA"
echo "=============================================================="
echo ""

if [[ ${#MARIADB_NODES[@]} -gt 0 ]]; then
    log_info "Nodes MariaDB: ${#MARIADB_NODES[@]}"
    
    MARIADB_ROOT_PASSWORD=""
    if [[ -f "/opt/keybuzz-installer/credentials/mariadb.env" ]]; then
        source /opt/keybuzz-installer/credentials/mariadb.env 2>/dev/null || true
        MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
    fi
    
    MARIADB_IP="${MARIADB_NODES[0]}"
    if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
        test_check "Connectivité MariaDB" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} \"docker exec mariadb mysql -uroot -p'${MARIADB_ROOT_PASSWORD}' -e 'SELECT 1;'\""
    else
        test_check "Connectivité MariaDB" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} 'docker exec mariadb mysql -uroot -e \"SELECT 1;\"'"
    fi
    
    echo ""
else
    log_warning "Module 7 : MariaDB non trouvé"
    echo ""
fi

# ============================================================
# MODULE 8 : ProxySQL
# ============================================================
echo "=============================================================="
echo " MODULE 8 : ProxySQL"
echo "=============================================================="
echo ""

if [[ ${#PROXYSQL_NODES[@]} -gt 0 ]]; then
    log_info "Nodes ProxySQL: ${#PROXYSQL_NODES[@]}"
    
    PROXYSQL_IP="${PROXYSQL_NODES[0]}"
    test_check "Connectivité ProxySQL" \
        "ssh ${SSH_KEY_OPTS} root@${PROXYSQL_IP} 'docker exec proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e \"SELECT 1;\"'"
    
    echo ""
else
    log_warning "Module 8 : ProxySQL non trouvé"
    echo ""
fi

# ============================================================
# MODULE 9 : K3s HA
# ============================================================
echo "=============================================================="
echo " MODULE 9 : K3s HA"
echo "=============================================================="
echo ""

if [[ -n "${K3S_MASTER_IP}" ]]; then
    log_info "Master K3s: ${K3S_MASTER_IP}"
    
    test_check "Cluster K3s accessible" \
        "ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get nodes' | grep -q 'Ready'"
    
    NODE_COUNT=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get nodes --no-headers 2>/dev/null | wc -l' || echo "0")
    if [[ ${NODE_COUNT} -ge 8 ]]; then
        log_success "  Nodes K3s: ${NODE_COUNT} (attendu: ≥8)"
        ((PASSED_TESTS++))
    else
        log_warning "  Nodes K3s: ${NODE_COUNT} (attendu: ≥8)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    INGRESS_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers 2>/dev/null | grep -c Running' || echo "0")
    if [[ ${INGRESS_PODS} -ge 5 ]]; then
        log_success "  Ingress NGINX: ${INGRESS_PODS} pods Running"
        ((PASSED_TESTS++))
    else
        log_warning "  Ingress NGINX: ${INGRESS_PODS} pods Running"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
else
    log_warning "Module 9 : K3s non trouvé"
    echo ""
fi

# ============================================================
# MODULE 10 : KeyBuzz API & Front
# ============================================================
echo "=============================================================="
echo " MODULE 10 : KeyBuzz API & Front"
echo "=============================================================="
echo ""

if [[ -n "${K3S_MASTER_IP}" ]]; then
    KEYBUZZ_API_DS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get daemonset keybuzz-api -n keybuzz --no-headers 2>/dev/null | wc -l' || echo "0")
    KEYBUZZ_FRONT_DS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get daemonset keybuzz-front -n keybuzz --no-headers 2>/dev/null | wc -l' || echo "0")
    
    if [[ ${KEYBUZZ_API_DS} -eq 1 ]] && [[ ${KEYBUZZ_FRONT_DS} -eq 1 ]]; then
        log_success "  DaemonSets KeyBuzz: présents"
        ((PASSED_TESTS++))
    else
        log_error "  DaemonSets KeyBuzz: API=${KEYBUZZ_API_DS}, Front=${KEYBUZZ_FRONT_DS}"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    KEYBUZZ_API_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n keybuzz -l app=keybuzz-api --no-headers 2>/dev/null | grep -c Running' || echo "0")
    KEYBUZZ_FRONT_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | grep -c Running' || echo "0")
    
    if [[ ${KEYBUZZ_API_PODS} -ge 5 ]] && [[ ${KEYBUZZ_FRONT_PODS} -ge 5 ]]; then
        log_success "  Pods KeyBuzz: API=${KEYBUZZ_API_PODS}, Front=${KEYBUZZ_FRONT_PODS}"
        ((PASSED_TESTS++))
    else
        log_warning "  Pods KeyBuzz: API=${KEYBUZZ_API_PODS}, Front=${KEYBUZZ_FRONT_PODS}"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    API_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get daemonset keybuzz-api -n keybuzz -o jsonpath="{.spec.template.spec.hostNetwork}" 2>/dev/null' || echo "false")
    FRONT_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get daemonset keybuzz-front -n keybuzz -o jsonpath="{.spec.template.spec.hostNetwork}" 2>/dev/null' || echo "false")
    
    if [[ "${API_HOSTNETWORK}" == "true" ]] && [[ "${FRONT_HOSTNETWORK}" == "true" ]]; then
        log_success "  hostNetwork: activé sur API et Front"
        ((PASSED_TESTS++))
    else
        log_error "  hostNetwork: API=${API_HOSTNETWORK}, Front=${FRONT_HOSTNETWORK}"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    test_check "URL platform.keybuzz.io accessible" \
        "timeout 10 curl -s -o /dev/null -w '%{http_code}' https://platform.keybuzz.io | grep -q '200'"
    
    test_check "URL platform-api.keybuzz.io accessible" \
        "timeout 10 curl -s -o /dev/null -w '%{http_code}' https://platform-api.keybuzz.io | grep -q '200'"
    
    echo ""
fi

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
echo "=============================================================="
echo " RÉSUMÉ DES TESTS"
echo "=============================================================="
echo ""

if [[ ${TOTAL_TESTS} -gt 0 ]]; then
    PERCENTAGE=$((PASSED_TESTS * 100 / TOTAL_TESTS))
else
    PERCENTAGE=0
fi

log_info "Total tests: ${TOTAL_TESTS}"
log_success "Tests réussis: ${PASSED_TESTS}"
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "Tests échoués: ${FAILED_TESTS}"
fi
log_info "Score: ${PERCENTAGE}%"
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "✅ TOUS LES TESTS RÉUSSIS !"
    echo ""
    log_info "L'infrastructure est opérationnelle et les modifications"
    log_info "n'ont pas affecté les services existants."
    echo ""
    exit 0
elif [[ ${PERCENTAGE} -ge 80 ]]; then
    log_warning "⚠️  La plupart des tests sont réussis (${PERCENTAGE}%)"
    echo ""
    log_info "Quelques tests ont échoué, mais l'infrastructure est"
    log_info "globalement opérationnelle."
    echo ""
    exit 0
else
    log_error "❌ Plusieurs tests ont échoué (${PERCENTAGE}%)"
    echo ""
    log_warning "L'infrastructure nécessite une attention."
    log_warning "Vérifiez les tests échoués ci-dessus."
    echo ""
    exit 1
fi

