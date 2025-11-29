#!/usr/bin/env bash
#
# 05_rmq_01_prepare_nodes.sh - Préparation des nœuds RabbitMQ
#
# Ce script prépare les nœuds RabbitMQ en créant les répertoires nécessaires,
# configurant le cookie Erlang, et vérifiant les prérequis.
#
# Usage:
#   ./05_rmq_01_prepare_nodes.sh [servers.tsv]
#
# Prérequis:
#   - Script 05_rmq_00_setup_credentials.sh exécuté
#   - Module 2 appliqué sur tous les serveurs RabbitMQ
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/rabbitmq.env"

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
    log_info "Exécutez d'abord: ./05_rmq_00_setup_credentials.sh"
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
echo " [KeyBuzz] Module 5 - Préparation des nœuds RabbitMQ"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds RabbitMQ
declare -a RABBITMQ_NODES
declare -a RABBITMQ_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" != "queue" ]] || [[ "${SUBROLE}" != "rabbitmq" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "queue-01" ]] || \
       [[ "${HOSTNAME}" == "queue-02" ]] || \
       [[ "${HOSTNAME}" == "queue-03" ]]; then
        RABBITMQ_NODES+=("${HOSTNAME}")
        RABBITMQ_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#RABBITMQ_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds RabbitMQ incorrect: ${#RABBITMQ_NODES[@]} (attendu: 3)"
    exit 1
fi

log_success "${#RABBITMQ_NODES[@]} nœuds RabbitMQ trouvés: ${RABBITMQ_NODES[*]}"
echo ""

# Préparer chaque nœud
for i in "${!RABBITMQ_NODES[@]}"; do
    hostname="${RABBITMQ_NODES[$i]}"
    ip="${RABBITMQ_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Préparation de ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

BASE="/opt/keybuzz/rabbitmq"

# Nettoyer les anciens conteneurs
docker stop rabbitmq 2>/dev/null || true
docker rm rabbitmq 2>/dev/null || true

# Créer les répertoires
mkdir -p "\${BASE}"/{data,log,conf}

# Vérifier le volume XFS (si monté)
if mountpoint -q "\${BASE}/data" 2>/dev/null; then
    echo "  ✓ Volume XFS monté sur \${BASE}/data"
    df -h "\${BASE}/data" | tail -1 | awk '{print "  Espace disponible: " \$4}'
else
    echo "  ⚠ Volume XFS non monté (optionnel pour RabbitMQ)"
fi

# Créer le cookie Erlang (doit être identique sur tous les nœuds)
# Note: Les permissions doivent être 400 et le propriétaire doit être rabbitmq (UID 999)
echo "${RABBITMQ_ERLANG_COOKIE}" > "\${BASE}/.erlang.cookie"
chmod 400 "\${BASE}/.erlang.cookie"
# Essayer de changer le propriétaire, mais ce n'est pas critique si ça échoue
# Le conteneur créera le cookie avec les bonnes permissions si nécessaire
chown 999:999 "\${BASE}/.erlang.cookie" 2>/dev/null || true

# Vérifier Docker
if ! command -v docker >/dev/null 2>&1; then
    echo "  ✗ Docker non installé"
    exit 1
fi

if ! systemctl is-active --quiet docker; then
    echo "  ✗ Docker non démarré"
    exit 1
fi

echo "  ✓ Docker opérationnel"

# Vérifier les ports UFW (optionnel, mais recommandé)
if command -v ufw >/dev/null 2>&1; then
    echo "  ✓ UFW disponible"
else
    echo "  ⚠ UFW non disponible"
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
log_success "✅ Préparation des nœuds RabbitMQ terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœuds préparés: ${#RABBITMQ_NODES[@]}"
log_info "  - Cookie Erlang: Configuré sur tous les nœuds"
log_info ""
log_info "Prochaine étape: Déployer le cluster RabbitMQ"
log_info "  ./05_rmq_02_deploy_cluster.sh ${TSV_FILE}"
echo ""

