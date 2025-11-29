#!/usr/bin/env bash
#
# 03_pg_03_install_haproxy_db_lb.sh - Installation HAProxy pour PostgreSQL
#
# Ce script installe et configure HAProxy sur haproxy-01/02 pour router
# le trafic vers le cluster Patroni PostgreSQL.
#
# Usage:
#   ./03_pg_03_install_haproxy_db_lb.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur haproxy-01/02
#   - Cluster Patroni installé et fonctionnel
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

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

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 3 - Installation HAProxy pour PostgreSQL"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds DB et HAProxy
declare -a DB_NODES
declare -a DB_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    # Collecter les nœuds DB (uniquement les 3 nœuds Patroni)
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]]; then
        # Filtrer uniquement les 3 nœuds Patroni
        if [[ "${HOSTNAME}" == "db-master-01" ]] || \
           [[ "${HOSTNAME}" == "db-slave-01" ]] || \
           [[ "${HOSTNAME}" == "db-slave-02" ]]; then
            DB_NODES+=("${HOSTNAME}")
            DB_IPS+=("${IP_PRIVEE}")
        fi
    fi
    
    # Collecter les nœuds HAProxy
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]]; then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#DB_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds DB incorrect: ${#DB_NODES[@]} (attendu: 3)"
    exit 1
fi

if [[ ${#HAPROXY_NODES[@]} -lt 1 ]]; then
    log_error "Aucun nœud HAProxy trouvé"
    exit 1
fi

log_success "${#DB_NODES[@]} nœuds DB trouvés: ${DB_NODES[*]}"
log_success "${#HAPROXY_NODES[@]} nœuds HAProxy trouvés: ${HAPROXY_NODES[*]}"
echo ""

# Fonction pour installer HAProxy sur un nœud
install_haproxy_node() {
    local hostname=$1
    local ip=$2
    
    log_info "--------------------------------------------------------------"
    log_info "Installation HAProxy sur ${hostname} (${ip})"
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
mkdir -p /etc/haproxy
EOF
    
    # Générer le fichier haproxy.cfg
    log_info "Génération de haproxy.cfg pour ${hostname}..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/haproxy/haproxy.cfg <<'HAPROXY_EOF'
global
    log stdout format raw local0
    maxconn 4096
    daemon

defaults
    mode tcp
    timeout connect 10s
    timeout client 30s
    timeout server 30s
    option tcplog
    option log-health-checks

# Frontend PostgreSQL
frontend fe_pg_5432
    bind *:5432
    default_backend be_pg_primary

# Backend PostgreSQL Primary
backend be_pg_primary
    option httpchk GET /master
    http-check expect status 200
$(for i in "${!DB_NODES[@]}"; do
    if [[ ${i} -eq 0 ]]; then
        echo "    server ${DB_NODES[$i]} ${DB_IPS[$i]}:5432 check port 8008 inter 3s fall 3 rise 2"
    else
        echo "    server ${DB_NODES[$i]} ${DB_IPS[$i]}:5432 check port 8008 inter 3s fall 3 rise 2 backup"
    fi
done)

# Frontend PgBouncer (routage vers PgBouncer qui écoute sur 6432)
# Note: PgBouncer écoute directement sur 6432, donc HAProxy ne bind pas sur ce port
# Le LB Hetzner 10.0.0.10:6432 pointe directement vers haproxy-01/02:6432 (PgBouncer)
# Cette section est commentée car PgBouncer est accessible directement

# Stats page (optionnel, pour monitoring)
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
HAPROXY_EOF
chmod 644 /etc/haproxy/haproxy.cfg
EOF
    
    # Créer le service systemd
    log_info "Création du service systemd..."
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
cat > /etc/systemd/system/haproxy-docker.service <<'SERVICE_EOF'
[Unit]
Description=HAProxy Docker for KeyBuzz Load Balancing
After=docker.service
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
ExecStart=/usr/bin/docker run --rm --name haproxy \\
  --network host \\
  -v /etc/haproxy/haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro \\
  haproxy:2.8-alpine
ExecStop=/usr/bin/docker stop haproxy
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
SERVICE_EOF

systemctl daemon-reload
systemctl enable haproxy-docker.service
systemctl start haproxy-docker.service
EOF
    
    # Vérifier que le service est actif
    sleep 3
    if ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
        "systemctl is-active --quiet haproxy-docker.service"; then
        log_success "${hostname} configuré et actif"
    else
        log_error "Le service HAProxy n'est pas actif sur ${hostname}"
        return 1
    fi
    
    return 0
}

# Installer sur chaque nœud HAProxy
for i in "${!HAPROXY_NODES[@]}"; do
    if ! install_haproxy_node "${HAPROXY_NODES[$i]}" "${HAPROXY_IPS[$i]}"; then
        log_error "Échec de l'installation sur ${HAPROXY_NODES[$i]}"
        exit 1
    fi
    echo ""
done

echo "=============================================================="
log_success "HAProxy installé avec succès sur tous les nœuds !"
echo "=============================================================="
echo ""
log_info "Vérification du statut..."
echo ""

# Vérifier le statut
for i in "${!HAPROXY_NODES[@]}"; do
    log_info "Statut de ${HAPROXY_NODES[$i]} (${HAPROXY_IPS[$i]}):"
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${HAPROXY_IPS[$i]}" \
        "systemctl is-active haproxy-docker.service && docker ps | grep haproxy || echo 'Service non actif'" || true
    echo ""
done

log_info "HAProxy est maintenant prêt à router le trafic vers le cluster Patroni."
log_info "Les applications peuvent se connecter via :"
log_info "  - 10.0.0.11:5432 (haproxy-01)"
log_info "  - 10.0.0.12:5432 (haproxy-02)"
log_info "  - 10.0.0.10:5432 (via LB Hetzner → haproxy-01/02)"
echo ""

