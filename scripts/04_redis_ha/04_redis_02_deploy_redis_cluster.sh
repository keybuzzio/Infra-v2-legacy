#!/usr/bin/env bash
#
# 04_redis_02_deploy_redis_cluster.sh - Déploiement du cluster Redis
#
# Ce script déploie le cluster Redis (master + replicas) en Docker.
# Il utilise --network host et bind sur l'IP privée pour la sécurité.
#
# Usage:
#   ./04_redis_02_deploy_redis_cluster.sh [servers.tsv]
#
# Prérequis:
#   - Script 04_redis_01_prepare_nodes.sh exécuté
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/redis.env"

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
echo " [KeyBuzz] Module 4 - Déploiement Cluster Redis"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds Redis
declare -a REDIS_NODES
declare -a REDIS_IPS
declare -a REDIS_ROLES

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "redis" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "redis-01" ]] || \
       [[ "${HOSTNAME}" == "redis-02" ]] || \
       [[ "${HOSTNAME}" == "redis-03" ]]; then
        REDIS_NODES+=("${HOSTNAME}")
        REDIS_IPS+=("${IP_PRIVEE}")
        REDIS_ROLES+=("${SUBROLE}")
    fi
done
exec 3<&-

if [[ ${#REDIS_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds Redis incorrect: ${#REDIS_NODES[@]} (attendu: 3)"
    exit 1
fi

# Trouver le master initial
MASTER_IP=""
MASTER_NODE=""
for i in "${!REDIS_NODES[@]}"; do
    if [[ "${REDIS_ROLES[$i]}" == "master" ]]; then
        MASTER_NODE="${REDIS_NODES[$i]}"
        MASTER_IP="${REDIS_IPS[$i]}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    MASTER_NODE="redis-01"
    for i in "${!REDIS_NODES[@]}"; do
        if [[ "${REDIS_NODES[$i]}" == "redis-01" ]]; then
            MASTER_IP="${REDIS_IPS[$i]}"
            break
        fi
    done
fi

log_info "Master initial: ${MASTER_NODE} (${MASTER_IP})"
echo ""

# Copier les credentials sur tous les nœuds Redis
log_info "Copie des credentials sur les nœuds Redis..."
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" "mkdir -p /opt/keybuzz-installer/credentials"
    scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${ip}:/opt/keybuzz-installer/credentials/"
done
log_success "Credentials copiés sur tous les nœuds"
echo ""

# Nettoyer les anciens conteneurs sur tous les nœuds
log_info "Nettoyage des anciens conteneurs Redis..."
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
docker stop redis 2>/dev/null || true
docker rm redis 2>/dev/null || true
EOF
done
log_success "Anciens conteneurs nettoyés"
echo ""

# Déployer le master initial
log_info "--------------------------------------------------------------"
log_info "Déploiement du master initial: ${MASTER_NODE} (${MASTER_IP})"
log_info "--------------------------------------------------------------"

ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/redis.env
BASE="/opt/keybuzz/redis"

# Déployer Redis Master (utilise les arguments de ligne de commande comme dans les anciens scripts)
docker run -d --name redis \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/data":/data \
  redis:7-alpine redis-server \
    --bind ${MASTER_IP} \
    --port 6379 \
    --requirepass "\${REDIS_PASSWORD}" \
    --masterauth "\${REDIS_PASSWORD}" \
    --appendonly yes \
    --save 900 1 \
    --save 300 10 \
    --maxmemory-policy allkeys-lru

sleep 3

# Vérifier que Redis est démarré
if docker ps | grep -q "redis"; then
    echo "  ✓ Redis Master démarré"
else
    echo "  ✗ Échec du démarrage Redis"
    docker logs redis --tail 20 2>&1 || true
    exit 1
fi

# Test de connexion (avec --network host, on peut utiliser l'IP privée depuis l'hôte)
if timeout 3 redis-cli -h ${MASTER_IP} -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
    echo "  ✓ Redis Master répond correctement"
else
    # Essayer depuis l'intérieur du conteneur
    if docker exec redis redis-cli -h ${MASTER_IP} -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
        echo "  ✓ Redis Master répond correctement (depuis conteneur)"
    else
        echo "  ✗ Redis Master ne répond pas"
        docker logs redis --tail 10 2>&1 || true
        exit 1
    fi
fi
EOF

if [ $? -eq 0 ]; then
    log_success "Master Redis déployé avec succès"
else
    log_error "Échec du déploiement du master"
    exit 1
fi
echo ""

# Attendre que le master soit stable
log_info "Attente de stabilisation du master (5 secondes)..."
sleep 5

# Déployer les replicas
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    role="${REDIS_ROLES[$i]}"
    
    # Skip le master
    if [[ "${hostname}" == "${MASTER_NODE}" ]]; then
        continue
    fi
    
    log_info "--------------------------------------------------------------"
    log_info "Déploiement du replica: ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/redis.env
BASE="/opt/keybuzz/redis"

# Déployer Redis Replica (utilise les arguments de ligne de commande)
docker run -d --name redis \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/data":/data \
  redis:7-alpine redis-server \
    --bind ${ip} \
    --port 6379 \
    --requirepass "\${REDIS_PASSWORD}" \
    --masterauth "\${REDIS_PASSWORD}" \
    --replicaof ${MASTER_IP} 6379 \
    --appendonly yes \
    --maxmemory-policy allkeys-lru

sleep 3

# Vérifier que Redis est démarré
if docker ps | grep -q "redis"; then
    echo "  ✓ Redis Replica démarré"
else
    echo "  ✗ Échec du démarrage Redis"
    docker logs redis --tail 20 2>&1 || true
    exit 1
fi

# Test de connexion
if timeout 3 redis-cli -h ${ip} -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
    echo "  ✓ Redis Replica répond correctement"
else
    # Essayer depuis l'intérieur du conteneur
    if docker exec redis redis-cli -h ${ip} -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
        echo "  ✓ Redis Replica répond correctement (depuis conteneur)"
    else
        echo "  ✗ Redis Replica ne répond pas"
        docker logs redis --tail 10 2>&1 || true
        exit 1
    fi
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "Replica Redis déployé avec succès"
    else
        log_error "Échec du déploiement du replica ${hostname}"
        exit 1
    fi
    echo ""
done

# Attendre que la réplication soit établie
log_info "Attente de l'établissement de la réplication (10 secondes)..."
sleep 10

# Vérifier la réplication
log_info "Vérification de la réplication..."

# Vérifier le master (depuis l'intérieur du conteneur)
MASTER_ROLE=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MASTER_IP}" \
    "docker exec redis redis-cli -h ${MASTER_IP} -p 6379 -a '${REDIS_PASSWORD}' --no-auth-warning INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r ' || echo ''")

if [[ "${MASTER_ROLE}" == "master" ]]; then
    log_success "Master Redis: rôle confirmé (master)"
    
    # Compter les replicas connectés
    REPLICA_COUNT=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MASTER_IP}" \
        "timeout 3 redis-cli -h ${MASTER_IP} -p 6379 -a '${REDIS_PASSWORD}' --no-auth-warning INFO replication 2>/dev/null | grep 'connected_slaves:' | cut -d: -f2 | tr -d '\r ' || echo '0'")
    
    log_info "Replicas connectés: ${REPLICA_COUNT}"
    
    if [[ "${REPLICA_COUNT}" == "2" ]]; then
        log_success "Tous les replicas sont connectés"
    else
        log_warning "Seulement ${REPLICA_COUNT}/2 replicas connectés"
    fi
else
    log_error "Le master n'a pas le bon rôle: ${MASTER_ROLE}"
fi

# Vérifier les replicas
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    role="${REDIS_ROLES[$i]}"
    
    if [[ "${hostname}" == "${MASTER_NODE}" ]]; then
        continue
    fi
    
    REPLICA_ROLE=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec redis redis-cli -h ${ip} -p 6379 -a '${REDIS_PASSWORD}' --no-auth-warning INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r ' || echo ''")
    
    if [[ "${REPLICA_ROLE}" == "slave" ]] || [[ "${REPLICA_ROLE}" == "replica" ]]; then
        log_success "${hostname}: rôle confirmé (replica)"
    else
        log_warning "${hostname}: rôle inattendu (${REPLICA_ROLE})"
    fi
done

echo ""
echo "=============================================================="
log_success "✅ Déploiement du cluster Redis terminé !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Master: ${MASTER_NODE} (${MASTER_IP})"
log_info "  - Replicas: $((${#REDIS_NODES[@]} - 1)) nœuds"
log_info ""
log_info "Prochaine étape: Déployer Redis Sentinel"
log_info "  ./04_redis_03_deploy_sentinel.sh ${TSV_FILE}"
echo ""

