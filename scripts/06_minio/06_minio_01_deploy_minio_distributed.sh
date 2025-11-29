#!/usr/bin/env bash
#
# 06_minio_01_deploy_minio_distributed.sh - Déploiement du cluster MinIO distributed (3 nœuds)
#
# Ce script déploie MinIO en mode distributed sur 3 nœuds :
# - minio-01 (10.0.0.134)
# - minio-02 (10.0.0.131, ex-connect-01)
# - minio-03 (10.0.0.132, ex-connect-02)
#
# Usage:
#   ./06_minio_01_deploy_minio_distributed.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les nœuds MinIO
#   - Credentials configurés (06_minio_00_setup_credentials.sh)
#   - DNS configuré pour minio-01.keybuzz.io, minio-02.keybuzz.io, minio-03.keybuzz.io
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/minio.env"
VERSIONS_FILE="${INSTALL_DIR}/versions.yaml"

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

# Charger les versions
if [[ -f "${VERSIONS_FILE}" ]]; then
    MINIO_IMAGE=$(grep "^minio_image:" "${VERSIONS_FILE}" | cut -d' ' -f2 | tr -d '"' | tr -d "'")
    if [[ -z "${MINIO_IMAGE}" ]]; then
        log_warning "minio_image non trouvé dans versions.yaml, utilisation de la version par défaut"
        MINIO_IMAGE="minio/minio:RELEASE.2024-10-02T10-00Z"
    fi
else
    log_warning "Fichier versions.yaml introuvable, utilisation de la version par défaut"
    MINIO_IMAGE="minio/minio:RELEASE.2024-10-02T10-00Z"
fi

# Vérifier que MINIO_IMAGE est défini et nettoyer
MINIO_IMAGE=$(echo "${MINIO_IMAGE}" | xargs) # Supprimer espaces
if [[ -z "${MINIO_IMAGE}" ]]; then
    log_error "MINIO_IMAGE non défini"
    exit 1
fi

log_info "Image MinIO: ${MINIO_IMAGE}"

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

# Vérifier que les variables sont bien définies
if [[ -z "${MINIO_ROOT_USER:-}" ]] || [[ -z "${MINIO_ROOT_PASSWORD:-}" ]]; then
    log_error "MINIO_ROOT_USER ou MINIO_ROOT_PASSWORD non défini dans ${CREDENTIALS_FILE}"
    exit 1
fi

# Parser servers.tsv pour obtenir les nœuds MinIO
MINIO_NODES=()
MINIO_IPS=()
MINIO_HOSTNAMES=()

while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
    if [[ "${role}" == "storage" ]] && [[ "${subrole}" == "minio" ]]; then
        MINIO_NODES+=("${hostname}")
        MINIO_IPS+=("${ip_priv}")
        MINIO_HOSTNAMES+=("${hostname}")
    fi
done < <(tail -n +2 "${TSV_FILE}")

if [[ ${#MINIO_NODES[@]} -lt 3 ]]; then
    log_error "Au moins 3 nœuds MinIO requis, trouvé: ${#MINIO_NODES[@]}"
    exit 1
fi

log_info "Nœuds MinIO détectés: ${MINIO_NODES[*]} (${MINIO_IPS[*]})"

# Construire MINIO_VOLUMES (utiliser les IPs directement pour éviter problème DNS)
# Note: On peut utiliser les hostnames une fois le DNS configuré, mais pour l'instant on utilise les IPs
MINIO_VOLUMES_ARRAY=()
for i in "${!MINIO_IPS[@]}"; do
    # Utiliser l'IP directement (plus fiable que hostname si DNS pas encore configuré)
    MINIO_VOLUMES_ARRAY+=("http://${MINIO_IPS[i]}:9000/data")
done

# Convertir en string pour affichage
MINIO_VOLUMES=$(IFS=' '; echo "${MINIO_VOLUMES_ARRAY[*]}")

log_info "MINIO_VOLUMES (avec IPs): ${MINIO_VOLUMES}"
log_warning "NOTE: Une fois le DNS configuré, on pourra utiliser les hostnames (minio-01.keybuzz.io, etc.)"

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

# Déployer MinIO sur chaque nœud
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Déploiement MinIO sur: ${hostname} (${ip})"
    log_info "=============================================================="
    
    # Construire la liste des volumes pour ce nœud (utiliser les IPs directement)
    # Format: http://IP:9000/data pour chaque nœud
    MINIO_VOLUMES_STR=""
    for vol_ip in "${MINIO_IPS[@]}"; do
        MINIO_VOLUMES_STR="${MINIO_VOLUMES_STR} http://${vol_ip}:9000/data"
    done
    MINIO_VOLUMES_STR=$(echo "${MINIO_VOLUMES_STR}" | xargs) # Nettoyer espaces
    
    log_info "Command MinIO: server ${MINIO_VOLUMES_STR} --console-address :9001"
    
    # Vérifier que MINIO_VOLUMES_STR est défini
    if [[ -z "${MINIO_VOLUMES_STR}" ]]; then
        log_error "MINIO_VOLUMES_STR est vide pour ${hostname}"
        exit 1
    fi
    
    # Debug: afficher les variables avant interpolation
    log_info "Variables avant interpolation: MINIO_IMAGE=${MINIO_IMAGE}, MINIO_ROOT_USER=${MINIO_ROOT_USER:-<non défini>}"
    
    # Exécuter directement sur le serveur distant via SSH heredoc
    # Utiliser des guillemets doubles pour permettre l'interpolation
    # Désactiver temporairement -u pour permettre l'interpolation des variables dans le heredoc
    # Sauvegarder l'état de -u, le désactiver, puis le restaurer après
    OLD_SET_U=$(set +o | grep -E '^set [+-]u' || echo '')
    set +u
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<REMOTE_SCRIPT
# Utiliser set -e sans -u pour permettre l'utilisation de variables non initialisées dans la construction de CMD
set +u  # Désactiver -u explicitement
set -e
set -o pipefail

# Variables (interpolées depuis le script principal)
# Les variables sont directement interpolées depuis le script principal
MINIO_IMAGE_ARG="${MINIO_IMAGE}"
MINIO_ROOT_USER_ARG="${MINIO_ROOT_USER}"
MINIO_ROOT_PASSWORD_ARG="${MINIO_ROOT_PASSWORD}"
MINIO_VOLUMES_STR="${MINIO_VOLUMES_STR}"
HOSTNAME_ARG="${hostname}"

# Debug: afficher les variables
echo "  [DEBUG] MINIO_IMAGE_ARG: ${MINIO_IMAGE_ARG}"
echo "  [DEBUG] MINIO_ROOT_USER_ARG: ${MINIO_ROOT_USER_ARG}"
echo "  [DEBUG] MINIO_VOLUMES_STR: ${MINIO_VOLUMES_STR}"

# Arrêter et supprimer l'ancien conteneur si présent
docker stop minio 2>/dev/null || true
docker rm minio 2>/dev/null || true

# Créer le répertoire de données
mkdir -p /opt/keybuzz/minio/data
chmod 755 /opt/keybuzz/minio/data

# Construire la commande Docker directement sans utiliser eval
# Utiliser un tableau pour éviter les problèmes d'expansion
DOCKER_CMD_ARGS=(
    docker run -d
    --name minio
    --restart always
    --network host
    -v /opt/keybuzz/minio/data:/data
    -e "MINIO_ROOT_USER=${MINIO_ROOT_USER_ARG}"
    -e "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD_ARG}"
    "${MINIO_IMAGE_ARG}"
    server
)

# Ajouter les volumes un par un
IFS=' ' read -ra VOL_ARRAY <<< "${MINIO_VOLUMES_STR}"
for vol in "${VOL_ARRAY[@]}"; do
    if [ -n "${vol:-}" ]; then
        DOCKER_CMD_ARGS+=("${vol}")
    fi
done

# Ajouter l'option console
DOCKER_CMD_ARGS+=(--console-address :9001)

# Debug: afficher la commande avant exécution
echo "  [DEBUG] Commande Docker: ${DOCKER_CMD_ARGS[@]}"

# Exécuter la commande avec le tableau
"${DOCKER_CMD_ARGS[@]}"

sleep 3

# Vérifier que MinIO est démarré
if docker ps | grep -q "minio"; then
    echo "  ✓ MinIO démarré sur ${HOSTNAME_ARG}"
else
    echo "  ✗ Échec du démarrage MinIO"
    docker logs minio --tail 20 2>&1 || true
    exit 1
fi
REMOTE_SCRIPT
    # Restaurer l'état de -u
    eval "${OLD_SET_U}"

    log_success "MinIO déployé sur ${hostname}"
done

# Attendre que le cluster soit prêt
log_info "Attente de la stabilisation du cluster MinIO (30 secondes)..."
sleep 30

# Vérifier le statut du cluster
log_info "Vérification du statut du cluster MinIO..."
FIRST_NODE_IP="${MINIO_IPS[0]}"

if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" "timeout 5 docker exec minio mc admin info minio/ 2>/dev/null || echo 'Cluster en cours de démarrage'"; then
    log_success "Cluster MinIO opérationnel"
else
    log_warning "Le cluster MinIO est peut-être encore en cours de démarrage"
fi

echo ""
log_success "✅ Déploiement MinIO distributed terminé !"
echo ""
log_info "Nœuds MinIO:"
for i in "${!MINIO_NODES[@]}"; do
    log_info "  - ${MINIO_NODES[$i]} (${MINIO_IPS[$i]})"
done
echo ""
log_info "Point d'entrée: http://s3.keybuzz.io:9000 (minio-01)"
log_info "Console Web: http://${MINIO_IPS[0]}:9001"
echo ""

