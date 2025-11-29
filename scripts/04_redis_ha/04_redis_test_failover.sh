#!/usr/bin/env bash
#
# 04_redis_test_failover.sh - Test du failover Redis Sentinel
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
echo " [KeyBuzz] Test Failover Redis Sentinel"
echo "=============================================================="
echo ""

source "${CREDENTIALS_FILE}"

# Détecter les nœuds Redis
declare -a REDIS_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ "${ROLE}" != "redis" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    [[ ! "${HOSTNAME}" =~ ^redis-[0-9]+$ ]] && continue
    
    REDIS_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

# Trouver le master
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        log_success "Master actuel: ${ip}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    log_error "Aucun master trouvé"
    exit 1
fi

echo ""

# Vérifier l'état Sentinel avant
log_info "État Sentinel avant failover:"
for ip in "${REDIS_IPS[@]}"; do
    MASTER_DETECTED=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || MASTER_DETECTED=""
    
    log_info "  ${ip}: Master détecté = ${MASTER_DETECTED}"
done

echo ""

# Arrêter le master
log_warning "Arrêt du master Redis sur ${MASTER_IP}..."
ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true

log_info "Attente du failover (90 secondes)..."
sleep 90

# Vérifier le nouveau master
NEW_MASTER_IP=""
for attempt in {1..6}; do
    log_info "Vérification failover (tentative ${attempt}/6)..."
    
    NEW_MASTER_IP=$(ssh ${SSH_OPTS} root@${REDIS_IPS[0]} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || NEW_MASTER_IP=""
    
    if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
        # Vérifier le rôle
        ROLE=$(ssh ${SSH_OPTS} root@${NEW_MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
        
        if [[ "${ROLE}" == "master" ]]; then
            log_success "✅ Failover réussi ! Nouveau master: ${NEW_MASTER_IP}"
            break
        else
            log_warning "Nouveau master détecté mais rôle incorrect: ${ROLE}"
        fi
    fi
    
    if [[ ${attempt} -lt 6 ]]; then
        sleep 15
    fi
done

if [[ -z "${NEW_MASTER_IP}" ]] || [[ "${NEW_MASTER_IP}" == "${MASTER_IP}" ]]; then
    log_error "✗ Failover échoué"
    log_info "Logs Sentinel:"
    for ip in "${REDIS_IPS[@]}"; do
        if [[ "${ip}" != "${MASTER_IP}" ]]; then
            log_info "  ${ip}:"
            ssh ${SSH_OPTS} root@${ip} "docker logs redis-sentinel --tail 20 2>&1 | grep -E 'failover|master|quorum|vote'" || true
        fi
    done
else
    log_success "✅ Failover validé !"
fi

# Redémarrer le master
log_info "Redémarrage du master Redis..."
ssh ${SSH_OPTS} root@${MASTER_IP} "docker start redis" || true
sleep 20

echo ""
log_success "✅ Test terminé"

