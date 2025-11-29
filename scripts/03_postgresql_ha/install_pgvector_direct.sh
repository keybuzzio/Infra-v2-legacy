#!/bin/bash
# Installation directe de pgvector

source ../../postgres.env 2>/dev/null || exit 1

echo "=== INSTALLATION PGVECTOR ==="
ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni psql -U postgres -d keybuzz -c 'CREATE EXTENSION IF NOT EXISTS vector;' 2>&1"

echo ""
echo "=== VERIFICATION ==="
VERSION=$(ssh -o BatchMode=yes root@10.0.0.120 "docker exec patroni psql -U postgres -d keybuzz -t -c \"SELECT extversion FROM pg_extension WHERE extname = 'vector';\" 2>&1" | tr -d ' ')

if [[ -n "${VERSION}" ]]; then
    echo "✓ pgvector version ${VERSION} installé"
else
    echo "✗ Erreur lors de l'installation"
    exit 1
fi

