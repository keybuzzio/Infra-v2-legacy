#!/usr/bin/env bash
#
# Script de nettoyage complet des données MinIO
# Supprime tous les fichiers, y compris format.json et .minio.sys
#

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

# Parser servers.tsv pour obtenir les nœuds MinIO
MINIO_NODES=()
MINIO_IPS=()

while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
    if [[ "${role}" == "storage" ]] && [[ "${subrole}" == "minio" ]]; then
        MINIO_NODES+=("${hostname}")
        MINIO_IPS+=("${ip_priv}")
    fi
done < <(tail -n +2 "${TSV_FILE}")

if [[ ${#MINIO_NODES[@]} -eq 0 ]]; then
    log_error "Aucun nœud MinIO trouvé dans ${TSV_FILE}"
    exit 1
fi

log_info "Nettoyage complet des données MinIO sur ${#MINIO_NODES[@]} nœuds..."

# Nettoyer chaque nœud
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    log_info "Nettoyage de ${hostname} (${ip})..."
    
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<'EOF'
        # Arrêter et supprimer le conteneur
        docker stop minio 2>/dev/null || true
        docker rm -f minio 2>/dev/null || true
        
        # Supprimer complètement le répertoire de données
        if [[ -d "/opt/keybuzz/minio/data" ]]; then
            rm -rf /opt/keybuzz/minio/data/*
            rm -rf /opt/keybuzz/minio/data/.* 2>/dev/null || true
            # Supprimer aussi .minio.sys si présent
            find /opt/keybuzz/minio/data -type d -name ".minio.sys" -exec rm -rf {} + 2>/dev/null || true
            find /opt/keybuzz/minio/data -name "format.json" -delete 2>/dev/null || true
            find /opt/keybuzz/minio/data -name ".format.json" -delete 2>/dev/null || true
            echo "  ✓ Données nettoyées"
        else
            echo "  ✓ Répertoire de données n'existe pas"
        fi
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Nettoyage terminé sur ${hostname}"
    else
        log_error "Échec du nettoyage sur ${hostname}"
    fi
done

log_success "Nettoyage complet terminé sur tous les nœuds MinIO"

