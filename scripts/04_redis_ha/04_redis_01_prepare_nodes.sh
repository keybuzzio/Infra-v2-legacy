#!/usr/bin/env bash
#
# 04_redis_01_prepare_nodes.sh - Préparation des nœuds Redis
#
# Ce script prépare les nœuds Redis en créant les répertoires nécessaires,
# générant les fichiers de configuration redis.conf de base, et vérifiant
# les prérequis (XFS, espace disque, Docker).
#
# Usage:
#   ./04_redis_01_prepare_nodes.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur redis-01/02/03
#   - Credentials configurés (04_redis_00_setup_credentials.sh)
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
    log_info "Exécutez d'abord: ./04_redis_00_setup_credentials.sh"
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
echo " [KeyBuzz] Module 4 - Préparation des nœuds Redis"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds Redis
declare -a REDIS_NODES
declare -a REDIS_IPS
declare -a REDIS_ROLES

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod et ROLE=redis
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "redis" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    # Filtrer uniquement les 3 nœuds Redis principaux
    if [[ "${HOSTNAME}" == "redis-01" ]] || \
       [[ "${HOSTNAME}" == "redis-02" ]] || \
       [[ "${HOSTNAME}" == "redis-03" ]]; then
        REDIS_NODES+=("${HOSTNAME}")
        REDIS_IPS+=("${IP_PRIVEE}")
        REDIS_ROLES+=("${SUBROLE}")
    fi
done
exec 3<&-

if [[ ${#REDIS_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds Redis incorrect: ${#REDIS_NODES[@]} (attendu: 3)"
    exit 1
fi

log_success "${#REDIS_NODES[@]} nœuds Redis trouvés: ${REDIS_NODES[*]}"
echo ""

# Trouver le master initial
MASTER_IP=""
MASTER_NODE=""
for i in "${!REDIS_NODES[@]}"; do
    if [[ "${REDIS_ROLES[$i]}" == "master" ]]; then
        MASTER_NODE="${REDIS_NODES[$i]}"
        MASTER_IP="${REDIS_IPS[$i]}"
        break
    fi
done

if [[ -z "${MASTER_IP}" ]]; then
    # Par défaut, redis-01 est le master
    MASTER_NODE="redis-01"
    for i in "${!REDIS_NODES[@]}"; do
        if [[ "${REDIS_NODES[$i]}" == "redis-01" ]]; then
            MASTER_IP="${REDIS_IPS[$i]}"
            break
        fi
    done
fi

log_info "Master initial: ${MASTER_NODE} (${MASTER_IP})"
echo ""

# Préparer chaque nœud
for i in "${!REDIS_NODES[@]}"; do
    hostname="${REDIS_NODES[$i]}"
    ip="${REDIS_IPS[$i]}"
    role="${REDIS_ROLES[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Préparation de ${hostname} (${ip}) - Rôle: ${role}"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

BASE_DIR="/opt/keybuzz/redis"

# Créer les répertoires
mkdir -p "\${BASE_DIR}"/{data,conf,log,status}
chmod 755 "\${BASE_DIR}"/{data,conf,log,status}

# Vérifier le système de fichiers (XFS recommandé)
if mountpoint -q "\${BASE_DIR}/data" 2>/dev/null; then
    FS_TYPE=\$(df -T "\${BASE_DIR}/data" | tail -1 | awk '{print \$2}')
    if [[ "\${FS_TYPE}" == "xfs" ]]; then
        echo "  ✓ Volume XFS monté sur \${BASE_DIR}/data"
    else
        echo "  ⚠ Volume monté en \${FS_TYPE} (XFS recommandé)"
    fi
else
    echo "  ⚠ Aucun volume monté sur \${BASE_DIR}/data"
    echo "  → Utilisation du système de fichiers local"
fi

# Vérifier l'espace disque
AVAILABLE=\$(df -h "\${BASE_DIR}/data" | tail -1 | awk '{print \$4}')
echo "  Espace disponible: \${AVAILABLE}"

# Générer redis.conf de base
# Note: bind utilise l'IP privée pour la sécurité (conforme aux anciens scripts)
cat > "\${BASE_DIR}/conf/redis.conf" <<REDIS_CONF
# Redis Configuration - Généré automatiquement
# Hostname: ${hostname}
# IP: ${ip}
# Rôle: ${role}

bind ${ip}
port 6379
protected-mode yes
requirepass ${REDIS_PASSWORD}
masterauth ${REDIS_PASSWORD}

# Persistence
appendonly yes
appendfsync everysec
dir /data

# Performance
maxmemory-policy allkeys-lru
timeout 300
tcp-keepalive 60

# Logging
loglevel notice
# logfile /var/log/redis/redis.log  # Désactivé car le répertoire n'existe pas dans le conteneur

# Réplication (sera configurée pour les replicas)
$(if [[ "${role}" == "replica" ]]; then
    echo "replicaof ${MASTER_IP} 6379"
fi)
REDIS_CONF

chmod 644 "\${BASE_DIR}/conf/redis.conf"

# Nettoyer les anciens conteneurs
docker stop redis redis-sentinel 2>/dev/null || true
docker rm redis redis-sentinel 2>/dev/null || true

# Vérifier Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "  ✗ Docker non installé"
    exit 1
fi

echo "  ✓ ${hostname} préparé"
EOF

    if [ $? -eq 0 ]; then
        log_success "${hostname} préparé avec succès"
    else
        log_error "Échec de la préparation de ${hostname}"
        exit 1
    fi
    echo ""
done

echo "=============================================================="
log_success "✅ Préparation des nœuds Redis terminée !"
echo "=============================================================="
echo ""

