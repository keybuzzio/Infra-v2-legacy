#!/bin/bash
# Script pour vérifier l'état de la construction

echo "=== ETAT CONSTRUCTION ==="
echo ""
echo "1. Processus en cours:"
ps aux | grep '03_pg_02' | grep -v grep || echo "Script termine"
echo ""

echo "2. Dernieres lignes log:"
tail -20 /tmp/module3_pg16_python312_compiled.log 2>/dev/null || echo "Log non disponible"
echo ""

echo "3. Images sur tous les nœuds:"
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
    echo "  $ip:"
    ssh -o BatchMode=yes root@$ip 'docker images | grep patroni-pg16-raft | head -1' || echo "    Aucune image"
done
echo ""

echo "4. Test Python 3.12 dans image (db-master-01):"
ssh -o BatchMode=yes root@10.0.0.120 'docker run --rm patroni-pg16-raft:latest /usr/local/bin/python3.12 --version 2>&1' || echo "  Python 3.12 non disponible"
echo ""

echo "5. Test Patroni dans image:"
ssh -o BatchMode=yes root@10.0.0.120 'docker run --rm patroni-pg16-raft:latest /usr/local/bin/python3.12 -m patroni --version 2>&1' || echo "  Patroni non disponible"

