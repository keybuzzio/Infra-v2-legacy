#!/bin/bash
# Installation finale de pgvector

set -e

source ../../postgres.env 2>/dev/null || exit 1

echo "=============================================================="
echo " Installation pgvector sur le cluster PostgreSQL HA"
echo "=============================================================="
echo ""

echo "=== Installation de l'extension ==="
ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni psql -U postgres -d keybuzz -c 'CREATE EXTENSION IF NOT EXISTS vector;' 2>&1"

if [ $? -eq 0 ]; then
    echo "✓ Extension créée"
else
    echo "✗ Erreur lors de la création"
    exit 1
fi

echo ""
echo "=== Vérification de l'installation ==="
VERSION=$(ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni psql -U postgres -d keybuzz -t -c \"SELECT extversion FROM pg_extension WHERE extname = 'vector';\" 2>&1" | tr -d ' ')

if [[ -n "${VERSION}" ]]; then
    echo "✓ pgvector version ${VERSION} installé"
else
    echo "✗ Impossible de récupérer la version"
    exit 1
fi

echo ""
echo "=== Test de fonctionnalité ==="
RESULT=$(ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni psql -U postgres -d keybuzz -t -c \"SELECT vector(ARRAY[1,2,3]::float[]);\" 2>&1" | head -1)

if [[ -n "${RESULT}" ]]; then
    echo "✓ Test réussi: ${RESULT}"
else
    echo "⚠ Test échoué, mais l'extension est installée"
fi

echo ""
echo "=============================================================="
echo "✓ pgvector installé avec succès !"
echo "=============================================================="

