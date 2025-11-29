#!/usr/bin/env bash
#
# 03_pg_02_install_patroni_cluster.sh - Installation du cluster Patroni RAFT
#
# Ce script installe et configure le cluster PostgreSQL HA avec Patroni RAFT
# sur les 3 nœuds DB (db-master-01, db-slave-01, db-slave-02).
#
# Usage:
#   ./03_pg_02_install_patroni_cluster.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs DB
#   - Credentials configurés (03_pg_00_setup_credentials.sh)
#   - Volumes XFS préparés sur chaque nœud DB
#   - Exécuter depuis install-01

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

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    log_info "Exécutez d'abord: ./03_pg_00_setup_credentials.sh"
    exit 1
fi

# Charger les credentials
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 3 - Installation Cluster Patroni RAFT"
echo "=============================================================="
echo ""
echo "Cluster Name : ${PATRONI_CLUSTER_NAME}"
echo "Database     : ${POSTGRES_DB}"
echo ""

# Collecter les informations des nœuds DB
declare -a DB_NODES
declare -a DB_IPS
declare -a DB_HOSTNAMES

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod et ROLE=db SUBROLE=postgres
    # ET on filtre uniquement les serveurs db-master-01, db-slave-01, db-slave-02
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "db" ]] || [[ "${SUBROLE}" != "postgres" ]]; then
        continue
    fi
    
    # Filtrer uniquement les 3 nœuds Patroni (exclure temporal-db, analytics-db, etc.)
    if [[ "${HOSTNAME}" != "db-master-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-02" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        log_warning "IP privée vide pour ${HOSTNAME}, on saute."
        continue
    fi
    
    DB_NODES+=("${HOSTNAME}")
    DB_IPS+=("${IP_PRIVEE}")
    DB_HOSTNAMES+=("${HOSTNAME}")
done
exec 3<&-

if [[ ${#DB_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds DB incorrect: ${#DB_NODES[@]} (attendu: 3)"
    exit 1
fi

log_success "3 nœuds DB trouvés: ${DB_NODES[*]}"
echo ""

# Construire la liste RAFT
RAFT_MEMBERS=""
for i in "${!DB_IPS[@]}"; do
    if [[ -n "${RAFT_MEMBERS}" ]]; then
        RAFT_MEMBERS="${RAFT_MEMBERS},"
    fi
    RAFT_MEMBERS="${RAFT_MEMBERS}${DB_IPS[$i]}:7000"
done

log_info "Membres RAFT: ${RAFT_MEMBERS}"
echo ""

# Fonction pour installer Patroni sur un nœud
install_patroni_node() {
    local hostname=$1
    local ip=$2
    local node_index=$3
    
    log_info "--------------------------------------------------------------"
    log_info "Installation sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    # Vérifier la connectivité
    if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new "root@${ip}" "echo OK" >/dev/null 2>&1; then
        log_error "Impossible de se connecter à ${hostname}"
        return 1
    fi
    
    # Vérifier Docker
    if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "command -v docker >/dev/null 2>&1 && systemctl is-active --quiet docker" >/dev/null 2>&1; then
        log_error "Docker non disponible sur ${hostname}"
        return 1
    fi
    
    # Vérifier le filesystem XFS
    local fs_type=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "df -T /opt/keybuzz/postgres/data 2>/dev/null | tail -1 | awk '{print \$2}' || echo 'unknown'")
    
    if [[ "${fs_type}" != "xfs" ]] && [[ "${fs_type}" != "unknown" ]]; then
        log_warning "Filesystem sur ${hostname} n'est pas XFS (${fs_type})"
        # Vérifier si c'est un mountpoint (volume monté)
        local is_mountpoint=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
            "mountpoint -q /opt/keybuzz/postgres/data 2>/dev/null && echo 'yes' || echo 'no'")
        
        if [[ "${is_mountpoint}" == "yes" ]]; then
            log_warning "Volume monté mais filesystem ${fs_type} (XFS recommandé pour PostgreSQL)"
            log_warning "Le volume devrait être en XFS pour de meilleures performances"
        else
            log_warning "Répertoire non monté, utilisation du filesystem système (${fs_type})"
        fi
        
        # En mode non-interactif ou si volume monté, continuer automatiquement
        # Vérifier si on est en mode non-interactif (via variable d'environnement ou stdin fermé)
        if [[ "${SKIP_FS_CHECK:-false}" == "true" ]] || [[ "${is_mountpoint}" == "yes" ]] || [[ "${NON_INTERACTIVE:-false}" == "true" ]] || ! tty -s; then
            log_warning "Continuation automatique (mode non-interactif ou volume monté)"
        else
            log_warning "Continuez quand même ? (y/N)"
            read -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Installation annulée"
                return 1
            fi
        fi
    elif [[ "${fs_type}" == "xfs" ]]; then
        log_success "Filesystem XFS détecté sur ${hostname}"
    fi
    
    # Créer les répertoires nécessaires et construire l'image Docker
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<'BUILD_IMAGE'
set -e

# Arrêter les conteneurs existants
docker stop patroni 2>/dev/null || true
docker rm -f patroni 2>/dev/null || true

# Structure des répertoires
mkdir -p /opt/keybuzz/postgres/{data,raft,archive,config,logs,status}
mkdir -p /opt/keybuzz/patroni/{config,logs}

# Permissions (même si le volume n'est pas monté, on prépare les répertoires)
chown -R 999:999 /opt/keybuzz/postgres 2>/dev/null || true

# Construire l'image Docker personnalisée (TOUJOURS construire, même sans volume monté)
echo "  → Construction de l'image Docker custom Patroni + PostgreSQL 16 + pgvector..."

cat > /opt/keybuzz/patroni/Dockerfile <<'DOCKERFILE'
FROM postgres:16

ENV DEBIAN_FRONTEND=noninteractive

# Installer les dépendances pour Patroni avec Python 3.11 (déjà présent dans postgres:16)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        python3-pip \
        python3-dev \
        python3-psycopg2 \
        python3-setuptools \
        python3-wheel \
        gcc \
        postgresql-server-dev-16 \
        git \
        ca-certificates && \
    pip3 install --break-system-packages --no-cache-dir \
        patroni[raft]==3.3.2 \
        psycopg2-binary && \
    apt-get remove -y gcc git && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Installer pgvector
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql-16-pgvector && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/run/postgresql && \
    chown -R postgres:postgres /var/run/postgresql

USER postgres

CMD ["patroni", "/etc/patroni/patroni.yml"]
DOCKERFILE

# Build
cd /opt/keybuzz/patroni
if docker build -t patroni-pg16-raft:latest . >/tmp/patroni_build.log 2>&1; then
    echo "  ✓ Image construite"
else
    echo "  ✗ Échec build (voir /tmp/patroni_build.log)"
    exit 1
fi
BUILD_IMAGE
    
    # Générer le fichier patroni.yml
    log_info "Génération de patroni.yml pour ${hostname}..."
    
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
mkdir -p /etc/patroni
cp /opt/keybuzz/patroni/config/patroni.yml /etc/patroni/patroni.yml
chmod 600 /etc/patroni/patroni.yml
EOF
    
    # Créer le service systemd
    log_info "Création du service systemd..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/systemd/system/patroni-docker.service <<'SERVICE_EOF'
[Unit]
Description=Patroni Docker for PostgreSQL 16
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/usr/bin/docker run -d --name patroni \\
  --hostname ${hostname} \\
  --network host \\
  --restart unless-stopped \\
  -v /opt/keybuzz/postgres/data:/var/lib/postgresql/data \\
  -v /opt/keybuzz/postgres/raft:/opt/keybuzz/postgres/raft \\
  -v /opt/keybuzz/postgres/archive:/opt/keybuzz/postgres/archive \\
  -v /opt/keybuzz/patroni/config/patroni.yml:/etc/patroni/patroni.yml:ro \\
  -u postgres \\
  patroni-pg16-raft:latest
ExecStop=/usr/bin/docker stop patroni
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable patroni-docker.service
EOF
    
    # Ne pas démarrer maintenant, on démarrera tous ensemble après
    log_info "Configuration terminée pour ${hostname} (démarrage différé)"
    
    log_success "${hostname} configuré"
    return 0
}

# Installer sur chaque nœud
for i in "${!DB_NODES[@]}"; do
    if ! install_patroni_node "${DB_NODES[$i]}" "${DB_IPS[$i]}" "${i}"; then
        log_error "Échec de l'installation sur ${DB_NODES[$i]}"
        exit 1
    fi
    echo ""
done

# Démarrer tous les nœuds en PARALLÈLE pour RAFT quorum
log_info "Démarrage du cluster Patroni..."
log_warning "Avec RAFT, tous les nœuds doivent démarrer ensemble pour le quorum"
echo ""

# Nettoyer les anciens conteneurs sur tous les nœuds
log_info "Nettoyage des anciens conteneurs..."
for i in "${!DB_NODES[@]}"; do
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${DB_IPS[$i]}" \
        "docker stop patroni 2>/dev/null || true; \
         docker rm -f patroni 2>/dev/null || true; \
         docker container prune -f 2>/dev/null || true; \
         sleep 1" &
done
wait
sleep 3

# Démarrer TOUS les nœuds en parallèle
for i in "${!DB_NODES[@]}"; do
    log_info "Démarrage de Patroni sur ${DB_NODES[$i]}..."
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${DB_IPS[$i]}" \
        "docker run -d --name patroni --hostname ${DB_NODES[$i]} --network host --restart unless-stopped -u postgres -v /opt/keybuzz/postgres/data:/var/lib/postgresql/data -v /opt/keybuzz/postgres/raft:/opt/keybuzz/postgres/raft -v /opt/keybuzz/postgres/archive:/opt/keybuzz/postgres/archive -v /opt/keybuzz/patroni/config/patroni.yml:/etc/patroni/patroni.yml:ro patroni-pg16-raft:latest" &
done

# Attendre que tous les processus en arrière-plan se terminent
wait

log_info "Attente de la stabilisation du cluster (30 secondes)..."
sleep 30

echo ""
echo "=============================================================="
log_success "Cluster Patroni RAFT installé avec succès !"
echo "=============================================================="
echo ""
log_info "Vérification du statut du cluster..."
echo ""

# Vérifier le statut
for i in "${!DB_NODES[@]}"; do
    log_info "Statut de ${DB_NODES[$i]} (${DB_IPS[$i]}):"
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${DB_IPS[$i]}" \
        "systemctl is-active patroni-docker.service && docker ps | grep patroni || echo 'Service non actif'" || true
    echo ""
done

log_info "Pour vérifier le cluster complet :"
log_info "  ssh root@${DB_IPS[0]} 'docker exec patroni patronictl -c /etc/patroni/patroni.yml list'"
echo ""

