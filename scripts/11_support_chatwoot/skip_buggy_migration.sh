#!/bin/bash
source /opt/keybuzz-installer-v2/credentials/postgres.env
source /opt/keybuzz-installer-v2/credentials/chatwoot.env
export PGPASSWORD="${CHATWOOT_PASSWORD}"

echo "=== Marquage migration buggy comme exécutée ==="
psql -h 10.0.0.10 -p 5432 -U chatwoot -d chatwoot <<SQL
-- Créer la table schema_migrations si elle n'existe pas
CREATE TABLE IF NOT EXISTS schema_migrations (version VARCHAR PRIMARY KEY);

-- Marquer la migration comme exécutée
INSERT INTO schema_migrations (version) VALUES ('20231211010807') ON CONFLICT (version) DO NOTHING;

-- Vérifier
SELECT version FROM schema_migrations WHERE version = '20231211010807';
SQL

echo "Migration marquée comme exécutée"

