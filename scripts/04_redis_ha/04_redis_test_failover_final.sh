#!/usr/bin/env bash
#
# 04_redis_test_failover_final.sh - Test final failover Redis avec détection correcte
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

echo "=== Test Failover Redis Sentinel ==="
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
        echo "Master actuel: ${MASTER_IP}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    echo "ERREUR: Aucun master"
    exit 1
fi

echo ""
echo "Arrêt du master ${MASTER_IP}..."
ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "docker stop redis" || true

echo "Attente 90 secondes..."
sleep 90

# Vérifier nouveau master (essayer tous les Sentinels et toutes les méthodes)
NEW_MASTER_IP=""
for sentinel_ip in "${REDIS_IPS[@]}"; do
    # Méthode 1: SENTINEL get-master-addr-by-name
    DETECTED=$(ssh -o StrictHostKeyChecking=no root@${sentinel_ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || DETECTED=""
    
    if [[ -n "${DETECTED}" ]] && [[ "${DETECTED}" != "${MASTER_IP}" ]]; then
        NEW_MASTER_IP="${DETECTED}"
        echo "Nouveau master détecté via Sentinel ${sentinel_ip}: ${NEW_MASTER_IP}"
        break
    fi
    
    # Méthode 2: SENTINEL masters (parser la sortie)
    if [[ -z "${NEW_MASTER_IP}" ]]; then
        DETECTED=$(ssh -o StrictHostKeyChecking=no root@${sentinel_ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis-sentinel redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" SENTINEL masters 2>/dev/null | grep -A 20 "name ${REDIS_MASTER_NAME}" | grep "^ip:" | cut -d: -f2 | tr -d ' ' || echo ""
EOF
) || DETECTED=""
        
        if [[ -n "${DETECTED}" ]] && [[ "${DETECTED}" != "${MASTER_IP}" ]]; then
            NEW_MASTER_IP="${DETECTED}"
            echo "Nouveau master détecté via SENTINEL masters ${sentinel_ip}: ${NEW_MASTER_IP}"
            break
        fi
    fi
done

# Méthode 3: Vérifier directement sur chaque nœud Redis
if [[ -z "${NEW_MASTER_IP}" ]]; then
    for ip in "${REDIS_IPS[@]}"; do
        if [[ "${ip}" != "${MASTER_IP}" ]]; then
            ROLE=$(ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
            
            if [[ "${ROLE}" == "master" ]]; then
                NEW_MASTER_IP="${ip}"
                echo "Nouveau master détecté directement sur ${ip}"
                break
            fi
        fi
    done
fi

if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
    # Vérifier rôle
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${NEW_MASTER_IP} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${NEW_MASTER_IP} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        echo "SUCCESS: Failover réussi ! Nouveau master: ${NEW_MASTER_IP}"
        exit 0
    else
        echo "ERREUR: Nouveau master détecté mais rôle: ${ROLE}"
        exit 1
    fi
else
    echo "ERREUR: Failover échoué - Aucun nouveau master détecté"
    exit 1
fi

