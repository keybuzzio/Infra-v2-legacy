#!/bin/bash
set -u
set -o pipefail

BASE="/opt/keybuzz/redis-lb"
STATE_FILE="${BASE}/status/STATE"

# Variables (seront remplacées par le script principal)
REDIS_IPS="${REDIS_IPS}"
SENTINEL_IPS="${SENTINEL_IPS}"
MASTER_NAME="${MASTER_NAME}"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Initialiser les compteurs
REDIS_OK=0
SENTINEL_OK=0
HAPROXY_OK=0

# Fonction pour vérifier Redis
check_redis() {
    local ip=$1
    timeout 2 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"
}

# Fonction pour vérifier Sentinel
check_sentinel() {
    local ip=$1
    timeout 2 redis-cli -h "${ip}" -p 26379 SENTINEL get-master-addr-by-name "${MASTER_NAME}" 2>/dev/null | head -1 | grep -q "."
}

# Fonction pour vérifier HAProxy
check_haproxy() {
    docker ps | grep -q "haproxy-redis"
}

# Vérifier les nœuds Redis
for ip in ${REDIS_IPS}; do
    if check_redis "${ip}"; then
        REDIS_OK=$((REDIS_OK + 1))
    fi
done

# Vérifier les Sentinels
for ip in ${SENTINEL_IPS}; do
    if check_sentinel "${ip}"; then
        SENTINEL_OK=$((SENTINEL_OK + 1))
    fi
done

# Vérifier HAProxy
if check_haproxy; then
    HAPROXY_OK=1
fi

# Déterminer l'état
if [ "${REDIS_OK}" -ge 2 ] && [ "${SENTINEL_OK}" -ge 2 ] && [ "${HAPROXY_OK}" -eq 1 ]; then
    echo "OK" > "${STATE_FILE}"
    exit 0
elif [ "${REDIS_OK}" -ge 1 ] && [ "${SENTINEL_OK}" -ge 1 ]; then
    echo "DEGRADED" > "${STATE_FILE}"
    exit 0
else
    echo "ERROR" > "${STATE_FILE}"
    exit 1
fi

