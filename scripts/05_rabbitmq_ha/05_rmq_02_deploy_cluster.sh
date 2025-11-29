#!/usr/bin/env bash
#
# 05_rmq_02_deploy_cluster.sh - Déploiement du cluster RabbitMQ
#
# Ce script déploie le cluster RabbitMQ (3 nœuds) en Docker et configure
# le clustering avec Quorum Queues.
#
# Usage:
#   ./05_rmq_02_deploy_cluster.sh [servers.tsv]
#
# Prérequis:
#   - Script 05_rmq_01_prepare_nodes.sh exécuté
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
echo " [KeyBuzz] Module 5 - Déploiement Cluster RabbitMQ"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds RabbitMQ
declare -a RABBITMQ_NODES
declare -a RABBITMQ_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "queue" ]] || [[ "${SUBROLE}" != "rabbitmq" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "queue-01" ]] || \
       [[ "${HOSTNAME}" == "queue-02" ]] || \
       [[ "${HOSTNAME}" == "queue-03" ]]; then
        RABBITMQ_NODES+=("${HOSTNAME}")
        RABBITMQ_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#RABBITMQ_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds RabbitMQ incorrect: ${#RABBITMQ_NODES[@]} (attendu: 3)"
    exit 1
fi

log_success "${#RABBITMQ_NODES[@]} nœuds RabbitMQ trouvés: ${RABBITMQ_NODES[*]}"
echo ""

# Copier les credentials sur tous les nœuds
log_info "Copie des credentials sur les nœuds RabbitMQ..."
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" "mkdir -p /opt/keybuzz-installer/credentials"
    scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${ip}:/opt/keybuzz-installer/credentials/"
done
log_success "Credentials copiés sur tous les nœuds"
echo ""

# Nettoyer les anciens conteneurs et le cookie existant
log_info "Nettoyage des anciens conteneurs RabbitMQ..."
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
docker stop rabbitmq 2>/dev/null || true
docker rm rabbitmq 2>/dev/null || true
# Supprimer le cookie existant dans le volume data (le conteneur le recréera avec les bonnes permissions)
rm -f /opt/keybuzz/rabbitmq/data/.erlang.cookie 2>/dev/null || true
EOF
done
log_success "Anciens conteneurs et cookies nettoyés"
echo ""

# Déployer RabbitMQ sur chaque nœud
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Déploiement RabbitMQ sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/rabbitmq.env
BASE="/opt/keybuzz/rabbitmq"

# Générer rabbitmq.conf (configuration minimale comme dans les anciens scripts fonctionnels)
cat > "\${BASE}/conf/rabbitmq.conf" <<RMQ_CONF
cluster_name = keybuzz-queue
default_queue_type = quorum
management.tcp.port = 15672
loopback_users.guest = false
RMQ_CONF

chmod 644 "\${BASE}/conf/rabbitmq.conf"

# Ajouter les hostnames dans /etc/hosts pour la résolution DNS dans le conteneur
grep -q "queue-01" /etc/hosts || echo "${RABBITMQ_IPS[0]} queue-01" >> /etc/hosts
grep -q "queue-02" /etc/hosts || echo "${RABBITMQ_IPS[1]} queue-02" >> /etc/hosts
grep -q "queue-03" /etc/hosts || echo "${RABBITMQ_IPS[2]} queue-03" >> /etc/hosts

# Déployer RabbitMQ (utilise --network host comme dans les anciens scripts fonctionnels)
# Note: On ne monte PAS le cookie directement, on le passe via variable d'environnement
# Le conteneur créera le cookie avec les bonnes permissions automatiquement
docker run -d --name rabbitmq \
  --restart unless-stopped \
  --network host \
  --hostname ${hostname} \
  -e RABBITMQ_ERLANG_COOKIE="\${RABBITMQ_ERLANG_COOKIE}" \
  -e RABBITMQ_DEFAULT_USER="\${RABBITMQ_USER}" \
  -e RABBITMQ_DEFAULT_PASS="\${RABBITMQ_PASSWORD}" \
  -e RABBITMQ_NODENAME="rabbit@${hostname}" \
  -v "\${BASE}/data":/var/lib/rabbitmq \
  -v "\${BASE}/log":/var/log/rabbitmq \
  -v "\${BASE}/conf/rabbitmq.conf":/etc/rabbitmq/rabbitmq.conf:ro \
  --ulimit nofile=65536:65536 \
  rabbitmq:3.12-management

sleep 5

# Vérifier que RabbitMQ est démarré
if docker ps | grep -q "rabbitmq"; then
    echo "  ✓ RabbitMQ démarré"
else
    echo "  ✗ Échec du démarrage RabbitMQ"
    docker logs rabbitmq --tail 20 2>&1 || true
    exit 1
fi

# Attendre que RabbitMQ soit prêt
echo "  Attente que RabbitMQ soit prêt (15 secondes)..."
sleep 15

# Vérifier que RabbitMQ répond
if docker exec rabbitmq rabbitmqctl status >/dev/null 2>&1; then
    echo "  ✓ RabbitMQ répond correctement"
else
    echo "  ⚠ RabbitMQ ne répond pas encore (peut être normal au démarrage)"
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "RabbitMQ déployé avec succès sur ${hostname}"
    else
        log_error "Échec du déploiement de RabbitMQ sur ${hostname}"
        exit 1
    fi
    echo ""
done

# Attendre que tous les nœuds soient prêts
log_info "Attente que tous les nœuds soient prêts (30 secondes)..."
sleep 30

# Configurer le cluster (queue-01 est le nœud principal)
FIRST_NODE="${RABBITMQ_NODES[0]}"
FIRST_IP="${RABBITMQ_IPS[0]}"

log_info "--------------------------------------------------------------"
log_info "Configuration du cluster (nœud principal: ${FIRST_NODE})"
log_info "--------------------------------------------------------------"

# Attendre que RabbitMQ soit complètement démarré sur queue-01
log_info "Attente que RabbitMQ soit prêt sur ${FIRST_NODE} (20 secondes supplémentaires)..."
sleep 20

# Vérifier que RabbitMQ répond
MAX_RETRIES=10
RETRY=0
while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
    if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${FIRST_IP}" \
        "docker exec rabbitmq rabbitmqctl status >/dev/null 2>&1"; then
        log_success "RabbitMQ prêt sur ${FIRST_NODE}"
        break
    fi
    ((RETRY++))
    sleep 3
done

if [[ ${RETRY} -eq ${MAX_RETRIES} ]]; then
    log_error "RabbitMQ ne répond pas sur ${FIRST_NODE} après ${MAX_RETRIES} tentatives"
    log_info "Vérification des logs..."
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${FIRST_IP}" "docker logs rabbitmq --tail 30 2>&1" || true
    exit 1
fi

# Réinitialiser queue-01 (nœud principal)
ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${FIRST_IP}" bash <<EOF
docker exec rabbitmq rabbitmqctl stop_app
docker exec rabbitmq rabbitmqctl reset
docker exec rabbitmq rabbitmqctl start_app
EOF

if [ $? -eq 0 ]; then
    log_success "${FIRST_NODE} configuré comme nœud principal"
else
    log_error "Échec de la configuration du nœud principal"
    exit 1
fi

# Joindre les autres nœuds au cluster
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    if [[ "${hostname}" == "${FIRST_NODE}" ]]; then
        continue
    fi
    
    log_info "Joindre ${hostname} au cluster..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
docker exec rabbitmq rabbitmqctl stop_app
docker exec rabbitmq rabbitmqctl reset
docker exec rabbitmq rabbitmqctl join_cluster rabbit@${FIRST_NODE}
docker exec rabbitmq rabbitmqctl start_app
EOF

    if [ $? -eq 0 ]; then
        log_success "${hostname} joint au cluster"
    else
        log_error "Échec du join de ${hostname} au cluster"
        exit 1
    fi
    sleep 5
done

# Attendre la stabilisation du cluster
log_info "Attente de la stabilisation du cluster (15 secondes)..."
sleep 15

# Vérifier le statut du cluster
log_info "Vérification du statut du cluster..."

for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    CLUSTER_STATUS=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null | grep -c 'running_nodes' || echo '0'")
    
    if [[ "${CLUSTER_STATUS}" == "1" ]]; then
        log_success "${hostname}: Cluster opérationnel"
    else
        log_warning "${hostname}: Statut cluster à vérifier"
    fi
done

# Activer les Quorum Queues (déjà dans la config, mais on recharge)
log_info "Activation des Quorum Queues..."

for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "docker exec rabbitmq rabbitmqctl reload_config 2>/dev/null || true" >/dev/null 2>&1
done

log_success "Quorum Queues activées"

echo ""
echo "=============================================================="
log_success "✅ Déploiement du cluster RabbitMQ terminé !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœuds déployés: ${#RABBITMQ_NODES[@]}"
log_info "  - Cluster: Configuré"
log_info "  - Quorum Queues: Activées"
log_info ""
log_info "Prochaine étape: Configurer HAProxy"
log_info "  ./05_rmq_03_configure_haproxy.sh ${TSV_FILE}"
echo ""

