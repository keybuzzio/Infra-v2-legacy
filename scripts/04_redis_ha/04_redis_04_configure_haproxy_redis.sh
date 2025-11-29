#!/usr/bin/env bash
#
# 04_redis_04_configure_haproxy_redis.sh - Configuration HAProxy pour Redis
#
# Ce script configure HAProxy sur haproxy-01/02 pour router vers le master Redis.
# Il inclut un watcher Sentinel qui met à jour automatiquement HAProxy lors d'un failover.
#
# Usage:
#   ./04_redis_04_configure_haproxy_redis.sh [servers.tsv]
#
# Prérequis:
#   - Script 04_redis_03_deploy_sentinel.sh exécuté
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/redis.env"

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
echo " [KeyBuzz] Module 4 - Configuration HAProxy pour Redis"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds Redis et HAProxy
declare -a REDIS_NODES
declare -a REDIS_IPS
declare -a HAPROXY_NODES
declare -a HAPROXY_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "redis" ]] && \
       ([[ "${HOSTNAME}" == "redis-01" ]] || \
        [[ "${HOSTNAME}" == "redis-02" ]] || \
        [[ "${HOSTNAME}" == "redis-03" ]]); then
        REDIS_NODES+=("${HOSTNAME}")
        REDIS_IPS+=("${IP_PRIVEE}")
    fi
    
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]] && \
       ([[ "${HOSTNAME}" == "haproxy-01" ]] || [[ "${HOSTNAME}" == "haproxy-02" ]]); then
        HAPROXY_NODES+=("${HOSTNAME}")
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#REDIS_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds Redis incorrect: ${#REDIS_NODES[@]} (attendu: 3)"
    exit 1
fi

if [[ ${#HAPROXY_NODES[@]} -ne 2 ]]; then
    log_error "Nombre de nœuds HAProxy incorrect: ${#HAPROXY_NODES[@]} (attendu: 2)"
    exit 1
fi

# Détecter le master actuel via Sentinel
SENTINEL_IP="${REDIS_IPS[0]}"
CURRENT_MASTER=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${SENTINEL_IP}" \
    "timeout 3 redis-cli -h ${SENTINEL_IP} -p 26379 SENTINEL get-master-addr-by-name ${REDIS_MASTER_NAME} 2>/dev/null | head -1 || echo ''")

if [[ -z "${CURRENT_MASTER}" ]]; then
    log_warning "Impossible de détecter le master via Sentinel, utilisation de redis-01 par défaut"
    CURRENT_MASTER="${REDIS_IPS[0]}"
fi

log_info "Master Redis actuel détecté: ${CURRENT_MASTER}"
log_info "Sentinels: ${REDIS_IPS[*]}"
echo ""

# Extraire les valeurs AVANT les boucles SSH (pour les passer dans les heredocs)
SENT1_VAL="${REDIS_IPS[0]}"
SENT2_VAL="${REDIS_IPS[1]}"
SENT3_VAL="${REDIS_IPS[2]}"
NAME_VAL="${REDIS_MASTER_NAME}"

# Configurer HAProxy sur chaque nœud HAProxy
for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Configuration HAProxy sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    # Copier les credentials
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" "mkdir -p /opt/keybuzz-installer/credentials"
    scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${ip}:/opt/keybuzz-installer/credentials/"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -eo pipefail
# Retirer -u pour éviter les erreurs avec variables non initialisées dans heredoc

source /opt/keybuzz-installer/credentials/redis.env
BASE="/opt/keybuzz/redis-lb"

# Nettoyer les anciens conteneurs
docker stop haproxy-redis redis-sentinel-watcher 2>/dev/null || true
docker rm haproxy-redis redis-sentinel-watcher 2>/dev/null || true

# Créer les répertoires
mkdir -p "\${BASE}"/{config,bin,logs,status}

# Configuration HAProxy (bind sur IP privée)
cat > "\${BASE}/config/haproxy-redis.cfg" <<HAPROXY_CFG
global
    maxconn 10000
    log stdout local0

defaults
    mode tcp
    timeout connect 5s
    timeout client 30s
    timeout server 30s
    log global

listen redis_master
    bind ${ip}:6379
    mode tcp
    balance first
    option tcp-check
    tcp-check send AUTH\ \${REDIS_PASSWORD}\r\n
    tcp-check expect string +OK
    tcp-check send PING\r\n
    tcp-check expect string +PONG
    tcp-check send QUIT\r\n
    tcp-check expect string +OK
    server redis-master ${CURRENT_MASTER}:6379 check inter 2s fall 3 rise 2
HAPROXY_CFG

# Sauvegarder l'IP du master actuel
echo "${CURRENT_MASTER}" > "\${BASE}/status/current_master"

# Script watcher Sentinel (les valeurs sont passées depuis le script parent)
cat > "\${BASE}/bin/watcher.sh" <<WATCHER_SCRIPT
#!/bin/bash
set -o pipefail

BASE="/opt/keybuzz/redis-lb"
CFG="\${BASE}/config/haproxy-redis.cfg"
CUR="\${BASE}/status/current_master"
SENT1="${SENT1_VAL}"
SENT2="${SENT2_VAL}"
SENT3="${SENT3_VAL}"
NAME="${NAME_VAL}"
PASS="\${REDIS_PASSWORD}"

mkdir -p "\${BASE}/status"
mkdir -p "\${BASE}/logs"

while true; do
  # Essayer de détecter le master via les Sentinels (avec authentification)
  NEW=""
  NEW=\$(redis-cli -h \${SENT1} -p 26379 -a \${PASS} --no-auth-warning SENTINEL get-master-addr-by-name \${NAME} 2>/dev/null | sed -n '1p' || echo "")
  [ -z "\${NEW}" ] && NEW=\$(redis-cli -h \${SENT2} -p 26379 -a \${PASS} --no-auth-warning SENTINEL get-master-addr-by-name \${NAME} 2>/dev/null | sed -n '1p' || echo "")
  [ -z "\${NEW}" ] && NEW=\$(redis-cli -h \${SENT3} -p 26379 -a \${PASS} --no-auth-warning SENTINEL get-master-addr-by-name \${NAME} 2>/dev/null | sed -n '1p' || echo "")
  
  if [ -n "\${NEW}" ] && [ "\${NEW}" != "\$(cat "\${CUR}" 2>/dev/null || true)" ]; then
    # Mettre à jour la configuration HAProxy
    sed -i "s#^\s*server redis-master .*#    server redis-master \${NEW}:6379 check inter 2s fall 3 rise 2#" "\${CFG}"
    echo "\${NEW}" > "\${CUR}"
    
    # Recharger HAProxy
    docker kill -s HUP haproxy-redis >/dev/null 2>&1 || docker restart haproxy-redis >/dev/null 2>&1
    
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - Master changé: \${NEW}" >> "\${BASE}/logs/watcher.log"
    echo "Master Redis changé: \${NEW}"
  fi
  
  sleep 5
done
WATCHER_SCRIPT

chmod +x "\${BASE}/bin/watcher.sh"

# Démarrer HAProxy
docker run -d \
  --name haproxy-redis \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/config/haproxy-redis.cfg":/usr/local/etc/haproxy/haproxy.cfg:ro \
  haproxy:2.9-alpine

sleep 2

# Démarrer le watcher Sentinel
docker run -d \
  --name redis-sentinel-watcher \
  --restart unless-stopped \
  -v "\${BASE}":/opt/keybuzz/redis-lb \
  --network host \
  alpine:3.20 sh -c "apk add --no-cache redis bash >/dev/null 2>&1 && bash /opt/keybuzz/redis-lb/bin/watcher.sh"

sleep 2

# Vérifier que les conteneurs sont démarrés
if ! docker ps | grep -q "haproxy-redis"; then
    echo "  ✗ Échec du démarrage HAProxy"
    docker logs haproxy-redis --tail 10 2>&1 || true
    echo "ERROR" > "\${BASE}/status/STATE"
    exit 1
fi

if ! docker ps | grep -q "redis-sentinel-watcher"; then
    echo "  ✗ Échec du démarrage du watcher Sentinel"
    docker logs redis-sentinel-watcher --tail 20 2>&1 || true
    echo "ERROR" > "\${BASE}/status/STATE"
    exit 1
fi

echo "  ✓ HAProxy démarré"
echo "  ✓ Watcher Sentinel démarré"
echo "OK" > "\${BASE}/status/STATE"

# Test de connexion HAProxy
if timeout 3 redis-cli -h ${ip} -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
    echo "  ✓ HAProxy répond correctement"
else
    echo "  ⚠ HAProxy ne répond pas encore (peut être normal au démarrage)"
fi
EOF

    if [ $? -eq 0 ]; then
        log_success "HAProxy configuré avec succès sur ${hostname}"
    else
        log_error "Échec de la configuration HAProxy sur ${hostname}"
        exit 1
    fi
    echo ""
done

# Vérification finale
log_info "Vérification finale de HAProxy..."

for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    if timeout 3 redis-cli -h "${ip}" -p 6379 -a "${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"; then
        log_success "${hostname}: HAProxy opérationnel"
    else
        log_warning "${hostname}: HAProxy ne répond pas (peut nécessiter quelques secondes)"
    fi
done

echo ""
echo "=============================================================="
log_success "✅ Configuration HAProxy pour Redis terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - HAProxy déployé sur: ${HAPROXY_NODES[*]}"
log_info "  - Master Redis actuel: ${CURRENT_MASTER}"
log_info "  - Watcher Sentinel: Actif sur chaque HAProxy"
log_info ""
log_info "Points d'accès:"
log_info "  - haproxy-01: ${HAPROXY_IPS[0]}:6379"
log_info "  - haproxy-02: ${HAPROXY_IPS[1]}:6379"
log_info ""
log_info "Prochaine étape: Configurer le LB healthcheck"
log_info "  ./04_redis_05_configure_lb_healthcheck.sh"
echo ""

