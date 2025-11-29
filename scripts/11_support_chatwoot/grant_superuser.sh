#!/bin/bash
source /opt/keybuzz-installer-v2/credentials/postgres.env
export PGPASSWORD="${POSTGRES_SUPERPASS}"
psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres -c "ALTER USER chatwoot WITH SUPERUSER;"
echo "Droits superuser accordés à chatwoot"

