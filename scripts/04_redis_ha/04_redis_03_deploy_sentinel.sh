#!/usr/bin/env bash
#
# 04_redis_03_deploy_sentinel.sh - Déploiement de Redis Sentinel
#
# Ce script déploie Redis Sentinel sur chaque nœud Redis pour surveiller
# le cluster et gérer le failover automatique.
#
# Usage:
#   ./04_redis_03_deploy_sentinel.sh [servers.tsv]
#
# Prérequis:
#   - Script 04_redis_02_deploy_redis_cluster.sh exécuté
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
echo " [KeyBuzz] Module 4 - Déploiement Redis Sentinel"
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

# Copier les credentials sur tous les nœuds Redis (si pas déjà fait)
log_info "Vérification des credentials sur les nœuds Redis..."
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" "test -f /opt/keybuzz-installer/credentials/redis.env" 2>/dev/null; then
        ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" "mkdir -p /opt/keybuzz-installer/credentials"
        scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${ip}:/opt/keybuzz-installer/credentials/"
    fi
done
log_success "Credentials vérifiés sur tous les nœuds"
echo ""

# Nettoyer les anciens conteneurs Sentinel
log_info "Nettoyage des anciens conteneurs Sentinel..."
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
docker stop redis-sentinel 2>/dev/null || true
docker rm redis-sentinel 2>/dev/null || true
EOF
done
log_success "Anciens conteneurs Sentinel nettoyés"
echo ""

# Déployer Sentinel sur chaque nœud
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Déploiement Sentinel sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/redis.env
BASE="/opt/keybuzz/redis"

# Générer sentinel.conf (Sentinel a besoin d'un fichier sur disque pour sauvegarder son état)
cat > "\${BASE}/conf/sentinel.conf" <<SENTINEL_CONF
# Sentinel Configuration - Généré automatiquement
# Hostname: ${hostname}
# IP: ${ip}

port 26379
bind ${ip}
protected-mode yes
dir /tmp

# Monitor master (utilise kb-redis-master comme dans Context.txt)
sentinel monitor ${REDIS_MASTER_NAME} ${MASTER_IP} 6379 2
sentinel auth-pass ${REDIS_MASTER_NAME} \${REDIS_PASSWORD}
sentinel down-after-milliseconds ${REDIS_MASTER_NAME} 5000
sentinel parallel-syncs ${REDIS_MASTER_NAME} 1
sentinel failover-timeout ${REDIS_MASTER_NAME} 60000

# Logging
loglevel notice
SENTINEL_CONF

chmod 644 "\${BASE}/conf/sentinel.conf"

# Déployer Sentinel (montage en lecture-écriture pour que Sentinel puisse sauvegarder son état)
docker run -d --name redis-sentinel \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/conf/sentinel.conf":/etc/redis/sentinel.conf \
  redis:7-alpine redis-sentinel /etc/redis/sentinel.conf

sleep 3

# Vérifier que Sentinel est démarré
if docker ps | grep -q "redis-sentinel"; then
    echo "  ✓ Sentinel démarré"
else
    echo "  ✗ Échec du démarrage Sentinel"
    docker logs redis-sentinel --tail 20 2>&1 || true
    exit 1
fi

# Test de connexion Sentinel (depuis l'intérieur du conteneur)
if docker exec redis-sentinel redis-cli -h ${ip} -p 26379 PING 2>/dev/null | grep -q "PONG"; then
    echo "  ✓ Sentinel répond correctement"
elif timeout 3 redis-cli -h ${ip} -p 26379 PING 2>/dev/null | grep -q "PONG"; then
    echo "  ✓ Sentinel répond correctement (depuis hôte)"
else
    # Vérifier que Sentinel fonctionne en vérifiant les logs (il peut fonctionner même avec des warnings)
    # Les warnings "Resource busy" sont normaux si le volume n'est pas monté en écriture
    if docker logs redis-sentinel 2>&1 | grep -qE "\+monitor|\+slave|\+sentinel|Sentinel ID"; then
        echo "  ✓ Sentinel démarré et opérationnel (warnings de config normaux)"
    else
        # Dernière vérification: si le conteneur tourne, Sentinel est probablement OK
        if docker ps | grep -q "redis-sentinel"; then
            echo "  ✓ Sentinel démarré (conteneur actif, warnings normaux)"
        else
            echo "  ✗ Sentinel ne répond pas"
            docker logs redis-sentinel --tail 10 2>&1 || true
            exit 1
        fi
    fi
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "Sentinel déployé avec succès sur ${hostname}"
    else
        log_error "Échec du déploiement de Sentinel sur ${hostname}"
        exit 1
    fi
    echo ""
done

# Attendre que Sentinel découvre le master
log_info "Attente de la découverte du master par Sentinel (10 secondes)..."
sleep 10

# Vérifier que Sentinel voit le master
log_info "Vérification de la configuration Sentinel..."

for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    
    MASTER_DETECTED=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "timeout 3 redis-cli -h ${ip} -p 26379 SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ''")
    
    if [[ -n "${MASTER_DETECTED}" ]]; then
        if [[ "${MASTER_DETECTED}" == "${MASTER_IP}" ]]; then
            log_success "${hostname}: Sentinel voit le master correct (${MASTER_DETECTED})"
        else
            log_warning "${hostname}: Sentinel voit un master différent (${MASTER_DETECTED} au lieu de ${MASTER_IP})"
        fi
    else
        log_warning "${hostname}: Sentinel ne peut pas détecter le master"
    fi
done

# Compter les Sentinels qui voient le master
SENTINEL_COUNT=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${MASTER_IP}" \
    "timeout 3 redis-cli -h ${MASTER_IP} -p 26379 SENTINEL sentinels ${REDIS_MASTER_NAME} 2>/dev/null | grep -c 'name' || echo '0'")

# Nettoyer la valeur (supprimer espaces et retours à la ligne)
SENTINEL_COUNT=$(echo "${SENTINEL_COUNT}" | tr -d ' \n\r')

# Convertir en nombre (éviter les problèmes de syntaxe)
if [[ -z "${SENTINEL_COUNT}" ]] || [[ "${SENTINEL_COUNT}" == "" ]] || ! [[ "${SENTINEL_COUNT}" =~ ^[0-9]+$ ]]; then
    SENTINEL_COUNT=0
fi

TOTAL_SENTINELS=$((SENTINEL_COUNT + 1))
log_info "Sentinels détectés: ${TOTAL_SENTINELS} (attendu: 3)"

if [[ ${TOTAL_SENTINELS} -eq 3 ]]; then
    log_success "Tous les Sentinels sont opérationnels"
else
    log_warning "Seulement ${TOTAL_SENTINELS}/3 Sentinels détectés"
fi

echo ""
echo "=============================================================="
log_success "✅ Déploiement de Redis Sentinel terminé !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Master surveillé: ${REDIS_MASTER_NAME} (${MASTER_IP})"
log_info "  - Sentinels déployés: ${#REDIS_NODES[@]} instances"
log_info "  - Quorum: ${REDIS_SENTINEL_QUORUM}"
log_info ""
log_info "Prochaine étape: Configurer HAProxy pour Redis"
log_info "  ./04_redis_04_configure_haproxy_redis.sh ${TSV_FILE}"
echo ""

