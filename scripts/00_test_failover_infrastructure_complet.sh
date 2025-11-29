#!/usr/bin/env bash
#
# 00_test_failover_infrastructure_complet.sh - Tests de failover complets de toute l'infrastructure
#
# Ce script teste la solidité et le failover automatique de TOUTE l'infrastructure :
# - PostgreSQL HA (Patroni)
# - Redis HA (Sentinel)
# - RabbitMQ HA (Quorum)
# - MariaDB Galera HA
# - K3s HA (masters, workers, pods)
#
# Usage:
#   ./00_test_failover_infrastructure_complet.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Modules 3-9 installés
#   - Exécuter depuis install-01
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_test() {
    local test_name="$1"
    local test_command="$2"
    
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

echo "=============================================================="
echo " [KeyBuzz] Tests de Failover Complets Infrastructure"
echo "=============================================================="
echo ""
log_warning "Ces tests vont arrêter temporairement des services"
log_warning "L'infrastructure doit continuer à fonctionner malgré les pertes"
echo ""

if [[ "${AUTO_YES}" != "--yes" ]]; then
    read -p "Continuer avec les tests de failover complets ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Tests annulés"
        exit 0
    fi
fi

# Détecter les serveurs
declare -a PG_IPS=()
declare -a REDIS_IPS=()
declare -a RABBITMQ_IPS=()
declare -a MARIADB_IPS=()
declare -a K3S_MASTER_IPS=()
declare -a K3S_WORKER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    case "${ROLE}" in
        postgres|db)
            if [[ "${SUBROLE}" != "proxy" ]]; then
                PG_IPS+=("${IP_PRIVEE}")
            fi
            ;;
        redis)
            REDIS_IPS+=("${IP_PRIVEE}")
            ;;
        rabbitmq|rmq)
            RABBITMQ_IPS+=("${IP_PRIVEE}")
            ;;
        mariadb|maria)
            MARIADB_IPS+=("${IP_PRIVEE}")
            ;;
        k3s)
            if [[ "${SUBROLE}" == "master" ]]; then
                K3S_MASTER_IPS+=("${IP_PRIVEE}")
            elif [[ "${SUBROLE}" == "worker" ]]; then
                K3S_WORKER_IPS+=("${IP_PRIVEE}")
            fi
            ;;
    esac
done
exec 3<&-

log_info "Serveurs détectés :"
log_info "  PostgreSQL: ${#PG_IPS[@]} nœuds"
log_info "  Redis: ${#REDIS_IPS[@]} nœuds"
log_info "  RabbitMQ: ${#RABBITMQ_IPS[@]} nœuds"
log_info "  MariaDB: ${#MARIADB_IPS[@]} nœuds"
log_info "  K3s Masters: ${#K3S_MASTER_IPS[@]} nœuds"
log_info "  K3s Workers: ${#K3S_WORKER_IPS[@]} nœuds"
echo ""

# ============================================================
# TEST 1: Failover PostgreSQL
# ============================================================
if [[ ${#PG_IPS[@]} -ge 2 ]]; then
    echo "=============================================================="
    log_info "TEST 1: Failover PostgreSQL (Patroni)"
    echo "=============================================================="
    
    # Trouver le primary
    PRIMARY_IP=""
    for ip in "${PG_IPS[@]}"; do
        ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("role", "unknown"))' 2>/dev/null || echo "unknown"
EOF
)
        if [[ "${ROLE}" == "primary" ]]; then
            PRIMARY_IP="${ip}"
            break
        fi
    done
    
    if [[ -n "${PRIMARY_IP}" ]]; then
        log_info "Arrêt du primary PostgreSQL sur ${PRIMARY_IP}..."
        ssh ${SSH_OPTS} root@${PRIMARY_IP} "docker stop patroni" || true
        
        log_info "Attente du failover (90 secondes)..."
        sleep 90
        
        # Vérifier qu'un nouveau primary est élu
        NEW_PRIMARY=false
        for ip in "${PG_IPS[@]}"; do
            if [[ "${ip}" != "${PRIMARY_IP}" ]]; then
                ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("role", "unknown"))' 2>/dev/null || echo "unknown"
EOF
)
                if [[ "${ROLE}" == "primary" ]]; then
                    NEW_PRIMARY=true
                    log_info "Nouveau primary détecté sur ${ip}"
                    break
                fi
            fi
        done
        
        run_test "PostgreSQL - Failover automatique" "${NEW_PRIMARY}"
        
        # Redémarrer
        log_info "Redémarrage du nœud PostgreSQL..."
        ssh ${SSH_OPTS} root@${PRIMARY_IP} "docker start patroni" || true
        sleep 30
    fi
    echo ""
fi

# ============================================================
# TEST 2: Failover Redis (si fonctionnel)
# ============================================================
if [[ ${#REDIS_IPS[@]} -ge 2 ]]; then
    echo "=============================================================="
    log_info "TEST 2: Failover Redis (Sentinel)"
    echo "=============================================================="
    log_warning "Note: Failover Redis peut nécessiter investigation supplémentaire"
    
    # Trouver le master
    MASTER_IP=""
    for ip in "${REDIS_IPS[@]}"; do
        ROLE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis redis-cli -a \"\${REDIS_PASSWORD}\" -h ${ip} INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n '" 2>/dev/null || echo "")
        if [[ "${ROLE}" == "master" ]]; then
            MASTER_IP="${ip}"
            break
        fi
    done
    
    if [[ -n "${MASTER_IP}" ]]; then
        log_info "Arrêt du master Redis sur ${MASTER_IP}..."
        ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true
        
        log_info "Attente du failover Sentinel (120 secondes)..."
        sleep 120
        
        # Vérifier via Sentinel
        NEW_MASTER_IP=$(ssh ${SSH_OPTS} root@${REDIS_IPS[0]} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis-sentinel redis-cli -h ${REDIS_IPS[0]} -p 26379 SENTINEL get-master-addr-by-name kb-redis-master 2>/dev/null | head -1" 2>/dev/null || echo "")
        
        if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
            ROLE=$(ssh ${SSH_OPTS} root@${NEW_MASTER_IP} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis redis-cli -a \"\${REDIS_PASSWORD}\" -h ${NEW_MASTER_IP} INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n '" 2>/dev/null || echo "")
            if [[ "${ROLE}" == "master" ]]; then
                run_test "Redis - Failover automatique (Sentinel)" "true"
            else
                run_test "Redis - Failover automatique (Sentinel)" "false"
            fi
        else
            run_test "Redis - Failover automatique (Sentinel)" "false"
        fi
        
        # Redémarrer
        log_info "Redémarrage du nœud Redis..."
        ssh ${SSH_OPTS} root@${MASTER_IP} "docker start redis" || true
        sleep 30
    fi
    echo ""
fi

# ============================================================
# TEST 3: Failover RabbitMQ (Quorum)
# ============================================================
if [[ ${#RABBITMQ_IPS[@]} -ge 2 ]]; then
    echo "=============================================================="
    log_info "TEST 3: Failover RabbitMQ (Quorum)"
    echo "=============================================================="
    
    # Arrêter un nœud RabbitMQ
    TEST_RABBITMQ_IP="${RABBITMQ_IPS[0]}"
    log_info "Arrêt du nœud RabbitMQ sur ${TEST_RABBITMQ_IP}..."
    ssh ${SSH_OPTS} root@${TEST_RABBITMQ_IP} "docker stop rabbitmq" || true
    
    log_info "Attente de la stabilisation (30 secondes)..."
    sleep 30
    
    # Vérifier que le cluster fonctionne toujours
    CLUSTER_SIZE=0
    for ip in "${RABBITMQ_IPS[@]}"; do
        if [[ "${ip}" != "${TEST_RABBITMQ_IP}" ]]; then
            SIZE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/rabbitmq.env 2>/dev/null && docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -oE 'running_nodes.*' | grep -oE 'rabbit@[^,}]+' | wc -l" || echo "0")
            if [[ ${SIZE} -gt ${CLUSTER_SIZE} ]]; then
                CLUSTER_SIZE=${SIZE}
            fi
        fi
    done
    
    run_test "RabbitMQ - Cluster opérationnel après perte nœud" "[[ ${CLUSTER_SIZE} -ge 2 ]]"
    
    # Redémarrer
    log_info "Redémarrage du nœud RabbitMQ..."
    ssh ${SSH_OPTS} root@${TEST_RABBITMQ_IP} "docker start rabbitmq" || true
    sleep 30
    echo ""
fi

# ============================================================
# TEST 4: Failover MariaDB Galera
# ============================================================
if [[ ${#MARIADB_IPS[@]} -ge 2 ]]; then
    echo "=============================================================="
    log_info "TEST 4: Failover MariaDB Galera"
    echo "=============================================================="
    
    # Arrêter un nœud MariaDB
    TEST_MARIA_IP="${MARIADB_IPS[0]}"
    log_info "Arrêt du nœud MariaDB sur ${TEST_MARIA_IP}..."
    ssh ${SSH_OPTS} root@${TEST_MARIA_IP} "docker stop mariadb" || true
    
    log_info "Attente de la stabilisation (30 secondes)..."
    sleep 30
    
    # Vérifier que le cluster fonctionne toujours
    CLUSTER_SIZE=0
    for ip in "${MARIADB_IPS[@]}"; do
        if [[ "${ip}" != "${TEST_MARIA_IP}" ]]; then
            SIZE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/mariadb.env 2>/dev/null && docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e \"SHOW STATUS LIKE 'wsrep_cluster_size';\" 2>/dev/null | grep -o '[0-9]' | head -1" || echo "0")
            if [[ ${SIZE} -gt ${CLUSTER_SIZE} ]]; then
                CLUSTER_SIZE=${SIZE}
            fi
        fi
    done
    
    run_test "MariaDB - Cluster opérationnel après perte nœud" "[[ ${CLUSTER_SIZE} -ge 2 ]]"
    
    # Redémarrer
    log_info "Redémarrage du nœud MariaDB..."
    ssh ${SSH_OPTS} root@${TEST_MARIA_IP} "docker start mariadb" || true
    sleep 30
    echo ""
fi

# ============================================================
# TEST 5: Failover K3s (si Module 9 installé)
# ============================================================
if [[ ${#K3S_MASTER_IPS[@]} -ge 1 ]]; then
    echo "=============================================================="
    log_info "TEST 5: Failover K3s (Module 9)"
    echo "=============================================================="
    
    MASTER_IP="${K3S_MASTER_IPS[0]}"
    
    # Test failover master (si au moins 3 masters)
    if [[ ${#K3S_MASTER_IPS[@]} -ge 3 ]]; then
        TEST_MASTER_IP="${K3S_MASTER_IPS[1]}"
        log_info "Arrêt du master K3s sur ${TEST_MASTER_IP}..."
        ssh ${SSH_OPTS} root@${TEST_MASTER_IP} "systemctl stop k3s" || true
        
        log_info "Attente de la stabilisation (30 secondes)..."
        sleep 30
        
        # Vérifier que le cluster fonctionne
        ACTIVE_MASTERS=$(ssh ${SSH_OPTS} root@${MASTER_IP} "kubectl get nodes -l node-role.kubernetes.io/master=true --no-headers 2>/dev/null | grep Ready | wc -l || kubectl get nodes -l node-role.kubernetes.io/control-plane=true --no-headers 2>/dev/null | grep Ready | wc -l || echo \"0\"")
        
        run_test "K3s - Cluster opérationnel après perte master" "[[ ${ACTIVE_MASTERS} -ge 2 ]]"
        
        run_test "K3s - API Server accessible" \
            "ssh ${SSH_OPTS} root@${MASTER_IP} 'kubectl get nodes >/dev/null 2>&1'"
        
        # Redémarrer
        log_info "Redémarrage du master K3s..."
        ssh ${SSH_OPTS} root@${TEST_MASTER_IP} "systemctl start k3s" || true
        sleep 30
    fi
    
    # Test failover worker (si au moins 1 worker)
    if [[ ${#K3S_WORKER_IPS[@]} -ge 1 ]]; then
        TEST_WORKER_IP="${K3S_WORKER_IPS[0]}"
        log_info "Arrêt du worker K3s sur ${TEST_WORKER_IP}..."
        ssh ${SSH_OPTS} root@${TEST_WORKER_IP} "systemctl stop k3s-agent" || true
        
        log_info "Attente de la détection (20 secondes)..."
        sleep 20
        
        # Vérifier que le cluster fonctionne
        ACTIVE_WORKERS=$(ssh ${SSH_OPTS} root@${MASTER_IP} "kubectl get nodes --no-headers | grep -v master | grep -v control-plane | grep Ready | wc -l" || echo "0")
        
        run_test "K3s - Cluster opérationnel après perte worker" "[[ ${ACTIVE_WORKERS} -ge $(( ${#K3S_WORKER_IPS[@]} - 1 )) ]]"
        
        # Redémarrer
        log_info "Redémarrage du worker K3s..."
        ssh ${SSH_OPTS} root@${TEST_WORKER_IP} "systemctl start k3s-agent" || true
        sleep 30
    fi
    echo ""
fi

# ============================================================
# TEST 6: Connectivité Services (après tous les failovers)
# ============================================================
echo "=============================================================="
log_info "TEST 6: Connectivité Services (après failovers)"
echo "=============================================================="

run_test "PostgreSQL accessible" \
    "ssh ${SSH_OPTS} root@10.0.0.10 'timeout 3 nc -z 10.0.0.10 5432'"

run_test "Redis accessible" \
    "ssh ${SSH_OPTS} root@10.0.0.10 'timeout 3 nc -z 10.0.0.10 6379'"

run_test "RabbitMQ accessible" \
    "ssh ${SSH_OPTS} root@10.0.0.10 'timeout 3 nc -z 10.0.0.10 5672'"

run_test "MinIO accessible" \
    "ssh ${SSH_OPTS} root@10.0.0.134 'timeout 3 nc -z 10.0.0.134 9000'"

run_test "MariaDB accessible" \
    "ssh ${SSH_OPTS} root@10.0.0.20 'timeout 3 nc -z 10.0.0.20 3306'"

if [[ ${#K3S_MASTER_IPS[@]} -ge 1 ]]; then
    run_test "K3s API Server accessible" \
        "ssh ${SSH_OPTS} root@${K3S_MASTER_IPS[0]} 'kubectl get nodes >/dev/null 2>&1'"
fi

echo ""

# Résumé final
echo "=============================================================="
log_info "RÉSUMÉ DES TESTS DE FAILOVER"
echo "=============================================================="
log_info "Total de tests : ${TOTAL_TESTS}"
log_success "Tests réussis : ${PASSED_TESTS}"
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "Tests échoués : ${FAILED_TESTS}"
else
    log_success "Tests échoués : ${FAILED_TESTS}"
fi
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "✅ Tous les tests de failover sont passés avec succès !"
    log_info "L'infrastructure est robuste et résiliente"
    exit 0
else
    log_error "❌ Certains tests de failover ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
    exit 1
fi

