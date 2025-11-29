#!/usr/bin/env bash
#
# 00_diagnostic_failover.sh - Diagnostic des tests de failover
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " Diagnostic Failover PostgreSQL et Redis"
echo "=============================================================="
echo ""

# PostgreSQL - Vérifier l'état actuel
echo "=== PostgreSQL - État Actuel ==="
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    echo "  ${ip}:"
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("role", "unknown"))' 2>/dev/null || echo "unknown"
EOF
)
    STATE=$(ssh ${SSH_OPTS} root@${ip} "docker ps | grep patroni | awk '{print \$7}'" 2>/dev/null || echo "stopped")
    echo "    Rôle: ${ROLE}, État: ${STATE}"
done
echo ""

# Redis - Vérifier l'état actuel
echo "=== Redis - État Actuel ==="
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    echo "  ${ip}:"
    ROLE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis redis-cli -a \"\${REDIS_PASSWORD}\" -h ${ip} INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n '" 2>/dev/null || echo "unknown")
    STATE=$(ssh ${SSH_OPTS} root@${ip} "docker ps | grep redis | grep -v sentinel | awk '{print \$7}'" 2>/dev/null || echo "stopped")
    echo "    Rôle: ${ROLE}, État: ${STATE}"
done
echo ""

# Test manuel PostgreSQL failover
echo "=== Test Manuel PostgreSQL Failover ==="
echo "1. Identifier le primary actuel..."
PRIMARY_IP=""
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("role", "unknown"))' 2>/dev/null || echo "unknown"
EOF
)
    if [[ "${ROLE}" == "primary" ]]; then
        PRIMARY_IP="${ip}"
        echo "   Primary trouvé: ${PRIMARY_IP}"
        break
    fi
done

if [[ -n "${PRIMARY_IP}" ]]; then
    echo "2. Arrêt du primary sur ${PRIMARY_IP}..."
    ssh ${SSH_OPTS} root@${PRIMARY_IP} "docker stop patroni" || true
    echo "3. Attente de 30 secondes pour le failover..."
    sleep 30
    
    echo "4. Vérification du nouveau primary..."
    NEW_PRIMARY=false
    for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
        if [[ "${ip}" != "${PRIMARY_IP}" ]]; then
            ROLE=$(ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
curl -s http://localhost:8008/patroni 2>/dev/null | python3 -c 'import sys, json; data=json.load(sys.stdin); print(data.get("role", "unknown"))' 2>/dev/null || echo "unknown"
EOF
)
            echo "   ${ip}: ${ROLE}"
            if [[ "${ROLE}" == "primary" ]]; then
                NEW_PRIMARY=true
                echo "   ✓ Nouveau primary détecté sur ${ip}"
            fi
        fi
    done
    
    if [[ "${NEW_PRIMARY}" == "true" ]]; then
        echo "   ✓ Failover PostgreSQL réussi"
    else
        echo "   ✗ Failover PostgreSQL échoué"
    fi
    
    echo "5. Redémarrage du nœud arrêté..."
    ssh ${SSH_OPTS} root@${PRIMARY_IP} "docker start patroni" || true
    sleep 20
    echo "   ✓ Nœud redémarré"
fi
echo ""

# Test manuel Redis failover
echo "=== Test Manuel Redis Failover ==="
echo "1. Identifier le master actuel..."
MASTER_IP=""
for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
    ROLE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis redis-cli -a \"\${REDIS_PASSWORD}\" -h ${ip} INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n '" 2>/dev/null || echo "unknown")
    if [[ "${ROLE}" == "master" ]]; then
        MASTER_IP="${ip}"
        echo "   Master trouvé: ${MASTER_IP}"
        break
    fi
done

if [[ -n "${MASTER_IP}" ]]; then
    echo "2. Arrêt du master sur ${MASTER_IP}..."
    ssh ${SSH_OPTS} root@${MASTER_IP} "docker stop redis" || true
    echo "3. Attente de 30 secondes pour le failover Sentinel..."
    sleep 30
    
    echo "4. Vérification du nouveau master..."
    NEW_MASTER=false
    for ip in 10.0.0.123 10.0.0.124 10.0.0.125; do
        if [[ "${ip}" != "${MASTER_IP}" ]]; then
            ROLE=$(ssh ${SSH_OPTS} root@${ip} "source /opt/keybuzz-installer/credentials/redis.env 2>/dev/null && docker exec redis redis-cli -a \"\${REDIS_PASSWORD}\" -h ${ip} INFO replication 2>/dev/null | grep 'role:' | cut -d: -f2 | tr -d '\r\n '" 2>/dev/null || echo "unknown")
            echo "   ${ip}: ${ROLE}"
            if [[ "${ROLE}" == "master" ]]; then
                NEW_MASTER=true
                echo "   ✓ Nouveau master détecté sur ${ip}"
            fi
        fi
    done
    
    if [[ "${NEW_MASTER}" == "true" ]]; then
        echo "   ✓ Failover Redis réussi"
    else
        echo "   ✗ Failover Redis échoué"
    fi
    
    echo "5. Redémarrage du nœud arrêté..."
    ssh ${SSH_OPTS} root@${MASTER_IP} "docker start redis" || true
    sleep 20
    echo "   ✓ Nœud redémarré"
fi
echo ""

