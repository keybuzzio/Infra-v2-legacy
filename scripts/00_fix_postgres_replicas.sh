#!/usr/bin/env bash
#
# 00_fix_postgres_replicas.sh - Corriger les permissions PostgreSQL sur les réplicas
#

set -euo pipefail

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " Correction Permissions PostgreSQL Réplicas"
echo "=============================================================="
echo ""

for ip in 10.0.0.121 10.0.0.122; do
    echo "=== ${ip} ==="
    ssh ${SSH_OPTS} root@${ip} bash <<'EOF'
# Arrêter Patroni
docker stop patroni 2>/dev/null || true

# Corriger les permissions
chown -R 999:999 /opt/keybuzz/postgres/data 2>/dev/null || true
chmod 700 /opt/keybuzz/postgres/data 2>/dev/null || true

# Redémarrer Patroni
docker start patroni 2>/dev/null || true
echo "  ✓ Permissions corrigées et Patroni redémarré"
EOF
    sleep 5
done

echo ""
echo "Attente de 30 secondes pour que les réplicas se synchronisent..."
sleep 30

echo ""
echo "Vérification de l'état du cluster..."
ssh ${SSH_OPTS} root@10.0.0.120 "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" || true

echo ""
echo "✓ Correction terminée"

