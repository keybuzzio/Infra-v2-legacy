#!/usr/bin/env bash
#
# fix_patroni_yml.sh - Script de correction pour créer les fichiers patroni.yml manquants
#
# Ce script crée les fichiers patroni.yml manquants sur les 3 nœuds DB
# après une installation où les répertoires n'ont pas été créés correctement

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Charger les credentials
if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Collecter les informations des nœuds DB
declare -a DB_NODES
declare -a DB_IPS

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" != "db" ]] || [[ "${SUBROLE}" != "postgres" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" != "db-master-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-02" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    DB_NODES+=("${HOSTNAME}")
    DB_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

echo "=============================================================="
echo " [KeyBuzz] Correction des fichiers patroni.yml"
echo "=============================================================="
echo ""

# Fonction pour corriger un nœud
fix_node() {
    local hostname=$1
    local ip=$2
    
    log_info "Correction de ${hostname} (${ip})..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
# Créer les répertoires nécessaires
mkdir -p /etc/patroni
mkdir -p /opt/keybuzz/patroni/config

# Générer le fichier patroni.yml directement dans le répertoire config
cat > /opt/keybuzz/patroni/config/patroni.yml <<'PATRONI_EOF'
scope: ${PATRONI_CLUSTER_NAME}
namespace: /db/
name: ${hostname}

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${ip}:8008

raft:
  data_dir: /opt/keybuzz/postgres/raft
  self_addr: ${ip}:7000
  partner_addrs:
$(for i in "${!DB_IPS[@]}"; do
    if [[ "${DB_IPS[$i]}" != "${ip}" ]]; then
        echo "    - ${DB_IPS[$i]}:7000"
    fi
done)

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 30
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        max_connections: 200
        shared_buffers: 256MB
        effective_cache_size: 1GB
        maintenance_work_mem: 64MB
        checkpoint_completion_target: 0.9
        wal_buffers: 16MB
        default_statistics_target: 100
        random_page_cost: 1.1
        effective_io_concurrency: 200
        work_mem: 4MB
        min_wal_size: 1GB
        max_wal_size: 4GB
        max_worker_processes: 8
        max_parallel_workers_per_gather: 4
        max_parallel_workers: 8
        max_parallel_maintenance_workers: 4
        
  initdb:
    - encoding: UTF8
    - locale: en_US.UTF-8
    - data-checksums
    
  pg_hba:
    - local all all trust
    - host all all 10.0.0.0/16 scram-sha-256
    - host replication ${POSTGRES_REPL_USER} 10.0.0.0/16 scram-sha-256
    
  users:
    ${POSTGRES_SUPERUSER}:
      password: ${POSTGRES_SUPERPASS}
      options:
        - createrole
        - createdb
    ${POSTGRES_REPL_USER}:
      password: ${POSTGRES_REPL_PASS}
      options:
        - replication

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${ip}:5432
  data_dir: /var/lib/postgresql/data
  pgpass: /tmp/pgpass
  authentication:
    superuser:
      username: ${POSTGRES_SUPERUSER}
      password: ${POSTGRES_SUPERPASS}
    replication:
      username: ${POSTGRES_REPL_USER}
      password: ${POSTGRES_REPL_PASS}
  parameters:
    max_connections: 200
    shared_buffers: 256MB
    effective_cache_size: 1GB
    maintenance_work_mem: 64MB
    checkpoint_completion_target: 0.9
    wal_buffers: 16MB
    default_statistics_target: 100
    random_page_cost: 1.1
    effective_io_concurrency: 200
    work_mem: 4MB
    min_wal_size: 1GB
    max_wal_size: 4GB
    max_worker_processes: 8
    max_parallel_workers_per_gather: 4
    max_parallel_workers: 8
    max_parallel_maintenance_workers: 4

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
PATRONI_EOF

# Définir les permissions correctes
chmod 644 /opt/keybuzz/patroni/config/patroni.yml
chown postgres:postgres /opt/keybuzz/patroni/config/patroni.yml 2>/dev/null || chown 999:999 /opt/keybuzz/patroni/config/patroni.yml

# Créer également un lien symbolique ou copie dans /etc/patroni pour compatibilité
cp /opt/keybuzz/patroni/config/patroni.yml /etc/patroni/patroni.yml
chmod 600 /etc/patroni/patroni.yml

echo "  ✓ Fichier patroni.yml créé avec succès"
EOF

    if [[ $? -eq 0 ]]; then
        log_success "${hostname} corrigé"
        return 0
    else
        log_error "Échec de la correction sur ${hostname}"
        return 1
    fi
}

# Corriger chaque nœud
for i in "${!DB_NODES[@]}"; do
    if ! fix_node "${DB_NODES[$i]}" "${DB_IPS[$i]}"; then
        log_error "Échec de la correction sur ${DB_NODES[$i]}"
        exit 1
    fi
    echo ""
done

echo "=============================================================="
log_success "Tous les fichiers patroni.yml ont été créés avec succès !"
echo "=============================================================="

