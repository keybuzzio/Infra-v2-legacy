#!/usr/bin/env bash
#
# 06_minio_01_prepare_nodes.sh - Préparation des nœuds MinIO
#
# Ce script prépare les nœuds MinIO en créant les répertoires nécessaires
# et vérifiant les prérequis (XFS, espace disque, Docker).
#
# Usage:
#   ./06_minio_01_prepare_nodes.sh [servers.tsv]
#
# Prérequis:
#   - Script 06_minio_00_setup_credentials.sh exécuté
#   - Module 2 appliqué sur tous les serveurs MinIO
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
    log_info "Exécutez d'abord: ./06_minio_00_setup_credentials.sh"
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
echo " [KeyBuzz] Module 6 - Préparation des nœuds MinIO"
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
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" != "storage" ]] || [[ "${SUBROLE}" != "minio" ]]; then
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
    log_info "Vérifiez que ROLE=storage et SUBROLE=minio"
    exit 1
fi

log_success "${#MINIO_NODES[@]} nœud(s) MinIO trouvé(s): ${MINIO_NODES[*]}"
echo ""

# Préparer chaque nœud
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    log_info "--------------------------------------------------------------"
    log_info "Préparation de ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

BASE="/opt/keybuzz/minio"

# Nettoyer les anciens conteneurs
docker stop minio 2>/dev/null || true
docker rm minio 2>/dev/null || true

# Créer les répertoires
mkdir -p "\${BASE}"/{data,config,logs}

# Définir les permissions (UID 1000 = utilisateur minio dans le conteneur)
chown -R 1000:1000 "\${BASE}"

# Vérifier le volume XFS (si monté)
if mountpoint -q "\${BASE}/data" 2>/dev/null; then
    echo "  ✓ Volume XFS monté sur \${BASE}/data"
    df -h "\${BASE}/data" | tail -1 | awk '{print "  Espace disponible: " \$4}'
else
    # Vérifier le filesystem du répertoire parent
    FS_TYPE=\$(df -T "\${BASE}" | tail -1 | awk '{print \$2}')
    if [[ "\${FS_TYPE}" == "xfs" ]]; then
        echo "  ✓ Filesystem XFS détecté"
    else
        echo "  ⚠ Filesystem: \${FS_TYPE} (XFS recommandé)"
    fi
    df -h "\${BASE}" | tail -1 | awk '{print "  Espace disponible: " \$4}'
fi

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
log_success "✅ Préparation des nœuds MinIO terminée !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœuds préparés: ${#MINIO_NODES[@]}"
log_info ""
log_info "Prochaine étape: Installer MinIO (mono-nœud ou cluster)"
log_info "  ./06_minio_02_install_single.sh ${TSV_FILE}"
echo ""

