#!/usr/bin/env bash
#
# 00_restore_services_simple.sh - Redémarrage simple des services
#
# Ce script redémarre directement les services sur chaque serveur
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Redémarrage Simple des Services"
echo "=============================================================="
echo ""

# PostgreSQL - db-master-01
echo "1. Redémarrage PostgreSQL db-master-01 (10.0.0.120)..."
ssh -o ConnectTimeout=10 root@195.201.122.106 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
if docker ps -a | grep -q patroni; then
    docker restart patroni 2>/dev/null || docker start patroni 2>/dev/null
    echo "  ✅ Patroni redémarré"
else
    echo "  ⚠️  Container Patroni introuvable"
fi
EOF
echo ""

# PostgreSQL - db-slave-01
echo "2. Redémarrage PostgreSQL db-slave-01 (10.0.0.121)..."
ssh -o ConnectTimeout=10 root@91.98.169.31 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
if docker ps -a | grep -q patroni; then
    docker restart patroni 2>/dev/null || docker start patroni 2>/dev/null
    echo "  ✅ Patroni redémarré"
else
    echo "  ⚠️  Container Patroni introuvable"
fi
EOF
echo ""

# PostgreSQL - db-slave-02
echo "3. Redémarrage PostgreSQL db-slave-02 (10.0.0.122)..."
ssh -o ConnectTimeout=10 root@65.21.251.198 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
if docker ps -a | grep -q patroni; then
    docker restart patroni 2>/dev/null || docker start patroni 2>/dev/null
    echo "  ✅ Patroni redémarré"
else
    echo "  ⚠️  Container Patroni introuvable"
fi
EOF
echo ""

# HAProxy - haproxy-01
echo "4. Redémarrage HAProxy haproxy-01 (10.0.0.11)..."
ssh -o ConnectTimeout=10 root@159.69.159.32 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
for container in haproxy pgbouncer; do
    if docker ps -a | grep -q "$container"; then
        docker restart "$container" 2>/dev/null || docker start "$container" 2>/dev/null
        echo "  ✅ $container redémarré"
    else
        echo "  ⚠️  Container $container introuvable"
    fi
done
EOF
echo ""

# HAProxy - haproxy-02
echo "5. Redémarrage HAProxy haproxy-02 (10.0.0.12)..."
ssh -o ConnectTimeout=10 root@91.98.164.223 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
for container in haproxy pgbouncer; do
    if docker ps -a | grep -q "$container"; then
        docker restart "$container" 2>/dev/null || docker start "$container" 2>/dev/null
        echo "  ✅ $container redémarré"
    else
        echo "  ⚠️  Container $container introuvable"
    fi
done
EOF
echo ""

# Redis - redis-01
echo "6. Redémarrage Redis redis-01 (10.0.0.123)..."
ssh -o ConnectTimeout=10 root@49.12.231.193 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
for container in $(docker ps -a --format "{{.Names}}" | grep -E "redis|sentinel"); do
    docker restart "$container" 2>/dev/null || docker start "$container" 2>/dev/null
    echo "  ✅ $container redémarré"
done
EOF
echo ""

# Redis - redis-02
echo "7. Redémarrage Redis redis-02 (10.0.0.124)..."
ssh -o ConnectTimeout=10 root@23.88.48.163 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
for container in $(docker ps -a --format "{{.Names}}" | grep -E "redis|sentinel"); do
    docker restart "$container" 2>/dev/null || docker start "$container" 2>/dev/null
    echo "  ✅ $container redémarré"
done
EOF
echo ""

# Redis - redis-03
echo "8. Redémarrage Redis redis-03 (10.0.0.125)..."
ssh -o ConnectTimeout=10 root@91.98.167.166 bash <<'EOF' || echo "  ⚠️  Serveur non accessible"
for container in $(docker ps -a --format "{{.Names}}" | grep -E "redis|sentinel"); do
    docker restart "$container" 2>/dev/null || docker start "$container" 2>/dev/null
    echo "  ✅ $container redémarré"
done
EOF
echo ""

echo "=============================================================="
echo " ✅ Redémarrage terminé"
echo "=============================================================="
echo ""
echo "Attente de 30 secondes pour le démarrage des services..."
sleep 30
echo ""
echo "Vérifiez maintenant si les URLs fonctionnent :"
echo "  - https://platform.keybuzz.io"
echo "  - https://platform-api.keybuzz.io"
echo ""

