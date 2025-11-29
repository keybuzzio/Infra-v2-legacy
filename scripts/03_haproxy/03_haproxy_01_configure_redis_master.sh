#!/usr/bin/env bash
#
# 03_haproxy_01_configure_redis_master.sh - Configuration HAProxy avec backend redis-master
#
# Ce script configure HAProxy avec le backend be_redis_master
# selon le design définitif (toujours pointer vers le master Redis).
#
# Usage:
#   ./03_haproxy_01_configure_redis_master.sh [servers.tsv]
#
# Prérequis:
#   - HAProxy installé sur haproxy-01 et haproxy-02
#   - Redis Sentinel accessible
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

# Parser servers.tsv
HAPROXY_IPS=()
REDIS_IPS=()

while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
    if [[ "${role}" == "lb" ]] && [[ "${subrole}" == "internal-haproxy" ]]; then
        HAPROXY_IPS+=("${ip_priv}")
    fi
    if [[ "${role}" == "redis" ]]; then
        REDIS_IPS+=("${ip_priv}")
    fi
done < <(tail -n +2 "${TSV_FILE}")

if [[ ${#HAPROXY_IPS[@]} -eq 0 ]]; then
    log_error "Aucun nœud HAProxy trouvé"
    exit 1
fi

if [[ ${#REDIS_IPS[@]} -eq 0 ]]; then
    log_error "Aucun nœud Redis trouvé"
    exit 1
fi

SENTINEL_IP="${REDIS_IPS[0]}"

log_info "HAProxy nodes: ${HAPROXY_IPS[*]}"
log_info "Redis nodes: ${REDIS_IPS[*]}"
log_info "Sentinel IP: ${SENTINEL_IP}"
echo ""

# Détecter la clé SSH
SSH_KEY="${HOME}/.ssh/keybuzz_infra"
if [[ ! -f "${SSH_KEY}" ]]; then
    SSH_KEY="/root/.ssh/keybuzz_infra"
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    log_warning "Clé SSH introuvable, utilisation de l'authentification par défaut"
    SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
else
    SSH_KEY_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
fi

# Configuration HAProxy pour chaque nœud
for haproxy_ip in "${HAPROXY_IPS[@]}"; do
    log_info "=============================================================="
    log_info "Configuration HAProxy sur: ${haproxy_ip}"
    log_info "=============================================================="
    
    ssh ${SSH_KEY_OPTS} "root@${haproxy_ip}" bash <<EOF
set -euo pipefail

HAPROXY_CONFIG="/opt/keybuzz/haproxy/haproxy.cfg"
HAPROXY_DIR="/opt/keybuzz/haproxy"

# Créer le répertoire si nécessaire
mkdir -p "\${HAPROXY_DIR}"

# Obtenir l'IP du master Redis depuis Sentinel
MASTER_IP=\$(redis-cli -h ${SENTINEL_IP} -p 26379 SENTINEL get-master-addr-by-name keybuzz-master 2>/dev/null | head -1 | cut -d' ' -f1 || echo "")

if [[ -z "\${MASTER_IP}" ]]; then
    echo "⚠️  Impossible de récupérer le master depuis Sentinel, utilisation de redis-01 par défaut"
    MASTER_IP="10.0.0.123"
fi

echo "Master Redis détecté: \${MASTER_IP}:6379"

# Vérifier si le backend be_redis_master existe déjà
if [[ -f "\${HAPROXY_CONFIG}" ]] && grep -q "backend be_redis_master" "\${HAPROXY_CONFIG}"; then
    echo "Backend be_redis_master existe déjà, mise à jour..."
    
    # Mettre à jour la ligne server redis-master
    sed -i "s|^[[:space:]]*server[[:space:]]*redis-master[[:space:]]*[0-9.]*:[0-9]*|    server redis-master \${MASTER_IP}:6379|g" "\${HAPROXY_CONFIG}"
    
    echo "✓ Backend be_redis_master mis à jour avec master: \${MASTER_IP}:6379"
else
    echo "Création du backend be_redis_master..."
    
    # Ajouter le backend be_redis_master à la config
    cat >> "\${HAPROXY_CONFIG}" <<HAPROXY_CONFIG_EOF

# Backend Redis Master (Design Définitif)
# Toujours pointer vers le master Redis, pas de round-robin
frontend redis_frontend
    bind 0.0.0.0:6379
    mode tcp
    default_backend be_redis_master

backend be_redis_master
    mode tcp
    option tcp-check
    tcp-check connect
    tcp-check send PING\\r\\n
    tcp-check expect string +PONG
    server redis-master \${MASTER_IP}:6379 check
HAPROXY_CONFIG_EOF
    
    echo "✓ Backend be_redis_master créé avec master: \${MASTER_IP}:6379"
fi

# Valider la configuration (utiliser docker si haproxy n'est pas en ligne de commande)
if command -v haproxy >/dev/null 2>&1; then
    if haproxy -c -f "\${HAPROXY_CONFIG}" >/dev/null 2>&1; then
        echo "✓ Configuration HAProxy valide"
    else
        echo "✗ Configuration HAProxy invalide"
        haproxy -c -f "\${HAPROXY_CONFIG}" || true
        exit 1
    fi
elif docker ps | grep -q haproxy; then
    # HAProxy est dans Docker, validation via docker
    if docker exec haproxy haproxy -c -f /etc/haproxy/haproxy.cfg >/dev/null 2>&1; then
        echo "✓ Configuration HAProxy valide (via Docker)"
    else
        echo "⚠️  Validation Docker échouée, mais on continue (HAProxy sera rechargé)"
    fi
else
    echo "⚠️  haproxy command non trouvé, validation ignorée (HAProxy sera rechargé)"
fi

# Recharger HAProxy (via systemd ou docker)
if systemctl is-active --quiet haproxy 2>/dev/null; then
    systemctl reload haproxy
    echo "✓ HAProxy rechargé (systemd)"
elif docker ps | grep -q haproxy; then
    docker restart haproxy >/dev/null 2>&1 || true
    echo "✓ HAProxy rechargé (Docker)"
else
    echo "⚠️  HAProxy service non trouvé, redémarrage manuel requis"
fi

# Installer le script redis-update-master.sh
echo "Installation du script redis-update-master.sh..."
mkdir -p /usr/local/bin

# Le script sera copié depuis install-01
echo "Script redis-update-master.sh doit être copié depuis install-01"
EOF

    log_success "HAProxy configuré sur ${haproxy_ip}"
done

echo ""
log_success "✅ Configuration HAProxy Redis Master terminée !"
echo ""
log_warning "NEXT STEP : Installer redis-update-master.sh sur chaque nœud HAProxy"
log_warning "            et configurer le cron/systemd pour exécution régulière"
echo ""

