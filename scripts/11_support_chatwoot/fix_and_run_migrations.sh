#!/usr/bin/env bash
#
# fix_and_run_migrations.sh - Fix DB et exécute les migrations
#

set -euo pipefail

source /opt/keybuzz-installer-v2/credentials/postgres.env
export PGPASSWORD="${POSTGRES_SUPERPASS}"

echo "=== Création base chatwoot si nécessaire ==="
psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres <<EOF
SELECT 'CREATE DATABASE chatwoot OWNER chatwoot'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'chatwoot')\gexec
EOF

echo ""
echo "=== Création extension pg_stat_statements ==="
psql -h 10.0.0.10 -p 5432 -U kb_admin -d chatwoot <<EOF
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOF

echo ""
echo "=== Vérification ==="
psql -h 10.0.0.10 -p 5432 -U kb_admin -d chatwoot -c "SELECT extname FROM pg_extension WHERE extname = 'pg_stat_statements';"

echo ""
echo "=== Relance migrations ==="
export KUBECONFIG=/root/.kube/config
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 2
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
bash 11_ct_04_run_migrations.sh

