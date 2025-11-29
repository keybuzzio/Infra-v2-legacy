#!/usr/bin/env bash
#
# 04_redis_diagnostic_sentinel.sh - Diagnostic complet Sentinel
#

set -uo pipefail

TSV_FILE="${1:-/opt/keybuzz-installer/servers.tsv}"
CREDENTIALS_FILE="/opt/keybuzz-installer/credentials/redis.env"

source "${CREDENTIALS_FILE}"

declare -a REDIS_IPS=()

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ "${ROLE}" != "redis" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    [[ ! "${HOSTNAME}" =~ ^redis-[0-9]+$ ]] && continue
    
    REDIS_IPS+=("${IP_PRIVEE}")
done < "${TSV_FILE}"

echo "=== Diagnostic Sentinel ==="
echo ""

# Vérifier l'état Sentinel
for ip in "${REDIS_IPS[@]}"; do
    echo "--- Sentinel ${ip} ---"
    
    # État Sentinel
    echo "État:"
    ssh -o StrictHostKeyChecking=no root@${ip} "docker ps | grep redis-sentinel || echo 'Non actif'" 2>&1
    
    # Master détecté
    echo "Master détecté:"
    MASTER=$(ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo "non détecté"
EOF
) || MASTER="erreur"
    echo "  ${MASTER}"
    
    # Info Sentinel
    echo "Info Sentinel:"
    ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" INFO Sentinel 2>/dev/null | grep -E "sentinel_masters|sentinel_tilt|sentinel_running_scripts" || echo "  erreur"
EOF
    
    # Logs récents
    echo "Logs récents (failover/master/quorum):"
    ssh -o StrictHostKeyChecking=no root@${ip} "docker logs redis-sentinel --tail 30 2>&1 | grep -iE 'failover|master|quorum|vote|down|switch' || echo '  aucun'" 2>&1 | head -10
    
    echo ""
done

echo "=== Test Failover ==="
echo ""

# Trouver master
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        echo "Master: ${MASTER_IP}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    echo "ERREUR: Aucun master"
    exit 1
fi

echo "Arrêt du master..."
ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "docker stop redis" || true

echo "Attente 90 secondes..."
sleep 90

# Vérifier nouveau master
NEW_MASTER=$(ssh -o StrictHostKeyChecking=no root@${REDIS_IPS[0]} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || NEW_MASTER=""

if [[ -n "${NEW_MASTER}" ]] && [[ "${NEW_MASTER}" != "${MASTER_IP}" ]]; then
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${NEW_MASTER} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${NEW_MASTER} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        echo "SUCCESS: Failover réussi ! Nouveau master: ${NEW_MASTER}"
    else
        echo "ERREUR: Nouveau master détecté mais rôle: ${ROLE}"
    fi
else
    echo "ERREUR: Failover échoué"
    echo "Logs Sentinel après failover:"
    for ip in "${REDIS_IPS[@]}"; do
        if [[ "${ip}" != "${MASTER_IP}" ]]; then
            echo "  ${ip}:"
            ssh -o StrictHostKeyChecking=no root@${ip} "docker logs redis-sentinel --tail 40 2>&1" | grep -iE "failover|master|quorum|vote|down|switch|error" || echo "    aucun log pertinent"
        fi
    done
fi

# Redémarrer
echo "Redémarrage du master..."
ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "docker start redis" || true
sleep 15

echo "Diagnostic terminé"

