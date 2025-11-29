#!/usr/bin/env bash
#
# 06_minio_02_install_single.sh - Installation MinIO mono-nœud
#
# Ce script installe MinIO en mode mono-nœud sur le premier nœud MinIO.
# Ce mode est simple et opérationnel pour démarrer.
#
# Usage:
#   ./06_minio_02_install_single.sh [servers.tsv]
#
# Prérequis:
#   - Script 06_minio_01_prepare_nodes.sh exécuté
#   - Credentials configurés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/minio.env"

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
echo " [KeyBuzz] Module 6 - Installation MinIO Mono-Nœud"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds MinIO
declare -a MINIO_NODES
declare -a MINIO_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "storage" ]] || [[ "${SUBROLE}" != "minio" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    MINIO_NODES+=("${HOSTNAME}")
    MINIO_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

if [[ ${#MINIO_NODES[@]} -eq 0 ]]; then
    log_error "Aucun nœud MinIO trouvé dans servers.tsv"
    exit 1
fi

# Utiliser le premier nœud pour l'installation mono-nœud
FIRST_NODE="${MINIO_NODES[0]}"
FIRST_IP="${MINIO_IPS[0]}"

log_info "Installation MinIO mono-nœud sur ${FIRST_NODE} (${FIRST_IP})"
echo ""

# Copier les credentials sur le nœud
log_info "Copie des credentials sur ${FIRST_NODE}..."
ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${FIRST_IP}" "mkdir -p /opt/keybuzz-installer/credentials"
scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${FIRST_IP}:/opt/keybuzz-installer/credentials/"
log_success "Credentials copiés"
echo ""

# Installer MinIO
log_info "Déploiement de MinIO..."

ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${FIRST_IP}" bash <<EOF
set -euo pipefail

source /opt/keybuzz-installer/credentials/minio.env
BASE="/opt/keybuzz/minio"

# Nettoyer les anciens conteneurs
docker stop minio 2>/dev/null || true
docker rm minio 2>/dev/null || true

# Déployer MinIO (mono-nœud)
# Note: Utiliser --network host pour éviter les problèmes de binding IP
docker run -d --name minio \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/data":/data \
  -v "\${BASE}/config":/root/.minio \
  -e MINIO_ROOT_USER="\${MINIO_ROOT_USER}" \
  -e MINIO_ROOT_PASSWORD="\${MINIO_ROOT_PASSWORD}" \
  minio/minio server /data --console-address ":9001" --address "${FIRST_IP}:9000"

sleep 5

# Vérifier que MinIO est démarré
if docker ps | grep -q "minio"; then
    echo "  ✓ MinIO démarré"
else
    echo "  ✗ Échec du démarrage MinIO"
    docker logs minio --tail 20 2>&1 || true
    exit 1
fi

# Attendre que MinIO soit prêt
echo "  Attente que MinIO soit prêt (10 secondes)..."
sleep 10

# Vérifier que MinIO répond
if timeout 3 curl -s -f http://localhost:9000/minio/health/live >/dev/null 2>&1; then
    echo "  ✓ MinIO répond correctement"
else
    echo "  ⚠ MinIO ne répond pas encore (peut être normal au démarrage)"
fi
EOF

if [ $? -eq 0 ]; then
    log_success "MinIO installé avec succès sur ${FIRST_NODE}"
else
    log_error "Échec de l'installation de MinIO"
    exit 1
fi

# Attendre la stabilisation
log_info "Attente de la stabilisation de MinIO (5 secondes)..."
sleep 5

# Vérification finale
log_info "Vérification finale..."

if timeout 3 curl -s -f "http://${FIRST_IP}:9000/minio/health/live" >/dev/null 2>&1; then
    log_success "MinIO opérationnel sur ${FIRST_IP}:9000"
else
    log_warning "MinIO ne répond pas encore (peut nécessiter quelques secondes)"
fi

echo ""
echo "=============================================================="
log_success "✅ Installation MinIO mono-nœud terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœud: ${FIRST_NODE} (${FIRST_IP})"
log_info "  - S3 API: http://${FIRST_IP}:9000"
log_info "  - Console: http://${FIRST_IP}:9001"
log_info ""
log_info "Prochaine étape: Configurer le client mc et créer le bucket"
log_info "  ./06_minio_03_configure_client.sh ${TSV_FILE}"
echo ""

