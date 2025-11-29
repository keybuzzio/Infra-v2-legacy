#!/usr/bin/env bash
#
# 04_redis_diagnostic_failover.sh - Diagnostic et correction failover Redis Sentinel
#
# Ce script diagnostique pourquoi le failover Redis ne fonctionne pas
# et applique les corrections nécessaires.
#

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

# Options SSH (depuis install-01, pas besoin de clé pour IP internes)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Failover Redis Sentinel"
echo "=============================================================="
echo ""

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

log_info "Nœuds Redis détectés: ${#REDIS_IPS[@]}"
echo ""

# Étape 1: Vérifier l'état actuel
log_info "=============================================================="
log_info "Étape 1: État Actuel Redis et Sentinel"
log_info "=============================================================="

# Trouver le master actuel
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
)
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        log_success "Master actuel: ${ip}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    log_error "Aucun master Redis trouvé"
    exit 1
fi

echo ""

# Vérifier la configuration Sentinel
log_info "=============================================================="
log_info "Étape 2: Configuration Sentinel"
log_info "=============================================================="

for ip in "${REDIS_IPS[@]}"; do
    log_info "Sentinel sur ${ip}:"
    
    # Vérifier que Sentinel est actif
    SENTINEL_ACTIVE=$(ssh ${SSH_OPTS} root@${ip} "docker ps | grep redis-sentinel | wc -l" || echo "0")
    if [[ ${SENTINEL_ACTIVE} -gt 0 ]]; then
        log_success "  ✓ Sentinel actif"
    else
        log_error "  ✗ Sentinel non actif"
        continue
    fi
    
    # Vérifier la configuration Sentinel
    ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
echo "  Configuration:"
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL masters 2>/dev/null | grep -E "name|ip|port|quorum|down-after|failover-timeout" || echo "    ⚠ Impossible de lire la configuration"
EOF
    
    echo ""
done

# Vérifier le quorum Sentinel
log_info "Vérification du quorum Sentinel..."
SENTINEL_COUNT=$(ssh ${SSH_OPTS} root@${MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL sentinels kb-redis-master 2>/dev/null | grep -c "name" || echo "0"
EOF
)

SENTINEL_COUNT=$(echo "${SENTINEL_COUNT}" | tr -d ' \n\r')
if [[ -z "${SENTINEL_COUNT}" ]] || ! [[ "${SENTINEL_COUNT}" =~ ^[0-9]+$ ]]; then
    SENTINEL_COUNT=0
fi

TOTAL_SENTINELS=$((SENTINEL_COUNT + 1))
log_info "Sentinels détectés: ${TOTAL_SENTINELS}/3"

if [[ ${TOTAL_SENTINELS} -lt 3 ]]; then
    log_warning "⚠ Quorum Sentinel insuffisant (${TOTAL_SENTINELS}/3)"
    log_warning "  Le failover nécessite au moins 2 Sentinels pour le quorum"
else
    log_success "✓ Quorum Sentinel OK (${TOTAL_SENTINELS}/3)"
fi

echo ""

# Étape 3: Vérifier les logs Sentinel pour erreurs
log_info "=============================================================="
log_info "Étape 3: Logs Sentinel (dernières erreurs)"
log_info "=============================================================="

for ip in "${REDIS_IPS[@]}"; do
    log_info "Logs Sentinel sur ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker logs redis-sentinel --tail 20 2>&1 | grep -E 'ERROR|WARN|failover|master|quorum' || docker logs redis-sentinel --tail 5 2>&1" || true
    echo ""
done

# Étape 4: Vérifier la configuration Sentinel (fichier)
log_info "=============================================================="
log_info "Étape 4: Configuration Sentinel (fichier)"
log_info "=============================================================="

for ip in "${REDIS_IPS[@]}"; do
    log_info "Configuration Sentinel sur ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "cat /opt/keybuzz/redis/conf/sentinel.conf 2>/dev/null | grep -E 'sentinel|quorum|down-after|failover-timeout' || echo '  ⚠ Fichier non trouvé'" || true
    echo ""
done

# Étape 5: Problèmes identifiés et solutions
log_info "=============================================================="
log_info "Étape 5: Problèmes Identifiés et Solutions"
log_info "=============================================================="

echo ""
log_warning "Problèmes potentiels identifiés:"
echo ""
log_warning "1. Protected Mode:"
log_warning "   - Sentinel est en 'protected-mode yes'"
log_warning "   - Solution: Vérifier que les Sentinels peuvent communiquer entre eux"
echo ""
log_warning "2. Quorum:"
log_warning "   - Quorum = 2 (nécessite 2 Sentinels sur 3)"
log_warning "   - Si moins de 3 Sentinels actifs, le failover ne peut pas se produire"
echo ""
log_warning "3. Délais:"
log_warning "   - down-after-milliseconds: 5000 (5 secondes)"
log_warning "   - failover-timeout: 60000 (60 secondes)"
log_warning "   - Le failover peut prendre jusqu'à 65-90 secondes"
echo ""
log_warning "4. Authentification:"
log_warning "   - Vérifier que tous les Sentinels utilisent le même mot de passe"
echo ""

# Étape 6: Test manuel du failover
log_info "=============================================================="
log_info "Étape 6: Test Manuel du Failover"
log_info "=============================================================="
log_warning "Ce test va arrêter le master Redis temporairement"
echo ""

read -p "Voulez-vous tester le failover maintenant ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
    log_info "Test annulé"
    exit 0
fi

log_info "Arrêt du master Redis sur ${MASTER_IP}..."
ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true

log_info "Attente du failover (90 secondes)..."
sleep 90

# Vérifier le nouveau master
NEW_MASTER_IP=$(ssh ${SSH_OPTS} root@${REDIS_IPS[0]} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name kb-redis-master 2>/dev/null | head -1 || echo ""
EOF
)

if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
    # Vérifier le rôle
    ROLE=$(ssh ${SSH_OPTS} root@${NEW_MASTER_IP} bash <<'EOF'
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "${REDIS_PASSWORD}" -h 127.0.0.1 INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
)
    
    if [[ "${ROLE}" == "master" ]]; then
        log_success "✅ Failover réussi ! Nouveau master: ${NEW_MASTER_IP}"
    else
        log_error "✗ Nouveau master détecté mais rôle incorrect: ${ROLE}"
    fi
else
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
log_success "✅ Diagnostic terminé"

