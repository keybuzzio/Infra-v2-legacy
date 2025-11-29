#!/usr/bin/env bash
#
# 04_redis_fix_failover.sh - Correction configuration Redis Sentinel pour failover
#
# Ce script corrige la configuration Sentinel pour garantir le failover automatique.
#

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

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Correction Failover Redis Sentinel"
echo "=============================================================="
echo ""

# Charger les credentials
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

# Détecter les nœuds Redis
declare -a REDIS_IPS=()
declare -a REDIS_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "redis" ]]; then
        continue
    fi
    
    if [[ -n "${IP_PRIVEE}" ]] && [[ "${HOSTNAME}" =~ ^redis-[0-9]+$ ]]; then
        REDIS_IPS+=("${IP_PRIVEE}")
        REDIS_HOSTNAMES+=("${HOSTNAME}")
    fi
done
exec 3<&-

if [[ ${#REDIS_IPS[@]} -lt 3 ]]; then
    log_error "Moins de 3 nœuds Redis trouvés: ${#REDIS_IPS[@]}"
    exit 1
fi

# Trouver le master actuel
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        log_success "Master actuel: ${ip}"
        break
    fi
done

# Si aucun master trouvé, utiliser le premier nœud
if [[ -z "${MASTER_IP}" ]]; then
    MASTER_IP="${REDIS_IPS[0]}"
    log_warning "Aucun master détecté, utilisation de ${MASTER_IP} par défaut"
fi

echo ""

# Étape 1: Corriger la configuration Sentinel
log_info "=============================================================="
log_info "Étape 1: Correction Configuration Sentinel"
log_info "=============================================================="

for i in "${!REDIS_IPS[@]}"; do
    ip="${REDIS_IPS[$i]}"
    hostname="${REDIS_HOSTNAMES[$i]}"
    
    log_info "Correction Sentinel sur ${hostname} (${ip})..."
    
    ssh ${SSH_OPTS} root@${ip} bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
BASE="/opt/keybuzz/redis"

# Arrêter Sentinel
docker stop redis-sentinel 2>/dev/null || true
sleep 2

# Créer le répertoire de configuration si nécessaire
mkdir -p "\${BASE}/conf"

# Générer la nouvelle configuration Sentinel optimisée
cat > "\${BASE}/conf/sentinel.conf" <<SENTINEL_CONF
# Sentinel Configuration - Optimisée pour failover
# Hostname: ${hostname}
# IP: ${ip}
# Généré: $(date '+%Y-%m-%d %H:%M:%S')

port 26379
bind ${ip}
protected-mode no
dir /tmp

# Monitor master
sentinel monitor ${REDIS_MASTER_NAME} ${MASTER_IP} 6379 2
sentinel auth-pass ${REDIS_MASTER_NAME} \${REDIS_PASSWORD}

# Délais optimisés pour failover rapide mais fiable
sentinel down-after-milliseconds ${REDIS_MASTER_NAME} 5000
sentinel parallel-syncs ${REDIS_MASTER_NAME} 1
sentinel failover-timeout ${REDIS_MASTER_NAME} 60000

# Configuration réseau pour communication entre Sentinels
sentinel announce-ip ${ip}
sentinel announce-port 26379

# Logging
loglevel notice
logfile ""

# Désactiver les notifications (optionnel)
# sentinel notification-script ${REDIS_MASTER_NAME} /path/to/script.sh
SENTINEL_CONF

chmod 644 "\${BASE}/conf/sentinel.conf"

# Redémarrer Sentinel
docker start redis-sentinel 2>/dev/null || docker run -d --name redis-sentinel \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/conf/sentinel.conf":/etc/redis/sentinel.conf \
  redis:7-alpine redis-sentinel /etc/redis/sentinel.conf

sleep 3

# Vérifier que Sentinel est démarré
if docker ps | grep -q "redis-sentinel"; then
    echo "  ✓ Sentinel redémarré"
else
    echo "  ✗ Échec du redémarrage Sentinel"
    docker logs redis-sentinel --tail 20 2>&1 || true
    exit 1
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "Sentinel corrigé sur ${hostname}"
    else
        log_error "Échec de la correction sur ${hostname}"
    fi
    echo ""
done

# Étape 2: Attendre que les Sentinels se synchronisent
log_info "=============================================================="
log_info "Étape 2: Synchronisation Sentinels"
log_info "=============================================================="

log_info "Attente de la synchronisation (15 secondes)..."
sleep 15

# Vérifier que tous les Sentinels voient le master
log_info "Vérification de la synchronisation..."
SYNC_OK=true

for ip in "${REDIS_IPS[@]}"; do
    MASTER_DETECTED=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || MASTER_DETECTED=""
    
    if [[ -n "${MASTER_DETECTED}" ]]; then
        log_success "  ${ip}: Master détecté (${MASTER_DETECTED})"
    else
        log_warning "  ${ip}: Master non détecté"
        SYNC_OK=false
    fi
done

if [[ "${SYNC_OK}" == "true" ]]; then
    log_success "✓ Tous les Sentinels sont synchronisés"
else
    log_warning "⚠ Certains Sentinels ne sont pas synchronisés"
fi

echo ""

# Étape 3: Vérifier le quorum
log_info "=============================================================="
log_info "Étape 3: Vérification Quorum"
log_info "=============================================================="

SENTINEL_COUNT=$(ssh ${SSH_OPTS} root@${MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL sentinels ${REDIS_MASTER_NAME} 2>/dev/null | grep -c "name" || echo "0"
EOF
) || SENTINEL_COUNT="0"

SENTINEL_COUNT=$(echo "${SENTINEL_COUNT}" | tr -d ' \n\r')
if [[ -z "${SENTINEL_COUNT}" ]] || ! [[ "${SENTINEL_COUNT}" =~ ^[0-9]+$ ]]; then
    SENTINEL_COUNT=0
fi

TOTAL_SENTINELS=$((SENTINEL_COUNT + 1))
log_info "Sentinels détectés: ${TOTAL_SENTINELS}/3"

if [[ ${TOTAL_SENTINELS} -ge 2 ]]; then
    log_success "✓ Quorum atteint (${TOTAL_SENTINELS}/3, minimum 2 requis)"
else
    log_error "✗ Quorum insuffisant (${TOTAL_SENTINELS}/3, minimum 2 requis)"
    log_warning "Le failover ne pourra pas se produire sans quorum"
fi

echo ""

# Étape 4: Test du failover
log_info "=============================================================="
log_info "Étape 4: Test du Failover"
log_info "=============================================================="
log_warning "Ce test va arrêter le master Redis temporairement"
echo ""

read -p "Voulez-vous tester le failover maintenant ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    log_info "Test annulé"
    echo ""
    log_success "✅ Correction terminée (sans test)"
    exit 0
fi

log_info "Arrêt du master Redis sur ${MASTER_IP}..."
ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true

log_info "Attente du failover (90 secondes - down-after:5s, failover-timeout:60s)..."
sleep 90

# Vérifier le nouveau master
NEW_MASTER_IP=""
for attempt in {1..5}; do
    log_info "Vérification failover (tentative ${attempt}/5)..."
    
    NEW_MASTER_IP=$(ssh ${SSH_OPTS} root@${REDIS_IPS[0]} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || NEW_MASTER_IP=""
    
    if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
        # Vérifier le rôle
        ROLE=$(ssh ${SSH_OPTS} root@${NEW_MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
        
        if [[ "${ROLE}" == "master" ]]; then
            log_success "✅ Failover réussi ! Nouveau master: ${NEW_MASTER_IP}"
            break
        fi
    fi
    
    if [[ ${attempt} -lt 5 ]]; then
        sleep 15
    fi
done

if [[ -z "${NEW_MASTER_IP}" ]] || [[ "${NEW_MASTER_IP}" == "${MASTER_IP}" ]]; then
    log_error "✗ Failover échoué - Aucun nouveau master détecté"
    log_info "Vérification des logs Sentinel..."
    for ip in "${REDIS_IPS[@]}"; do
        if [[ "${ip}" != "${MASTER_IP}" ]]; then
            log_info "Logs Sentinel sur ${ip}:"
            ssh ${SSH_OPTS} root@${ip} "docker logs redis-sentinel --tail 30 2>&1" || true
            echo ""
        fi
    done
fi

# Redémarrer le master
log_info "Redémarrage du master Redis..."
ssh ${SSH_OPTS} root@${MASTER_IP} "docker start redis" || true
sleep 15

echo ""
log_success "✅ Correction terminée"

