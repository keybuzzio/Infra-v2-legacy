#!/usr/bin/env bash
# Script de test manuel pour Redis HA

set -euo pipefail

source /opt/keybuzz-installer-v2/credentials/redis.env

echo "=============================================================="
echo " Tests Redis HA - Module 4"
echo "=============================================================="
echo ""

echo "=== TEST 1: Connectivité Redis Directe ==="
echo "Master (redis-01):"
ssh root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 -a ${REDIS_PASSWORD} PING" || echo "❌ Échec"
echo "Replica 1 (redis-02):"
ssh root@10.0.0.124 "docker exec redis redis-cli -h 10.0.0.124 -a ${REDIS_PASSWORD} PING" || echo "❌ Échec"
echo "Replica 2 (redis-03):"
ssh root@10.0.0.125 "docker exec redis redis-cli -h 10.0.0.125 -a ${REDIS_PASSWORD} PING" || echo "❌ Échec"
echo ""

echo "=== TEST 2: Rôles Redis ==="
echo "Master:"
ssh root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 -a ${REDIS_PASSWORD} INFO replication | grep role" || echo "❌ Échec"
echo "Replica 1:"
ssh root@10.0.0.124 "docker exec redis redis-cli -h 10.0.0.124 -a ${REDIS_PASSWORD} INFO replication | grep role" || echo "❌ Échec"
echo "Replica 2:"
ssh root@10.0.0.125 "docker exec redis redis-cli -h 10.0.0.125 -a ${REDIS_PASSWORD} INFO replication | grep role" || echo "❌ Échec"
echo ""

echo "=== TEST 3: SET/GET via Master ==="
ssh root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 -a ${REDIS_PASSWORD} SET test_key 'Hello KeyBuzz Redis HA'" || echo "❌ Échec"
VALUE=$(ssh root@10.0.0.123 "docker exec redis redis-cli -h 10.0.0.123 -a ${REDIS_PASSWORD} GET test_key" || echo "")
if [[ "${VALUE}" == "Hello KeyBuzz Redis HA" ]]; then
    echo "✅ SET/GET réussi: ${VALUE}"
else
    echo "❌ Échec SET/GET: ${VALUE}"
fi
echo ""

echo "=== TEST 4: Lecture depuis Replicas ==="
echo "Replica 1:"
ssh root@10.0.0.124 "docker exec redis redis-cli -h 10.0.0.124 -a ${REDIS_PASSWORD} GET test_key" || echo "❌ Échec"
echo "Replica 2:"
ssh root@10.0.0.125 "docker exec redis redis-cli -h 10.0.0.125 -a ${REDIS_PASSWORD} GET test_key" || echo "❌ Échec"
echo ""

echo "=== TEST 5: Sentinel Status ==="
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    echo "Sentinel ${ip}:"
    ssh root@${ip} "docker exec redis-sentinel redis-cli -h ${ip} -p 26379 SENTINEL masters" 2>&1 | head -3 || echo "❌ Échec"
    echo ""
done

echo "=== TEST 6: HAProxy Redis ==="
echo "haproxy-01:"
ssh root@10.0.0.11 "docker exec haproxy-redis sh -c 'echo PING | nc 127.0.0.1 6379'" || echo "⚠️  Test HAProxy (nc peut ne pas être disponible)"
echo "haproxy-02:"
ssh root@10.0.0.12 "docker exec haproxy-redis sh -c 'echo PING | nc 127.0.0.1 6379'" || echo "⚠️  Test HAProxy (nc peut ne pas être disponible)"
echo ""

echo "=============================================================="
echo " Tests terminés"
echo "=============================================================="

