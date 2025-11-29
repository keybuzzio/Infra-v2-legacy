#!/usr/bin/env python3
"""
Corrige la migration problématique Chatwoot
"""
import os
import subprocess
import sys

# Charger les credentials
env_file = "/opt/keybuzz-installer-v2/credentials/postgres.env"
if not os.path.exists(env_file):
    print(f"❌ Fichier {env_file} non trouvé")
    sys.exit(1)

# Charger les variables
env_vars = {}
with open(env_file, 'r') as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith('#') and '=' in line:
            key, value = line.split('=', 1)
            env_vars[key] = value

# Variables PostgreSQL
pg_host = env_vars.get('POSTGRES_HOST', '10.0.0.10')
pg_port = env_vars.get('POSTGRES_PORT', '5432')
pg_user = env_vars.get('POSTGRES_SUPERUSER', 'kb_admin')
pg_pass = env_vars.get('POSTGRES_SUPERPASS', '')
pg_db = 'chatwoot'

# Commande psql
cmd = [
    'psql',
    '-h', pg_host,
    '-p', pg_port,
    '-U', pg_user,
    '-d', pg_db,
    '-c', "INSERT INTO schema_migrations (version) VALUES ('20231211010807') ON CONFLICT (version) DO NOTHING;"
]

# Exécuter
env = os.environ.copy()
env['PGPASSWORD'] = pg_pass

try:
    result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)
    print("✅ Migration 20231211010807 marquée comme exécutée")
    print(result.stdout)
except subprocess.CalledProcessError as e:
    print(f"❌ Erreur: {e}")
    print(e.stderr)
    sys.exit(1)

