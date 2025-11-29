#!/usr/bin/env bash
#
# 04_redis_verif_et_test.sh - Vérification et test failover Redis
#

set -uo pipefail

TSV_FILE="${1:-/opt/keybuzz-installer/servers.tsv}"
CREDENTIALS_FILE="/opt/keybuzz-installer/credentials/redis.env"

source "${CREDENTIALS_FILE}"

# Détecter les nœuds Redis
declare -a REDIS_IPS=()

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ "${ROLE}" != "redis" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    [[ ! "${HOSTNAME}" =~ ^redis-[0-9]+$ ]] && continue
    
    REDIS_IPS+=("${IP_PRIVEE}")
done < "${TSV_FILE}"

echo "Nœuds Redis: ${REDIS_IPS[*]}"
echo ""

# Vérifier l'état de Redis
echo "=== État Redis ==="
for ip in "${REDIS_IPS[@]}"; do
    echo -n "${ip}: "
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo "non accessible"
EOF
) || ROLE="erreur"
    echo "${ROLE}"
done

echo ""

# Trouver le master
MASTER_IP=""
for ip in "${REDIS_IPS[@]}"; do
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${ip} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${ip} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        echo "Master trouvé: ${MASTER_IP}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    echo "ERREUR: Aucun master trouvé"
    exit 1
fi

echo ""
echo "=== Test Failover ==="
echo "Arrêt du master ${MASTER_IP}..."
ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "docker stop redis" || true

echo "Attente 90 secondes..."
sleep 90

# Vérifier nouveau master
NEW_MASTER_IP=$(ssh -o StrictHostKeyChecking=no root@${REDIS_IPS[0]} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
timeout 3 redis-cli -h 127.0.0.1 -p 26379 -a "\${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ""
EOF
) || NEW_MASTER_IP=""

if [[ -n "${NEW_MASTER_IP}" ]] && [[ "${NEW_MASTER_IP}" != "${MASTER_IP}" ]]; then
    ROLE=$(ssh -o StrictHostKeyChecking=no root@${NEW_MASTER_IP} bash <<EOF
source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null || true
docker exec redis redis-cli -a "\${REDIS_PASSWORD}" -h ${NEW_MASTER_IP} --no-auth-warning INFO replication 2>/dev/null | grep '^role:' | cut -d: -f2 | tr -d '\r\n ' || echo ""
EOF
) || ROLE=""
    
    if [[ "${ROLE}" == "master" ]]; then
        echo "SUCCESS: Failover réussi ! Nouveau master: ${NEW_MASTER_IP}"
    else
        echo "ERREUR: Nouveau master détecté mais rôle incorrect: ${ROLE}"
    fi
else
    echo "ERREUR: Failover échoué"
fi

# Redémarrer
echo "Redémarrage du master..."
ssh -o StrictHostKeyChecking=no root@${MASTER_IP} "docker start redis" || true
sleep 15

echo "Test terminé"

