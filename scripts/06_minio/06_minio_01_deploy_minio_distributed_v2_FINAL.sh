#!/usr/bin/env bash
#
# 06_minio_01_deploy_minio_distributed_v2_FINAL.sh - Déploiement du cluster MinIO distributed (3 nœuds)
# VERSION FINALE : Utilise sed pour remplacer les placeholders au lieu d'interpolation
#
# Ce script déploie MinIO en mode distributed sur 3 nœuds :
# - minio-01 (10.0.0.134)
# - minio-02 (10.0.0.131, ex-connect-01)
# - minio-03 (10.0.0.132, ex-connect-02)
#
# Usage:
#   ./06_minio_01_deploy_minio_distributed_v2_FINAL.sh [servers.tsv]
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
        MINIO_IMAGE="minio/minio:latest"
    fi
else
    log_warning "Fichier versions.yaml introuvable, utilisation de la version par défaut"
    MINIO_IMAGE="minio/minio:latest"
fi

# Vérifier que MINIO_IMAGE est défini et nettoyer
MINIO_IMAGE=$(echo "${MINIO_IMAGE}" | tr -d '\n\r' | xargs) # Supprimer sauts de ligne et espaces
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

# Construire la liste des volumes (utiliser les IPs directement)
MINIO_VOLUMES_STR=""
for vol_ip in "${MINIO_IPS[@]}"; do
    MINIO_VOLUMES_STR="${MINIO_VOLUMES_STR} http://${vol_ip}:9000/data"
done
MINIO_VOLUMES_STR=$(echo "${MINIO_VOLUMES_STR}" | xargs) # Nettoyer espaces

log_info "MINIO_VOLUMES (avec IPs): ${MINIO_VOLUMES_STR}"
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

# Template du script de déploiement (avec placeholders)
# Utiliser un heredoc avec guillemets simples pour éviter l'interpolation
DEPLOY_SCRIPT_TEMPLATE=$(cat <<'TEMPLATE_END'
#!/usr/bin/env bash
set -euo pipefail

# Variables (remplacées par sed)
MINIO_IMAGE_ARG="__MINIO_IMAGE__"
MINIO_ROOT_USER_ARG="__MINIO_ROOT_USER__"
MINIO_ROOT_PASSWORD_ARG="__MINIO_ROOT_PASSWORD__"
MINIO_VOLUMES_STR="__MINIO_VOLUMES_STR__"
HOSTNAME_ARG="__HOSTNAME__"

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

# Créer un fichier d'environnement temporaire pour éviter les problèmes d'échappement
ENV_FILE="/tmp/minio_env_$$.env"
echo "MINIO_ROOT_USER=${MINIO_ROOT_USER_ARG}" > "${ENV_FILE}"
echo "MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD_ARG}" >> "${ENV_FILE}"
chmod 600 "${ENV_FILE}"

# Construire la commande Docker avec un tableau pour éviter les problèmes d'expansion
# L'image est déjà remplacée directement par sed (__MINIO_IMAGE__)
# Le placeholder __MINIO_IMAGE__ sera remplacé par sed dans toute la chaîne
DOCKER_CMD_ARGS=(
    docker run -d
    --name minio
    --restart always
    --network host
    -v /opt/keybuzz/minio/data:/data
    --env-file "${ENV_FILE}"
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

# Debug: afficher la commande
echo "  [DEBUG] Commande Docker (tableau):"
for i in "${!DOCKER_CMD_ARGS[@]}"; do
    echo "    [$i] = '${DOCKER_CMD_ARGS[$i]}'"
done

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

# Nettoyer le fichier d'environnement
rm -f "${ENV_FILE}"
TEMPLATE_END
)

# Déployer MinIO sur chaque nœud
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Déploiement MinIO sur: ${hostname} (${ip})"
    log_info "=============================================================="
    
    # Créer un script temporaire local avec le template
    TEMP_SCRIPT="/tmp/deploy_minio_${hostname}_$$.sh"
    echo "${DEPLOY_SCRIPT_TEMPLATE}" > "${TEMP_SCRIPT}"
    
    # Remplacer les placeholders avec sed
    # Utiliser des délimiteurs différents (|) pour éviter les problèmes d'échappement
    # Échapper uniquement les caractères spéciaux pour sed (|, &, etc.) mais pas /
    # Nettoyer les sauts de ligne avec tr -d '\n' et xargs
    MINIO_IMAGE_SED=$(echo "${MINIO_IMAGE}" | tr -d '\n' | xargs | sed 's/[|&]/\\&/g')
    MINIO_ROOT_USER_SED=$(echo "${MINIO_ROOT_USER}" | tr -d '\n' | xargs | sed 's/[|&]/\\&/g')
    MINIO_ROOT_PASSWORD_SED=$(echo "${MINIO_ROOT_PASSWORD}" | tr -d '\n' | xargs | sed 's/[|&]/\\&/g')
    MINIO_VOLUMES_STR_SED=$(echo "${MINIO_VOLUMES_STR}" | tr -d '\n' | xargs | sed 's/[|&]/\\&/g')
    HOSTNAME_SED=$(echo "${hostname}" | tr -d '\n' | xargs | sed 's/[|&]/\\&/g')
    
    # Remplacer __MINIO_IMAGE__ partout dans le script (y compris dans les variables)
    sed -i "s|__MINIO_IMAGE__|${MINIO_IMAGE_SED}|g" "${TEMP_SCRIPT}"
    sed -i "s|__MINIO_ROOT_USER__|${MINIO_ROOT_USER_SED}|g" "${TEMP_SCRIPT}"
    sed -i "s|__MINIO_ROOT_PASSWORD__|${MINIO_ROOT_PASSWORD_SED}|g" "${TEMP_SCRIPT}"
    sed -i "s|__MINIO_VOLUMES_STR__|${MINIO_VOLUMES_STR_SED}|g" "${TEMP_SCRIPT}"
    sed -i "s|__HOSTNAME__|${HOSTNAME_SED}|g" "${TEMP_SCRIPT}"
    
    # Vérifier que __MINIO_IMAGE__ a bien été remplacé
    if grep -q "__MINIO_IMAGE__" "${TEMP_SCRIPT}"; then
        log_warning "__MINIO_IMAGE__ n'a pas été remplacé dans le script !"
        log_info "Lignes contenant __MINIO_IMAGE__:"
        grep -n "__MINIO_IMAGE__" "${TEMP_SCRIPT}" || true
    else
        log_info "✓ __MINIO_IMAGE__ correctement remplacé"
        # Afficher la ligne contenant l'image pour vérification
        log_info "Ligne contenant l'image Docker:"
        grep -n "DOCKER_CMD_ARGS" "${TEMP_SCRIPT}" | head -1 || true
    fi
    
    # Rendre le script exécutable
    chmod +x "${TEMP_SCRIPT}"
    
    # Copier le script sur le serveur distant
    log_info "Copie du script de déploiement sur ${hostname}..."
    scp ${SSH_KEY_OPTS} "${TEMP_SCRIPT}" "root@${ip}:/tmp/deploy_minio.sh"
    
    # Exécuter le script sur le serveur distant
    log_info "Exécution du script de déploiement sur ${hostname}..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash /tmp/deploy_minio.sh
    
    # Nettoyer le script temporaire local
    rm -f "${TEMP_SCRIPT}"
    
    # Nettoyer le script temporaire distant
    ssh ${SSH_KEY_OPTS} "root@${ip}" rm -f /tmp/deploy_minio.sh
    
    log_success "MinIO déployé sur ${hostname}"
done

# Attendre que le cluster soit prêt
log_info "Attente de la stabilisation du cluster MinIO (30 secondes)..."
sleep 30

# Vérifier le statut du cluster
log_info "Vérification du statut du cluster MinIO..."
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    if ssh ${SSH_KEY_OPTS} "root@${ip}" docker ps | grep -q "minio"; then
        log_success "MinIO opérationnel sur ${hostname} (${ip})"
    else
        log_error "MinIO non démarré sur ${hostname} (${ip})"
    fi
done

log_success "Déploiement MinIO distributed terminé !"
log_info "Point d'entrée: http://s3.keybuzz.io:9000 (ou http://${MINIO_IPS[0]}:9000)"
log_info "Console: http://${MINIO_IPS[0]}:9001"

