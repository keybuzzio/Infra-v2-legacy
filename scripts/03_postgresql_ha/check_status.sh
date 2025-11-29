#!/usr/bin/env bash
# Script simple pour vérifier l'état du Module 3

echo "=== ÉTAT CLUSTER PATRONI ==="
CLUSTER_JSON=$(curl -s http://10.0.0.120:8008/cluster 2>/dev/null)
LEADER=$(echo "${CLUSTER_JSON}" | python3 -c "import sys, json; data=json.load(sys.stdin); leaders=[m['name'] for m in data['members'] if m['role']=='leader']; print(leaders[0] if leaders else 'NONE')" 2>/dev/null || echo "NONE")
if [[ "${LEADER}" != "NONE" ]]; then
    echo "✅ Leader détecté: ${LEADER}"
else
    echo "❌ Aucun Leader détecté"
fi

REPLICA_COUNT=$(echo "${CLUSTER_JSON}" | python3 -c "import sys, json; data=json.load(sys.stdin); print(len([m for m in data['members'] if m['role']=='replica']))" 2>/dev/null || echo "0")
echo "✅ Réplicas: ${REPLICA_COUNT}"

echo ""
echo "=== EXTENSION PGVECTOR ==="
source /opt/keybuzz-installer-v2/credentials/postgres.env
if ssh root@10.0.0.120 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d keybuzz -c 'SELECT extname FROM pg_extension WHERE extname = \"vector\";' 2>&1" | grep -q vector; then
    echo "✅ Extension pgvector installée"
else
    echo "❌ Extension pgvector non trouvée"
fi

echo ""
echo "=== HAProxy ==="
for ip in 10.0.0.11 10.0.0.12; do
    if ssh root@${ip} "docker ps | grep -q haproxy"; then
        echo "✅ HAProxy actif sur ${ip}"
    else
        echo "❌ HAProxy inactif sur ${ip}"
    fi
done

echo ""
echo "=== PgBouncer ==="
for ip in 10.0.0.11 10.0.0.12; do
    if ssh root@${ip} "docker ps | grep -q pgbouncer"; then
        echo "✅ PgBouncer actif sur ${ip}"
    else
        echo "❌ PgBouncer inactif sur ${ip}"
    fi
done

