#!/usr/bin/env bash
#
# 03_pg_04_install_pgbouncer.sh - Installation PgBouncer pour PostgreSQL
#
# Ce script installe et configure PgBouncer sur haproxy-01/02 pour le pooling
# de connexions PostgreSQL avec authentification SCRAM.
#
# Usage:
#   ./03_pg_04_install_pgbouncer.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur haproxy-01/02
#   - Cluster Patroni installé et fonctionnel
#   - HAProxy installé et fonctionnel
#   - Credentials configurés
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
echo " [KeyBuzz] Module 3 - Installation PgBouncer"
echo "=============================================================="
echo ""
echo "Database     : ${POSTGRES_DB}"
echo "App User     : ${POSTGRES_APP_USER}"
echo ""

# Collecter les informations des nœuds HAProxy
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod et ROLE=lb SUBROLE=internal-haproxy
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "lb" ]] || [[ "${SUBROLE}" != "internal-haproxy" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    HAPROXY_NODES+=("${HOSTNAME}")
    HAPROXY_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

if [[ ${#HAPROXY_NODES[@]} -lt 1 ]]; then
    log_error "Aucun nœud HAProxy trouvé"
    exit 1
fi

log_success "${#HAPROXY_NODES[@]} nœuds HAProxy trouvés: ${HAPROXY_NODES[*]}"
echo ""

# LB Hetzner IP (10.0.0.10)
LB_IP="10.0.0.10"

# Fonction pour générer le hash SCRAM du mot de passe
# Note: Cette fonction nécessite psql ou pgbouncer pour générer le hash correct
# Pour l'instant, on utilisera le format userlist.txt simple
generate_userlist() {
    local user=$1
    local password=$2
    
    # Format: "username" "password"
    # PgBouncer utilisera scram-sha-256
    echo "\"${user}\" \"${password}\""
}

# Fonction pour installer PgBouncer sur un nœud
install_pgbouncer_node() {
    local hostname=$1
    local ip=$2
    
    log_info "--------------------------------------------------------------"
    log_info "Installation PgBouncer sur ${hostname} (${ip})"
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
    
    # Créer les répertoires nécessaires
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" <<EOF
set -e
mkdir -p /etc/pgbouncer
EOF
    
    # Générer le fichier userlist.txt
    log_info "Génération de userlist.txt..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/pgbouncer/userlist.txt <<'USERLIST_EOF'
"${POSTGRES_APP_USER}" "${POSTGRES_APP_PASS}"
"${POSTGRES_SUPERUSER}" "${POSTGRES_SUPERPASS}"
USERLIST_EOF
chmod 600 /etc/pgbouncer/userlist.txt
EOF
    
    # Générer le fichier pgbouncer.ini
    log_info "Génération de pgbouncer.ini..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/pgbouncer/pgbouncer.ini <<'PGBOUNCER_EOF'
[databases]
${POSTGRES_DB} = host=${LB_IP} port=5432 dbname=${POSTGRES_DB}

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 6432
auth_type = scram-sha-256
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
max_client_conn = 500
default_pool_size = 50
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 100
max_user_connections = 100
server_round_robin = 1
ignore_startup_parameters = extra_float_digits
log_connections = 1
log_disconnections = 1
log_pooler_errors = 1
stats_period = 60
PGBOUNCER_EOF
chmod 644 /etc/pgbouncer/pgbouncer.ini
EOF
    
    # Créer le service systemd
    log_info "Création du service systemd..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/systemd/system/pgbouncer-docker.service <<'SERVICE_EOF'
[Unit]
Description=PgBouncer Docker for PostgreSQL Connection Pooling
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/usr/bin/docker run --rm --name pgbouncer \\
  --network host \\
  -v /etc/pgbouncer/pgbouncer.ini:/etc/pgbouncer/pgbouncer.ini:ro \\
  -v /etc/pgbouncer/userlist.txt:/etc/pgbouncer/userlist.txt:ro \\
  edoburu/pgbouncer:latest
ExecStop=/usr/bin/docker stop pgbouncer
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable pgbouncer-docker.service
systemctl start pgbouncer-docker.service
EOF
    
    # Vérifier que le service est actif
    sleep 3
    if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "systemctl is-active --quiet pgbouncer-docker.service"; then
        log_success "${hostname} configuré et actif"
    else
        log_error "Le service PgBouncer n'est pas actif sur ${hostname}"
        return 1
    fi
    
    return 0
}

# Installer sur chaque nœud HAProxy
for i in "${!HAPROXY_NODES[@]}"; do
    if ! install_pgbouncer_node "${HAPROXY_NODES[$i]}" "${HAPROXY_IPS[$i]}"; then
        log_error "Échec de l'installation sur ${HAPROXY_NODES[$i]}"
        exit 1
    fi
    echo ""
done

echo "=============================================================="
log_success "PgBouncer installé avec succès sur tous les nœuds !"
echo "=============================================================="
echo ""
log_info "Vérification du statut..."
echo ""

# Vérifier le statut
for i in "${!HAPROXY_NODES[@]}"; do
    log_info "Statut de ${HAPROXY_NODES[$i]} (${HAPROXY_IPS[$i]}):"
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${HAPROXY_IPS[$i]}" \
        "systemctl is-active pgbouncer-docker.service && docker ps | grep pgbouncer || echo 'Service non actif'" || true
    echo ""
done

log_info "PgBouncer est maintenant prêt pour le pooling de connexions."
log_info "Les applications peuvent se connecter via :"
log_info "  - 10.0.0.11:6432 (haproxy-01)"
log_info "  - 10.0.0.12:6432 (haproxy-02)"
log_info "  - 10.0.0.10:6432 (via LB Hetzner → haproxy-01/02)"
echo ""


