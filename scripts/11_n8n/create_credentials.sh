#!/bin/bash
# Script pour créer les credentials manuellement

mkdir -p /root/credentials
chmod 700 /root/credentials

# PostgreSQL credentials
cat > /root/credentials/postgres.env << 'POSTGRES_EOF'
#!/bin/bash
# Credentials PostgreSQL/Patroni - Générés manuellement

export POSTGRES_PASSWORD="NEhobUmaJGdR7TL2MCXRB853"
export REPLICATOR_PASSWORD="EtMfs8l8kCAPbc35MpK77Dya"
export PATRONI_API_PASSWORD="SBbee8i74cojAAm5zQ8DLwjF"
export PGPASSWORD="NEhobUmaJGdR7TL2MCXRB853"
export POSTGRES_SUPERUSER_PASSWORD="NEhobUmaJGdR7TL2MCXRB853"
export POSTGRES_LB_IP="10.0.0.10"
export POSTGRES_PORT="5432"
export POSTGRES_PORT_POOL="4632"

# URLs de connexion (via LB Hetzner 10.0.0.10)
export DATABASE_URL="postgresql://postgres:NEhobUmaJGdR7TL2MCXRB853@10.0.0.10:6432/postgres"
export KEYBUZZ_DATABASE_URL="postgresql://postgres:NEhobUmaJGdR7TL2MCXRB853@10.0.0.10:6432/keybuzz"
POSTGRES_EOF

# Redis credentials
cat > /root/credentials/redis.env << 'REDIS_EOF'
#!/bin/bash
# Credentials Redis HA - Générés manuellement

export REDIS_PASSWORD="SfqY41ThPI3UlGZxI1j2qlm0unBR41Ie"
export REDIS_SENTINEL_PASSWORD="SfqY41ThPI3UlGZxI1j2qlm0unBR41Ie"
export REDIS_MASTER_NAME="mymaster"
export REDIS_SENTINEL_QUORUM="2"
export REDIS_LB_IP="10.0.0.10"
export REDIS_PORT="6379"

# URLs de connexion
export REDIS_URL="redis://:SfqY41ThPI3UlGZxI1j2qlm0unBR41Ie@10.0.0.10:6379/0"
REDIS_EOF

chmod 600 /root/credentials/postgres.env
chmod 600 /root/credentials/redis.env

echo "✅ Credentials créés:"
echo "  - /root/credentials/postgres.env"
echo "  - /root/credentials/redis.env"

