#!/usr/bin/env bash
#
# 04_redis_05_configure_lb_healthcheck.sh - Configuration LB Healthcheck
#
# Ce script configure le mécanisme de healthcheck pour le LB Hetzner.
# Il crée le fichier /opt/keybuzz/redis-lb/status/STATE sur haproxy-01/02
# et met en place un script de monitoring qui met à jour ce fichier.
#
# Usage:
#   ./04_redis_05_configure_lb_healthcheck.sh [servers.tsv]
#
# Prérequis:
#   - Script 04_redis_04_configure_haproxy_redis.sh exécuté
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
echo " [KeyBuzz] Module 4 - Configuration LB Healthcheck"
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

# Configurer le healthcheck sur chaque HAProxy
for i in "${!HAPROXY_NODES[@]}"; do
    hostname="${HAPROXY_NODES[$i]}"
    ip="${HAPROXY_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Configuration healthcheck sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<REMOTE_SCRIPT
set -eo pipefail

source /opt/keybuzz-installer/credentials/redis.env
BASE="/opt/keybuzz/redis-lb"

# Créer les répertoires
mkdir -p "\${BASE}"/{bin,status,logs}

# Créer le script healthcheck directement avec les bonnes valeurs
cat > "\${BASE}/bin/healthcheck.sh" <<HEALTHCHECK_EOF
#!/bin/bash
set -o pipefail

BASE="/opt/keybuzz/redis-lb"
STATE_FILE="\${BASE}/status/STATE"
REDIS_IPS="${REDIS_IPS[*]}"
SENTINEL_IPS="${REDIS_IPS[*]}"
MASTER_NAME="${REDIS_MASTER_NAME}"
REDIS_PASSWORD="\${REDIS_PASSWORD}"

# Initialiser les compteurs
REDIS_OK=0
SENTINEL_OK=0
HAPROXY_OK=0

# Fonction pour vérifier Redis
check_redis() {
    local ip=\$1
    timeout 2 redis-cli -h "\${ip}" -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"
}

# Fonction pour vérifier Sentinel
check_sentinel() {
    local ip=\$1
    timeout 2 redis-cli -h "\${ip}" -p 26379 SENTINEL get-master-addr-by-name "\${MASTER_NAME}" 2>/dev/null | head -1 | grep -q "."
}

# Fonction pour vérifier HAProxy
check_haproxy() {
    docker ps | grep -q "haproxy-redis"
}

# Vérifier les nœuds Redis
for ip in \${REDIS_IPS}; do
    if check_redis "\${ip}"; then
        REDIS_OK=\$((REDIS_OK + 1))
    fi
done

# Vérifier les Sentinels
for ip in \${SENTINEL_IPS}; do
    if check_sentinel "\${ip}"; then
        SENTINEL_OK=\$((SENTINEL_OK + 1))
    fi
done

# Vérifier HAProxy
if check_haproxy; then
    HAPROXY_OK=1
fi

# Déterminer l'état
if [ "\${REDIS_OK}" -ge 2 ] && [ "\${SENTINEL_OK}" -ge 2 ] && [ "\${HAPROXY_OK}" -eq 1 ]; then
    echo "OK" > "\${STATE_FILE}"
    exit 0
elif [ "\${REDIS_OK}" -ge 1 ] && [ "\${SENTINEL_OK}" -ge 1 ]; then
    echo "DEGRADED" > "\${STATE_FILE}"
    exit 0
else
    echo "ERROR" > "\${STATE_FILE}"
    exit 1
fi
HEALTHCHECK_EOF
#!/bin/bash
set -u
set -o pipefail

BASE="/opt/keybuzz/redis-lb"
STATE_FILE="\${BASE}/status/STATE"
REDIS_IPS="${REDIS_IPS[*]}"
SENTINEL_IPS="${REDIS_IPS[*]}"
MASTER_NAME="${REDIS_MASTER_NAME}"
REDIS_PASSWORD="${REDIS_PASSWORD}"

# Initialiser les compteurs
REDIS_OK=0
SENTINEL_OK=0
HAPROXY_OK=0
STATE_FILE="\${BASE}/status/STATE"

# Fonction pour vérifier Redis
check_redis() {
    local ip=\$1
    timeout 2 redis-cli -h "\${ip}" -p 6379 -a "\${REDIS_PASSWORD}" --no-auth-warning PING 2>/dev/null | grep -q "PONG"
}

# Fonction pour vérifier Sentinel
check_sentinel() {
    local ip=\$1
    timeout 2 redis-cli -h "\${ip}" -p 26379 SENTINEL get-master-addr-by-name "\${MASTER_NAME}" 2>/dev/null | head -1 | grep -q "."
}

# Fonction pour vérifier HAProxy
check_haproxy() {
    docker ps | grep -q "haproxy-redis"
}

# Vérifier les nœuds Redis
for ip in \${REDIS_IPS}; do
    if check_redis "\${ip}"; then
        REDIS_OK=\$(expr \${REDIS_OK} + 1)
    fi
done

# Vérifier les Sentinels
for ip in \${SENTINEL_IPS}; do
    if check_sentinel "\${ip}"; then
        SENTINEL_OK=\$(expr \${SENTINEL_OK} + 1)
    fi
done

# Vérifier HAProxy
if check_haproxy; then
    HAPROXY_OK=1
fi

# Déterminer l'état
if [ \${REDIS_OK} -ge 2 ] && [ \${SENTINEL_OK} -ge 2 ] && [ \${HAPROXY_OK} -eq 1 ]; then
    echo "OK" > "\${STATE_FILE}"
    exit 0
elif [ \${REDIS_OK} -ge 1 ] && [ \${SENTINEL_OK} -ge 1 ]; then
    echo "DEGRADED" > "\${STATE_FILE}"
    exit 0
else
    echo "ERROR" > "\${STATE_FILE}"
    exit 1
fi
chmod +x "\${BASE}/bin/healthcheck.sh"

# Exécuter le healthcheck initial
"\${BASE}/bin/healthcheck.sh"
CURRENT_STATE=\$(cat "\${BASE}/status/STATE" 2>/dev/null || echo "UNKNOWN")

echo "  État actuel: \${CURRENT_STATE}"

# Créer un service systemd pour le healthcheck (optionnel, pour monitoring continu)
cat > /etc/systemd/system/redis-lb-healthcheck.service <<SYSTEMD_SERVICE
[Unit]
Description=Redis LB Healthcheck
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=\${BASE}/bin/healthcheck.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SYSTEMD_SERVICE

# Créer un timer pour exécuter le healthcheck toutes les 10 secondes
cat > /etc/systemd/system/redis-lb-healthcheck.timer <<SYSTEMD_TIMER
[Unit]
Description=Redis LB Healthcheck Timer
Requires=redis-lb-healthcheck.service

[Timer]
OnBootSec=10s
OnUnitActiveSec=10s

[Install]
WantedBy=timers.target
SYSTEMD_TIMER

systemctl daemon-reload
systemctl enable redis-lb-healthcheck.timer
systemctl start redis-lb-healthcheck.timer

echo "  ✓ Healthcheck configuré et démarré"
REMOTE_SCRIPT

    if [ $? -eq 0 ]; then
        log_success "Healthcheck configuré avec succès sur ${hostname}"
        
        # Vérifier l'état
        CURRENT_STATE=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
            "cat /opt/keybuzz/redis-lb/status/STATE 2>/dev/null || echo 'UNKNOWN'")
        log_info "  État: ${CURRENT_STATE}"
    else
        log_error "Échec de la configuration du healthcheck sur ${hostname}"
        exit 1
    fi
    echo ""
done

echo "=============================================================="
log_success "✅ Configuration LB Healthcheck terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Healthcheck configuré sur: ${HAPROXY_NODES[*]}"
log_info "  - Fichier d'état: /opt/keybuzz/redis-lb/status/STATE"
log_info "  - Timer systemd: Exécution toutes les 10 secondes"
log_info ""
log_info "États possibles:"
log_info "  - OK: Cluster Redis opérationnel (≥2 Redis, ≥2 Sentinel, HAProxy)"
log_info "  - DEGRADED: Cluster partiellement opérationnel (≥1 Redis, ≥1 Sentinel)"
log_info "  - ERROR: Cluster non opérationnel"
log_info ""
log_info "Note: Le LB Hetzner (10.0.0.10) peut utiliser ce fichier pour ses health-checks"
log_info ""
log_info "Prochaine étape: Exécuter les tests"
log_info "  ./04_redis_06_tests.sh ${TSV_FILE}"
echo ""

