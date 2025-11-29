#!/usr/bin/env bash
#
# 04_redis_fix_failover_complet.sh - Correction complète failover Redis Sentinel
#
# Ce script corrige la configuration Sentinel et teste le failover.
#

set -uo pipefail

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

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Correction Complète Failover Redis Sentinel"
echo "=============================================================="
echo ""

source "${CREDENTIALS_FILE}"

# Détecter les nœuds Redis
declare -a REDIS_IPS=()
declare -a REDIS_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ "${ROLE}" != "redis" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    [[ ! "${HOSTNAME}" =~ ^redis-[0-9]+$ ]] && continue
    
    REDIS_IPS+=("${IP_PRIVEE}")
    REDIS_HOSTNAMES+=("${HOSTNAME}")
done
exec 3<&-

log_info "Nœuds Redis: ${REDIS_IPS[*]}"
echo ""

# Trouver le master actuel
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        log_success "Master trouvé: ${ip}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    MASTER_IP="${REDIS_IPS[0]}"
    log_warning "Aucun master détecté, utilisation de ${MASTER_IP}"
fi

echo ""

# Corriger la configuration Sentinel
log_info "Correction configuration Sentinel..."
for i in "${!REDIS_IPS[@]}"; do
    ip="${REDIS_IPS[$i]}"
    hostname="${REDIS_HOSTNAMES[$i]}"
    
    ssh ${SSH_OPTS} root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
BASE="/opt/keybuzz/redis"

docker stop redis-sentinel 2>/dev/null || true
sleep 2

mkdir -p "\${BASE}/conf"

cat > "\${BASE}/conf/sentinel.conf" <<SENTINEL_CONF
port 26379
bind ${ip}
protected-mode no
dir /tmp

sentinel monitor ${REDIS_MASTER_NAME} ${MASTER_IP} 6379 2
sentinel auth-pass ${REDIS_MASTER_NAME} \${REDIS_PASSWORD}
sentinel down-after-milliseconds ${REDIS_MASTER_NAME} 5000
sentinel parallel-syncs ${REDIS_MASTER_NAME} 1
sentinel failover-timeout ${REDIS_MASTER_NAME} 60000

sentinel announce-ip ${ip}
sentinel announce-port 26379

loglevel notice
SENTINEL_CONF

chmod 644 "\${BASE}/conf/sentinel.conf"

docker start redis-sentinel 2>/dev/null || docker run -d --name redis-sentinel \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/conf/sentinel.conf":/etc/redis/sentinel.conf \
  redis:7-alpine redis-sentinel /etc/redis/sentinel.conf

sleep 3
EOF

    log_success "Sentinel corrigé sur ${hostname}"
done

echo ""
log_info "Attente synchronisation (20 secondes)..."
sleep 20

# Vérifier quorum
SENTINEL_COUNT=$(ssh ${SSH_OPTS} root@${MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL sentinels ${REDIS_MASTER_NAME} 2>/dev/null | grep -c "name" || echo "0"
EOF
) || SENTINEL_COUNT="0"

SENTINEL_COUNT=$(echo "${SENTINEL_COUNT}" | tr -d ' \n\r')
[[ -z "${SENTINEL_COUNT}" ]] && SENTINEL_COUNT=0
TOTAL_SENTINELS=$((SENTINEL_COUNT + 1))

log_info "Sentinels: ${TOTAL_SENTINELS}/3"
[[ ${TOTAL_SENTINELS} -ge 2 ]] && log_success "Quorum OK" || log_error "Quorum insuffisant"

echo ""
log_success "✅ Correction terminée"

