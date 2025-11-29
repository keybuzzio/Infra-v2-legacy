#!/usr/bin/env bash
#
# 00_test_complet_infrastructure.sh - Tests complets de l'infrastructure KeyBuzz
#
# Ce script effectue des tests complets de tous les modules installés pour vérifier
# que les dernières modifications n'ont pas cassé de services ou empêché les failovers.
#
# Usage:
#   ./00_test_complet_infrastructure.sh [servers.tsv]
#
# Prérequis:
#   - Tous les modules installés (2-10)
#   - Exécuter depuis install-01

set -uo pipefail

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

# Fonction de test
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Complets Infrastructure"
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

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
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
done
exec 3<&-

# ============================================================
# MODULE 3 : PostgreSQL HA
# ============================================================
echo "=============================================================="
echo " MODULE 3 : PostgreSQL HA (Patroni)"
echo "=============================================================="
echo ""

if [[ -n "${PG_MASTER_IP}" ]]; then
    log_info "Master PostgreSQL: ${PG_MASTER_IP}"
    
    # Test 1: Connectivité PostgreSQL
    set +e
    ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -c "SELECT version();" > /dev/null 2>&1'
    if [[ $? -eq 0 ]]; then
        log_success "  Test: Connectivité PostgreSQL ... OK"
        ((PASSED_TESTS++))
    else
        log_error "  Test: Connectivité PostgreSQL ... ÉCHEC"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    set -e
    
    # Test 2: Patroni cluster status
    set +e
    ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni patronictl list' 2>/dev/null | grep -q 'Leader\|Replica'
    if [[ $? -eq 0 ]]; then
        log_success "  Test: Patroni cluster status ... OK"
        ((PASSED_TESTS++))
    else
        log_error "  Test: Patroni cluster status ... ÉCHEC"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    set -e
    
    # Test 3: Réplication
    set +e
    REPLICA_COUNT=$(ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni psql -U postgres -t -c "SELECT count(*) FROM pg_stat_replication;" 2>/dev/null' | tr -d ' ' || echo "0")
    if [[ "${REPLICA_COUNT}" =~ ^[1-9] ]]; then
        log_success "  Test: Réplication active ... OK (${REPLICA_COUNT} réplicas)"
        ((PASSED_TESTS++))
    else
        log_warning "  Test: Réplication active ... ÉCHEC (${REPLICA_COUNT} réplicas)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    set -e
    
    # Test 4: PgBouncer (sur haproxy nodes)
    set +e
    PGBOUNCER_IP=$(grep -E "haproxy" "${TSV_FILE}" | head -1 | awk -F'\t' '{print $4}')
    if [[ -n "${PGBOUNCER_IP}" ]]; then
        ssh ${SSH_KEY_OPTS} root@${PGBOUNCER_IP} 'docker exec pgbouncer psql -h localhost -p 6432 -U postgres -d postgres -c "SELECT 1;" > /dev/null 2>&1'
        if [[ $? -eq 0 ]]; then
            log_success "  Test: PgBouncer connectivité ... OK"
            ((PASSED_TESTS++))
        else
            log_warning "  Test: PgBouncer connectivité ... ÉCHEC"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    set -e
    
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
        source /opt/keybuzz-installer/credentials/redis.env
        REDIS_PASSWORD="${REDIS_PASSWORD:-}"
    fi
    
    # Test 1: Connectivité Redis
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        run_test "Connectivité Redis (avec auth)" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} \"docker exec redis redis-cli -a '${REDIS_PASSWORD}' ping\" | grep -q PONG"
    else
        run_test "Connectivité Redis" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} 'docker exec redis redis-cli ping' | grep -q PONG"
    fi
    
    # Test 2: Réplication Redis
    if [[ -n "${REDIS_PASSWORD}" ]]; then
        run_test "Réplication Redis active" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} \"docker exec redis redis-cli -a '${REDIS_PASSWORD}' INFO replication\" | grep -q 'connected_slaves:[1-9]'"
    else
        run_test "Réplication Redis active" \
            "ssh ${SSH_KEY_OPTS} root@${REDIS_MASTER_IP} 'docker exec redis redis-cli INFO replication' | grep -q 'connected_slaves:[1-9]'"
    fi
    
    # Test 3: Sentinel
    SENTINEL_IP=$(grep -E "redis" "${TSV_FILE}" | grep -E "sentinel" | head -1 | cut -f4)
    if [[ -z "${SENTINEL_IP}" ]]; then
        # Essayer de trouver un node Redis qui a Sentinel
        SENTINEL_IP=$(grep -E "redis" "${TSV_FILE}" | head -1 | cut -f4)
    fi
    if [[ -n "${SENTINEL_IP}" ]]; then
        if [[ -n "${REDIS_PASSWORD}" ]]; then
            run_test "Sentinel status" \
                "ssh ${SSH_KEY_OPTS} root@${SENTINEL_IP} \"docker exec sentinel redis-cli -a '${REDIS_PASSWORD}' -p 26379 SENTINEL masters\" | grep -q 'mymaster'"
        else
            run_test "Sentinel status" \
                "ssh ${SSH_KEY_OPTS} root@${SENTINEL_IP} 'docker exec sentinel redis-cli -p 26379 SENTINEL masters' | grep -q 'mymaster'"
        fi
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
    
    # Test 1: Connectivité RabbitMQ
    RABBITMQ_IP="${RABBITMQ_NODES[0]}"
    run_test "Connectivité RabbitMQ" \
        "ssh ${SSH_KEY_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl status' > /dev/null 2>&1"
    
    # Test 2: Cluster RabbitMQ
    run_test "Cluster RabbitMQ formé" \
        "ssh ${SSH_KEY_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmqctl cluster_status' | grep -q 'running_nodes'"
    
    # Test 3: Quorum Queues
    run_test "Quorum Queues activés" \
        "ssh ${SSH_KEY_OPTS} root@${RABBITMQ_IP} 'docker exec rabbitmq rabbitmq-plugins list' | grep -q 'quorum_queue'"
    
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
    
    # Test 1: Connectivité MinIO
    run_test "Connectivité MinIO" \
        "ssh ${SSH_KEY_OPTS} root@${MINIO_IP} 'docker exec minio mc ready local' > /dev/null 2>&1"
    
    # Test 2: Bucket keybuzz-backups
    run_test "Bucket keybuzz-backups existe" \
        "ssh ${SSH_KEY_OPTS} root@${MINIO_IP} 'docker exec minio mc ls local/keybuzz-backups' > /dev/null 2>&1"
    
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
    
    # Charger credentials MariaDB
    MARIADB_ROOT_PASSWORD=""
    if [[ -f "/opt/keybuzz-installer/credentials/mariadb.env" ]]; then
        source /opt/keybuzz-installer/credentials/mariadb.env
        MARIADB_ROOT_PASSWORD="${MARIADB_ROOT_PASSWORD:-}"
    fi
    
    # Test 1: Connectivité MariaDB
    MARIADB_IP="${MARIADB_NODES[0]}"
    if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
        run_test "Connectivité MariaDB" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} \"docker exec mariadb mysql -uroot -p'${MARIADB_ROOT_PASSWORD}' -e 'SELECT 1;'\" > /dev/null 2>&1"
    else
        run_test "Connectivité MariaDB" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} 'docker exec mariadb mysql -uroot -e \"SELECT 1;\"' > /dev/null 2>&1"
    fi
    
    # Test 2: Galera cluster status
    if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
        run_test "Galera cluster status" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} \"docker exec mariadb mysql -uroot -p'${MARIADB_ROOT_PASSWORD}' -e 'SHOW STATUS LIKE \\\"wsrep_cluster_size\\\";'\" | grep -q '[1-9]'"
    else
        run_test "Galera cluster status" \
            "ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} 'docker exec mariadb mysql -uroot -e \"SHOW STATUS LIKE \\\"wsrep_cluster_size\\\";\"' | grep -q '[1-9]'"
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
    
    # Test 1: Connectivité ProxySQL
    PROXYSQL_IP="${PROXYSQL_NODES[0]}"
    run_test "Connectivité ProxySQL" \
        "ssh ${SSH_KEY_OPTS} root@${PROXYSQL_IP} 'docker exec proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e \"SELECT 1;\"' > /dev/null 2>&1"
    
    # Test 2: Backend servers
    run_test "ProxySQL backend servers" \
        "ssh ${SSH_KEY_OPTS} root@${PROXYSQL_IP} 'docker exec proxysql mysql -h127.0.0.1 -P6032 -uadmin -padmin -e \"SELECT * FROM mysql_servers;\"' | grep -q 'ONLINE'"
    
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
    
    # Test 1: Cluster K3s accessible
    run_test "Cluster K3s accessible" \
        "ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get nodes' | grep -q 'Ready'"
    
    # Test 2: Nombre de nodes
    NODE_COUNT=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get nodes --no-headers 2>/dev/null | wc -l' || echo "0")
    if [[ ${NODE_COUNT} -ge 8 ]]; then
        log_success "  Nodes K3s: ${NODE_COUNT} (attendu: ≥8)"
        ((PASSED_TESTS++))
    else
        log_warning "  Nodes K3s: ${NODE_COUNT} (attendu: ≥8)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 3: Ingress NGINX
    INGRESS_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers 2>/dev/null | grep -c Running' || echo "0")
    if [[ ${INGRESS_PODS} -ge 5 ]]; then
        log_success "  Ingress NGINX: ${INGRESS_PODS} pods Running (attendu: ≥5)"
        ((PASSED_TESTS++))
    else
        log_warning "  Ingress NGINX: ${INGRESS_PODS} pods Running (attendu: ≥5)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 4: Ingress NGINX hostNetwork
    INGRESS_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get daemonset -n ingress-nginx -o jsonpath="{.items[0].spec.template.spec.hostNetwork}" 2>/dev/null' || echo "false")
    if [[ "${INGRESS_HOSTNETWORK}" == "true" ]]; then
        log_success "  Ingress NGINX hostNetwork: activé"
        ((PASSED_TESTS++))
    else
        log_warning "  Ingress NGINX hostNetwork: ${INGRESS_HOSTNETWORK} (attendu: true)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 5: CoreDNS
    COREDNS_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c Running' || echo "0")
    if [[ ${COREDNS_PODS} -ge 1 ]]; then
        log_success "  CoreDNS: ${COREDNS_PODS} pods Running"
        ((PASSED_TESTS++))
    else
        log_warning "  CoreDNS: ${COREDNS_PODS} pods Running"
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
    # Test 1: DaemonSets KeyBuzz
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
    
    # Test 2: Pods KeyBuzz
    KEYBUZZ_API_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n keybuzz -l app=keybuzz-api --no-headers 2>/dev/null | grep -c Running' || echo "0")
    KEYBUZZ_FRONT_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | grep -c Running' || echo "0")
    
    if [[ ${KEYBUZZ_API_PODS} -ge 5 ]] && [[ ${KEYBUZZ_FRONT_PODS} -ge 5 ]]; then
        log_success "  Pods KeyBuzz: API=${KEYBUZZ_API_PODS}, Front=${KEYBUZZ_FRONT_PODS}"
        ((PASSED_TESTS++))
    else
        log_warning "  Pods KeyBuzz: API=${KEYBUZZ_API_PODS}, Front=${KEYBUZZ_FRONT_PODS} (attendu: ≥5 chacun)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 3: hostNetwork activé
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
    
    # Test 4: Services NodePort
    API_SVC_TYPE=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get svc keybuzz-api -n keybuzz -o jsonpath="{.spec.type}" 2>/dev/null' || echo "ClusterIP")
    FRONT_SVC_TYPE=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get svc keybuzz-front -n keybuzz -o jsonpath="{.spec.type}" 2>/dev/null' || echo "ClusterIP")
    
    if [[ "${API_SVC_TYPE}" == "NodePort" ]] && [[ "${FRONT_SVC_TYPE}" == "NodePort" ]]; then
        log_success "  Services: NodePort (API et Front)"
        ((PASSED_TESTS++))
    else
        log_warning "  Services: API=${API_SVC_TYPE}, Front=${FRONT_SVC_TYPE} (attendu: NodePort)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 5: Endpoints
    API_ENDPOINTS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get endpoints keybuzz-api -n keybuzz -o jsonpath="{.subsets[0].addresses[*].ip}" 2>/dev/null' | wc -w || echo "0")
    FRONT_ENDPOINTS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get endpoints keybuzz-front -n keybuzz -o jsonpath="{.subsets[0].addresses[*].ip}" 2>/dev/null' | wc -w || echo "0")
    
    if [[ ${API_ENDPOINTS} -ge 5 ]] && [[ ${FRONT_ENDPOINTS} -ge 5 ]]; then
        log_success "  Endpoints: API=${API_ENDPOINTS}, Front=${FRONT_ENDPOINTS}"
        ((PASSED_TESTS++))
    else
        log_warning "  Endpoints: API=${API_ENDPOINTS}, Front=${FRONT_ENDPOINTS} (attendu: ≥5 chacun)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 6: Ingress
    INGRESS_COUNT=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get ingress -n keybuzz --no-headers 2>/dev/null | wc -l' || echo "0")
    if [[ ${INGRESS_COUNT} -ge 2 ]]; then
        log_success "  Ingress: ${INGRESS_COUNT} configurés"
        ((PASSED_TESTS++))
    else
        log_warning "  Ingress: ${INGRESS_COUNT} (attendu: ≥2)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Test 7: Connectivité directe pods (hostNetwork)
    WORKER_IP=$(grep -E "k3s" "${TSV_FILE}" | grep -E "worker" | head -1 | awk -F'\t' '{print $4}')
    if [[ -n "${WORKER_IP}" ]]; then
        run_test "Connectivité API directe (hostNetwork 8080)" \
            "timeout 3 curl -s http://${WORKER_IP}:8080 > /dev/null 2>&1"
        
        run_test "Connectivité Front directe (hostNetwork 3000)" \
            "timeout 3 curl -s http://${WORKER_IP}:3000 > /dev/null 2>&1"
    fi
    
    # Test 8: URLs publiques
    run_test "URL platform.keybuzz.io accessible" \
        "timeout 10 curl -s -o /dev/null -w '%{http_code}' https://platform.keybuzz.io | grep -q '200'"
    
    run_test "URL platform-api.keybuzz.io accessible" \
        "timeout 10 curl -s -o /dev/null -w '%{http_code}' https://platform-api.keybuzz.io | grep -q '200'"
    
    echo ""
else
    log_warning "Module 10 : K3s non disponible pour tests"
    echo ""
fi

# ============================================================
# MODULE 11 : n8n (si installé)
# ============================================================
echo "=============================================================="
echo " MODULE 11 : n8n (si installé)"
echo "=============================================================="
echo ""

if [[ -n "${K3S_MASTER_IP}" ]]; then
    N8N_DEPLOYMENT=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get deployment n8n -n n8n --no-headers 2>/dev/null | wc -l' || echo "0")
    
    if [[ ${N8N_DEPLOYMENT} -eq 1 ]]; then
        log_info "n8n détecté"
        
        # Test 1: Pods n8n
        N8N_PODS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get pods -n n8n -l app=n8n --no-headers 2>/dev/null | grep -c Running' || echo "0")
        if [[ ${N8N_PODS} -ge 1 ]]; then
            log_success "  Pods n8n: ${N8N_PODS} Running"
            ((PASSED_TESTS++))
        else
            log_warning "  Pods n8n: ${N8N_PODS} Running"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
        
        # Test 2: Service n8n
        N8N_SVC=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get svc n8n -n n8n --no-headers 2>/dev/null | wc -l' || echo "0")
        if [[ ${N8N_SVC} -eq 1 ]]; then
            log_success "  Service n8n: présent"
            ((PASSED_TESTS++))
        else
            log_warning "  Service n8n: absent"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
        
        # Test 3: Ingress n8n
        N8N_INGRESS=$(ssh ${SSH_KEY_OPTS} root@${K3S_MASTER_IP} 'kubectl get ingress -n n8n --no-headers 2>/dev/null | wc -l' || echo "0")
        if [[ ${N8N_INGRESS} -ge 1 ]]; then
            log_success "  Ingress n8n: présent"
            ((PASSED_TESTS++))
        else
            log_warning "  Ingress n8n: absent"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    else
        log_info "n8n non installé (normal si Module 11 pas encore exécuté)"
    fi
    
    echo ""
fi

# ============================================================
# TESTS DE FAILOVER
# ============================================================
echo "=============================================================="
echo " TESTS DE FAILOVER"
echo "=============================================================="
echo ""

log_warning "⚠️  Les tests de failover sont non-destructifs (lecture seule)"
echo ""

# Test failover PostgreSQL (lecture seule)
if [[ -n "${PG_MASTER_IP}" ]]; then
    log_info "Test failover PostgreSQL (lecture seule)..."
    
    # Obtenir le leader actuel
    CURRENT_LEADER=$(ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni patronictl list -f json 2>/dev/null' | grep -o '"Role":"Leader"' | wc -l || echo "0")
    
    if [[ ${CURRENT_LEADER} -ge 1 ]]; then
        log_success "  Leader PostgreSQL détecté"
        ((PASSED_TESTS++))
    else
        log_warning "  Leader PostgreSQL non détecté"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    # Vérifier les réplicas
    REPLICA_COUNT=$(ssh ${SSH_KEY_OPTS} root@${PG_MASTER_IP} 'docker exec patroni patronictl list 2>/dev/null' | grep -c 'Replica\|Standby' || echo "0")
    if [[ ${REPLICA_COUNT} -ge 1 ]]; then
        log_success "  Réplicas PostgreSQL: ${REPLICA_COUNT}"
        ((PASSED_TESTS++))
    else
        log_warning "  Réplicas PostgreSQL: ${REPLICA_COUNT} (attendu: ≥1)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
fi

# Test failover Redis (lecture seule)
if [[ -n "${REDIS_MASTER_IP}" ]]; then
    log_info "Test failover Redis (lecture seule)..."
    
    # Vérifier Sentinel
    SENTINEL_IP=$(grep -E "redis" "${TSV_FILE}" | grep -E "sentinel" | head -1 | awk -F'\t' '{print $4}')
    if [[ -z "${SENTINEL_IP}" ]]; then
        SENTINEL_IP=$(grep -E "redis" "${TSV_FILE}" | head -1 | awk -F'\t' '{print $4}')
    fi
    if [[ -n "${SENTINEL_IP}" ]]; then
        if [[ -n "${REDIS_PASSWORD}" ]]; then
            MASTER_FROM_SENTINEL=$(ssh ${SSH_KEY_OPTS} root@${SENTINEL_IP} "docker exec sentinel redis-cli -a '${REDIS_PASSWORD}' -p 26379 SENTINEL get-master-addr-by-name mymaster 2>/dev/null" | head -1 || echo "")
        else
            MASTER_FROM_SENTINEL=$(ssh ${SSH_KEY_OPTS} root@${SENTINEL_IP} 'docker exec sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name mymaster 2>/dev/null' | head -1 || echo "")
        fi
        
        if [[ -n "${MASTER_FROM_SENTINEL}" ]]; then
            log_success "  Sentinel détecte le master: ${MASTER_FROM_SENTINEL}"
            ((PASSED_TESTS++))
        else
            log_warning "  Sentinel ne détecte pas de master"
            ((FAILED_TESTS++))
        fi
        ((TOTAL_TESTS++))
    fi
    
    echo ""
fi

# Test failover MariaDB Galera (lecture seule)
if [[ ${#MARIADB_NODES[@]} -gt 0 ]]; then
    log_info "Test failover MariaDB Galera (lecture seule)..."
    
    MARIADB_IP="${MARIADB_NODES[0]}"
    if [[ -n "${MARIADB_ROOT_PASSWORD}" ]]; then
        CLUSTER_SIZE=$(ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} "docker exec mariadb mysql -uroot -p'${MARIADB_ROOT_PASSWORD}' -e 'SHOW STATUS LIKE \"wsrep_cluster_size\";' 2>/dev/null" | grep -oE '[0-9]+' | tail -1 || echo "0")
    else
        CLUSTER_SIZE=$(ssh ${SSH_KEY_OPTS} root@${MARIADB_IP} 'docker exec mariadb mysql -uroot -e "SHOW STATUS LIKE \"wsrep_cluster_size\";" 2>/dev/null' | grep -oE '[0-9]+' | tail -1 || echo "0")
    fi
    
    if [[ ${CLUSTER_SIZE} -ge 2 ]]; then
        log_success "  Cluster Galera: ${CLUSTER_SIZE} nodes"
        ((PASSED_TESTS++))
    else
        log_warning "  Cluster Galera: ${CLUSTER_SIZE} nodes (attendu: ≥2)"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
    
    echo ""
fi

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
echo "=============================================================="
echo " RÉSUMÉ DES TESTS"
echo "=============================================================="
echo ""

PERCENTAGE=$((PASSED_TESTS * 100 / TOTAL_TESTS))

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
    log_warning "⚠️  La plupart des tests sont réussis"
    echo ""
    log_info "Quelques tests ont échoué, mais l'infrastructure est"
    log_info "globalement opérationnelle."
    echo ""
    log_warning "Vérifiez les tests échoués ci-dessus pour plus de détails."
    echo ""
    exit 0
else
    log_error "❌ Plusieurs tests ont échoué"
    echo ""
    log_warning "L'infrastructure nécessite une attention."
    log_warning "Vérifiez les tests échoués ci-dessus."
    echo ""
    exit 1
fi

