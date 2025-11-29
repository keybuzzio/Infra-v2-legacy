#!/usr/bin/env bash
#
# Script pour créer l'extension pgvector dans la base keybuzz
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    echo "❌ Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

echo "=============================================================="
echo " Création de l'extension pgvector"
echo "=============================================================="
echo ""

# Créer la base de données si elle n'existe pas
echo "Vérification/Création de la base de données keybuzz..."
ssh root@10.0.0.120 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d postgres -c 'SELECT 1 FROM pg_database WHERE datname = '\''keybuzz'\'';' | grep -q 1 || docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d postgres -c 'CREATE DATABASE keybuzz;'"

# Créer l'extension sur le primary
echo "Création de l'extension pgvector sur db-master-01..."
ssh root@10.0.0.120 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d keybuzz -c 'CREATE EXTENSION IF NOT EXISTS vector;'"

if [[ $? -eq 0 ]]; then
    echo "✅ Extension pgvector créée avec succès"
else
    echo "❌ Erreur lors de la création de l'extension"
    exit 1
fi

echo ""
echo "Vérification de l'extension..."
ssh root@10.0.0.120 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d keybuzz -c 'SELECT extname, extversion FROM pg_extension WHERE extname = '\''vector'\'';'"

echo ""
echo "Vérification sur les réplicas..."
echo "db-slave-01:"
ssh root@10.0.0.121 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d keybuzz -c 'SELECT extname FROM pg_extension WHERE extname = '\''vector'\'';'" 2>&1 | head -3

echo "db-slave-02:"
ssh root@10.0.0.122 "docker exec -e PGPASSWORD=${POSTGRES_SUPERPASS} patroni psql -U ${POSTGRES_SUPERUSER} -d keybuzz -c 'SELECT extname FROM pg_extension WHERE extname = '\''vector'\'';'" 2>&1 | head -3

echo ""
echo "=============================================================="
echo "✅ Extension pgvector installée avec succès !"
echo "=============================================================="

