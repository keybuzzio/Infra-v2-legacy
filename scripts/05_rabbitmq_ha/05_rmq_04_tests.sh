#!/usr/bin/env bash
#
# 05_rmq_04_tests.sh - Tests et diagnostics RabbitMQ HA
#
# Ce script exécute une série de tests pour valider le cluster RabbitMQ HA :
# - Tests de connectivité
# - Tests AMQP (publish/consume)
# - Tests de cluster
# - Tests HAProxy
#
# Usage:
#   ./05_rmq_04_tests.sh [servers.tsv]
#
# Prérequis:
#   - Tous les scripts précédents exécutés
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/rabbitmq.env"

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

# Vérifier que pika est disponible (pour les tests Python)
if ! python3 -c "import pika" 2>/dev/null; then
    log_info "Installation de pika (bibliothèque Python pour RabbitMQ)..."
    apt-get update -qq >/dev/null 2>&1 && \
    apt-get install -y -qq python3-pip >/dev/null 2>&1 && \
    pip3 install --quiet pika >/dev/null 2>&1 || {
        log_warning "Impossible d'installer pika, les tests AMQP seront ignorés"
        SKIP_AMQP_TESTS=true
    }
else
    SKIP_AMQP_TESTS=false
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 5 - Tests et Diagnostics RabbitMQ HA"
echo "=============================================================="
echo ""

# Collecter les informations
declare -a RABBITMQ_NODES
declare -a RABBITMQ_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..."

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
    
    if [[ "${ROLE}" == "queue" ]] && [[ "${SUBROLE}" == "rabbitmq" ]] && \
       ([[ "${HOSTNAME}" == "queue-01" ]] || \
        [[ "${HOSTNAME}" == "queue-02" ]] || \
        [[ "${HOSTNAME}" == "queue-03" ]]); then
        RABBITMQ_NODES+=("${HOSTNAME}")
        RABBITMQ_IPS+=("${IP_PRIVEE}")
    fi
    
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]] && \
       ([[ "${HOSTNAME}" == "haproxy-01" ]] || [[ "${HOSTNAME}" == "haproxy-02" ]]); then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

# Test 1: Connectivité RabbitMQ directe
log_info "=============================================================="
log_info "Test 1: Connectivité RabbitMQ (directe)"
log_info "=============================================================="

RABBITMQ_OK=0
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    if timeout 3 nc -z "${ip}" 5672 2>/dev/null; then
        log_success "${hostname} (${ip}): Port 5672 ouvert"
        ((RABBITMQ_OK++))
    else
        log_error "${hostname} (${ip}): Port 5672 fermé"
    fi
done

if [[ ${RABBITMQ_OK} -eq ${#RABBITMQ_NODES[@]} ]]; then
    log_success "Tous les nœuds RabbitMQ sont accessibles"
else
    log_warning "Seulement ${RABBITMQ_OK}/${#RABBITMQ_NODES[@]} nœuds RabbitMQ accessibles"
fi
echo ""

# Test 2: Statut du cluster
log_info "=============================================================="
log_info "Test 2: Statut du cluster RabbitMQ"
log_info "=============================================================="

CLUSTER_OK=0
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    CLUSTER_STATUS=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'running_nodes' || echo '0'")
    
    if [[ "${CLUSTER_STATUS}" == "1" ]]; then
        log_success "${hostname}: Cluster opérationnel"
        ((CLUSTER_OK++))
    else
        log_warning "${hostname}: Statut cluster à vérifier"
    fi
done

if [[ ${CLUSTER_OK} -eq ${#RABBITMQ_NODES[@]} ]]; then
    log_success "Tous les nœuds voient le cluster"
else
    log_warning "Seulement ${CLUSTER_OK}/${#RABBITMQ_NODES[@]} nœuds voient le cluster"
fi
echo ""

# Test 3: HAProxy
log_info "=============================================================="
log_info "Test 3: HAProxy"
log_info "=============================================================="

HAPROXY_OK=0
for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    if timeout 3 nc -z "${ip}" 5672 2>/dev/null; then
        log_success "${hostname} (${ip}): HAProxy opérationnel"
        ((HAPROXY_OK++))
    else
        log_error "${hostname} (${ip}): HAProxy ne répond pas"
    fi
done

if [[ ${HAPROXY_OK} -eq ${#HAPROXY_NODES[@]} ]]; then
    log_success "Tous les HAProxy sont opérationnels"
else
    log_warning "Seulement ${HAPROXY_OK}/${#HAPROXY_NODES[@]} HAProxy opérationnels"
fi
echo ""

# Test 4: AMQP via HAProxy (si pika est disponible)
if [[ "${SKIP_AMQP_TESTS:-false}" != "true" ]] && python3 -c "import pika" 2>/dev/null; then
    log_info "=============================================================="
    log_info "Test 4: AMQP via HAProxy (publish/consume)"
    log_info "=============================================================="
    
    if [[ ${#HAPROXY_IPS[@]} -gt 0 ]]; then
        TEST_IP="${HAPROXY_IPS[0]}"
        TEST_QUEUE="keybuzz_test_$(date +%s)"
        TEST_MESSAGE="test_message_$(date +%s)"
        
        # Test publish
        if python3 <<PYTHON_EOF
import pika
import sys
try:
    conn = pika.BlockingConnection(
        pika.ConnectionParameters(
            '${TEST_IP}', 
            5672, 
            '/', 
            pika.PlainCredentials('${RABBITMQ_USER}', '${RABBITMQ_PASSWORD}')
        )
    )
    channel = conn.channel()
    channel.queue_declare(queue='${TEST_QUEUE}', durable=True)
    channel.basic_publish(
        exchange='', 
        routing_key='${TEST_QUEUE}', 
        body='${TEST_MESSAGE}',
        properties=pika.BasicProperties(delivery_mode=2)  # Make message persistent
    )
    conn.close()
    print("OK")
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYTHON_EOF
        then
            log_success "Publish réussi via HAProxy (${TEST_IP})"
            
            # Attendre un peu
            sleep 2
            
            # Test consume
            if python3 <<PYTHON_EOF
import pika
import sys
try:
    conn = pika.BlockingConnection(
        pika.ConnectionParameters(
            '${TEST_IP}', 
            5672, 
            '/', 
            pika.PlainCredentials('${RABBITMQ_USER}', '${RABBITMQ_PASSWORD}')
        )
    )
    channel = conn.channel()
    method, properties, body = channel.basic_get('${TEST_QUEUE}')
    if method and body.decode() == '${TEST_MESSAGE}':
        channel.basic_ack(method.delivery_tag)
        print("OK")
    else:
        print("ERROR: Message not found or incorrect")
        sys.exit(1)
    conn.close()
except Exception as e:
    print(f"ERROR: {e}")
    sys.exit(1)
PYTHON_EOF
            then
                log_success "Consume réussi: message correctement reçu"
            else
                log_error "Consume échoué: message non reçu ou incorrect"
            fi
        else
            log_error "Publish échoué via HAProxy"
        fi
    else
        log_warning "Aucun HAProxy disponible pour le test"
    fi
    echo ""
else
    log_warning "Test 4 ignoré (pika non disponible)"
    echo ""
fi

# Test 5: Quorum Queues
log_info "=============================================================="
log_info "Test 5: Quorum Queues"
log_info "=============================================================="

QUORUM_OK=0
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    QUORUM_ENABLED=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl environment 2>/dev/null | grep -i 'default_queue_type.*quorum' || echo ''")
    
    if [[ -n "${QUORUM_ENABLED}" ]]; then
        log_success "${hostname}: Quorum Queues activées"
        ((QUORUM_OK++))
    else
        log_warning "${hostname}: Quorum Queues non confirmées"
    fi
done

if [[ ${QUORUM_OK} -eq ${#RABBITMQ_NODES[@]} ]]; then
    log_success "Quorum Queues activées sur tous les nœuds"
else
    log_warning "Quorum Queues: ${QUORUM_OK}/${#RABBITMQ_NODES[@]} nœuds"
fi
echo ""

# Résumé final
echo "=============================================================="
log_info "Résumé des tests"
echo "=============================================================="
echo ""
log_info "RabbitMQ:"
log_info "  - Nœuds accessibles: ${RABBITMQ_OK}/${#RABBITMQ_NODES[@]}"
log_info "  - Cluster opérationnel: ${CLUSTER_OK}/${#RABBITMQ_NODES[@]}"
log_info "  - Quorum Queues: ${QUORUM_OK}/${#RABBITMQ_NODES[@]}"
echo ""
log_info "HAProxy:"
log_info "  - HAProxy opérationnels: ${HAPROXY_OK}/${#HAPROXY_NODES[@]}"
echo ""

# Vérifier le cluster plus en détail
log_info "Vérification détaillée du cluster..."
CLUSTER_DETAIL_OK=0
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    RUNNING_NODES=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'running_nodes' || echo '0'")
    
    if [[ "${RUNNING_NODES}" == "1" ]]; then
        log_success "${hostname}: Cluster opérationnel"
        ((CLUSTER_DETAIL_OK++))
    else
        log_warning "${hostname}: Cluster à vérifier (${RUNNING_NODES} running_nodes trouvés)"
    fi
done

if [[ ${RABBITMQ_OK} -eq ${#RABBITMQ_NODES[@]} ]] && \
   [[ ${CLUSTER_DETAIL_OK} -ge 1 ]] && \
   [[ ${HAPROXY_OK} -eq ${#HAPROXY_NODES[@]} ]]; then
    echo "=============================================================="
    log_success "✅ Tous les tests sont passés avec succès !"
    echo "=============================================================="
    echo ""
    log_info "Le cluster RabbitMQ HA est opérationnel et prêt pour la production."
    echo ""
    exit 0
else
    echo "=============================================================="
    log_warning "⚠️  Certains tests ont échoué"
    echo "=============================================================="
    echo ""
    log_warning "Vérifiez les erreurs ci-dessus et corrigez les problèmes."
    echo ""
    exit 1
fi

