#!/usr/bin/env bash
#
# 05_rmq_03_configure_haproxy.sh - Configuration HAProxy pour RabbitMQ
#
# Ce script configure HAProxy sur haproxy-01/02 pour router vers le cluster RabbitMQ.
#
# Usage:
#   ./05_rmq_03_configure_haproxy.sh [servers.tsv]
#
# Prérequis:
#   - Script 05_rmq_02_deploy_cluster.sh exécuté
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 5 - Configuration HAProxy pour RabbitMQ"
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

if [[ ${#RABBITMQ_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds RabbitMQ incorrect: ${#RABBITMQ_NODES[@]} (attendu: 3)"
    exit 1
fi

if [[ ${#HAPROXY_NODES[@]} -ne 2 ]]; then
    log_error "Nombre de nœuds HAProxy incorrect: ${#HAPROXY_NODES[@]} (attendu: 2)"
    exit 1
fi

log_info "RabbitMQ nodes: ${RABBITMQ_IPS[*]}"
log_info "HAProxy nodes: ${HAPROXY_IPS[*]}"
echo ""

# Configurer HAProxy sur chaque nœud
for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Configuration HAProxy sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

BASE="/opt/keybuzz/rabbitmq-lb"

# Nettoyer les anciens conteneurs
docker stop haproxy-rabbitmq 2>/dev/null || true
docker rm haproxy-rabbitmq 2>/dev/null || true

# Créer les répertoires
mkdir -p "\${BASE}"/{config,status}

# Configuration HAProxy (bind sur IP privée)
cat > "\${BASE}/config/haproxy-rabbitmq.cfg" <<HAPROXY_CFG
global
    maxconn 10000
    log stdout local0

defaults
    mode tcp
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    log global

frontend fe_rabbitmq_5672
    bind ${ip}:5672
    default_backend be_rabbitmq

backend be_rabbitmq
    mode tcp
    option tcp-check
    # RabbitMQ AMQP n'a pas d'endpoint HTTP, on utilise TCP check simple
    tcp-check connect
    tcp-check send-binary 0000000000000000
    tcp-check expect binary 000a
    server queue1 ${RABBITMQ_IPS[0]}:5672 check inter 2s fall 3 rise 2
    server queue2 ${RABBITMQ_IPS[1]}:5672 check inter 2s fall 3 rise 2 backup
    server queue3 ${RABBITMQ_IPS[2]}:5672 check inter 2s fall 3 rise 2 backup
HAPROXY_CFG

# Démarrer HAProxy
docker run -d \
  --name haproxy-rabbitmq \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/config/haproxy-rabbitmq.cfg":/usr/local/etc/haproxy/haproxy.cfg:ro \
  haproxy:2.9-alpine

sleep 2

# Vérifier que HAProxy est démarré
if docker ps | grep -q "haproxy-rabbitmq"; then
    echo "  ✓ HAProxy démarré"
    echo "OK" > "\${BASE}/status/STATE"
else
    echo "  ✗ Échec du démarrage HAProxy"
    echo "ERROR" > "\${BASE}/status/STATE"
    exit 1
fi

# Test de connectivité TCP (simple)
if timeout 3 nc -z ${ip} 5672 2>/dev/null; then
    echo "  ✓ HAProxy écoute sur le port 5672"
else
    echo "  ⚠ HAProxy ne répond pas encore (peut être normal au démarrage)"
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "HAProxy configuré avec succès sur ${hostname}"
    else
        log_error "Échec de la configuration HAProxy sur ${hostname}"
        exit 1
    fi
    echo ""
done

# Vérification finale
log_info "Vérification finale de HAProxy..."

for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    if timeout 3 nc -z "${ip}" 5672 2>/dev/null; then
        log_success "${hostname}: HAProxy opérationnel"
    else
        log_warning "${hostname}: HAProxy ne répond pas (peut nécessiter quelques secondes)"
    fi
done

echo ""
echo "=============================================================="
log_success "✅ Configuration HAProxy pour RabbitMQ terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - HAProxy déployé sur: ${HAPROXY_NODES[*]}"
log_info "  - Points d'accès:"
log_info "    - haproxy-01: ${HAPROXY_IPS[0]}:5672"
log_info "    - haproxy-02: ${HAPROXY_IPS[1]}:5672"
log_info ""
log_info "Note: Le LB Hetzner (10.0.0.10:5672) doit être configuré manuellement"
log_info "  pour pointer vers haproxy-01 et haproxy-02"
log_info ""
log_info "Prochaine étape: Exécuter les tests"
log_info "  ./05_rmq_04_tests.sh ${TSV_FILE}"
echo ""

