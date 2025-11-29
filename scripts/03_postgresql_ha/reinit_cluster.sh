#!/bin/bash
# Script pour réinitialiser complètement le cluster

DB_IPS=(10.0.0.120 10.0.0.121 10.0.0.122)
DB_NODES=(db-master-01 db-slave-01 db-slave-02)

echo "=== ARRET SERVICES ET CONTENEURS ==="
for i in 0 1 2; do
    ssh -o BatchMode=yes root@${DB_IPS[$i]} "systemctl stop patroni-docker 2>/dev/null || true; docker stop patroni 2>/dev/null || true; docker rm -f patroni 2>/dev/null || true; echo \"${DB_NODES[$i]}: arrete\""
done
sleep 5

echo ""
echo "=== NETTOYAGE COMPLET DONNEES ==="
for i in 0 1 2; do
    echo "Nettoyage ${DB_NODES[$i]}..."
    ssh -o BatchMode=yes root@${DB_IPS[$i]} bash <<'CLEAN'
# Supprimer TOUT le contenu des répertoires
rm -rf /opt/keybuzz/postgres/data/* /opt/keybuzz/postgres/data/.* 2>/dev/null || true
rm -rf /opt/keybuzz/postgres/raft/* /opt/keybuzz/postgres/raft/.* 2>/dev/null || true

# Vérifier que les répertoires sont vraiment vides
if [ "$(ls -A /opt/keybuzz/postgres/data 2>/dev/null)" ]; then
    echo "  ⚠️  Répertoire data non vide, suppression forcée..."
    rm -rf /opt/keybuzz/postgres/data
fi
if [ "$(ls -A /opt/keybuzz/postgres/raft 2>/dev/null)" ]; then
    echo "  ⚠️  Répertoire raft non vide, suppression forcée..."
    rm -rf /opt/keybuzz/postgres/raft
fi

# Recréer les répertoires
mkdir -p /opt/keybuzz/postgres/data /opt/keybuzz/postgres/raft /opt/keybuzz/postgres/archive
chown -R 999:999 /opt/keybuzz/postgres/data /opt/keybuzz/postgres/raft /opt/keybuzz/postgres/archive 2>/dev/null || true
chmod 700 /opt/keybuzz/postgres/data /opt/keybuzz/postgres/raft 2>/dev/null || true
echo "  ✓ Données nettoyées"
CLEAN
done

echo ""
echo "=== DEMARRAGE PARALLELE ==="
for i in 0 1 2; do
    echo "Démarrage ${DB_NODES[$i]}..."
    ssh -o BatchMode=yes root@${DB_IPS[$i]} \
        "docker run -d --name patroni --hostname ${DB_NODES[$i]} --network host --restart unless-stopped -u postgres \
        -v /opt/keybuzz/postgres/data:/var/lib/postgresql/data \
        -v /opt/keybuzz/postgres/raft:/opt/keybuzz/postgres/raft \
        -v /opt/keybuzz/postgres/archive:/opt/keybuzz/postgres/archive \
        -v /opt/keybuzz/patroni/config/patroni.yml:/etc/patroni/patroni.yml:ro \
        patroni-pg16-raft:latest && echo \"  ✓ ${DB_NODES[$i]} démarré\"" &
done
wait
sleep 60

echo ""
echo "=== VERIFICATION ==="
for i in 0 1 2; do
    echo "${DB_NODES[$i]}:"
    ssh -o BatchMode=yes root@${DB_IPS[$i]} 'docker ps | grep patroni || echo "  ✗ Non démarré"'
done

echo ""
echo "=== STATUT CLUSTER ==="
ssh -o BatchMode=yes root@10.0.0.120 'docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1' || echo "En attente de stabilisation..."

