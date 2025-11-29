#!/usr/bin/env bash
#
# 00_distribute_credentials.sh - Distribution des credentials sur tous les serveurs
#
# Ce script copie les fichiers de credentials depuis install-01 vers tous les serveurs
# qui en ont besoin pour les tests et l'utilisation des services.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Chercher servers.tsv dans plusieurs emplacements possibles
if [[ -f "${INSTALL_DIR}/servers.tsv" ]]; then
    TSV_FILE="${INSTALL_DIR}/servers.tsv"
elif [[ -f "${INSTALL_DIR}/inventory/servers.tsv" ]]; then
    TSV_FILE="${INSTALL_DIR}/inventory/servers.tsv"
elif [[ -f "/opt/keybuzz-installer/servers.tsv" ]]; then
    TSV_FILE="/opt/keybuzz-installer/servers.tsv"
else
    TSV_FILE="${1:-/opt/keybuzz-installer/servers.tsv}"
fi

CREDENTIALS_DIR="${INSTALL_DIR}/credentials"

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

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Distribution des Credentials"
echo "=============================================================="
echo ""

# Vérifier que les credentials existent
if [[ ! -d "${CREDENTIALS_DIR}" ]]; then
    log_error "Répertoire credentials introuvable: ${CREDENTIALS_DIR}"
    exit 1
fi

# Liste des fichiers de credentials à distribuer
CREDENTIALS_FILES=(
    "postgres.env"
    "redis.env"
    "mariadb.env"
    "rabbitmq.env"
    "minio.env"
)

# Vérifier que les fichiers existent
MISSING_FILES=()
for file in "${CREDENTIALS_FILES[@]}"; do
    if [[ ! -f "${CREDENTIALS_DIR}/${file}" ]]; then
        MISSING_FILES+=("${file}")
    fi
done

if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    log_warning "Fichiers de credentials manquants: ${MISSING_FILES[*]}"
    log_info "Ces fichiers seront ignorés"
fi

# Collecter tous les serveurs qui ont besoin de credentials
declare -a ALL_SERVERS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    # Exclure install-01 (source) et backn8n
    if [[ "${HOSTNAME}" == "install-01" ]] || [[ "${HOSTNAME}" == "backn8n.keybuzz.io" ]]; then
        continue
    fi
    
    # Inclure tous les autres serveurs
    ALL_SERVERS+=("${IP_PRIVEE}:${HOSTNAME}")
done
exec 3<&-

log_info "Serveurs cibles: ${#ALL_SERVERS[@]}"
echo ""

# Fonction pour copier les credentials sur un serveur
copy_credentials_to_server() {
    local ip="$1"
    local hostname="$2"
    
    log_info "Copie des credentials vers ${hostname} (${ip})..."
    
    # Créer le répertoire credentials sur le serveur distant
    ssh ${SSH_OPTS} root@${ip} "mkdir -p /opt/keybuzz-installer/credentials && chmod 700 /opt/keybuzz-installer/credentials" 2>/dev/null || {
        log_error "Impossible de créer le répertoire sur ${hostname}"
        return 1
    }
    
    # Copier chaque fichier de credentials
    for file in "${CREDENTIALS_FILES[@]}"; do
        if [[ -f "${CREDENTIALS_DIR}/${file}" ]]; then
            scp ${SSH_OPTS} "${CREDENTIALS_DIR}/${file}" "root@${ip}:/opt/keybuzz-installer/credentials/" >/dev/null 2>&1 || {
                log_warning "Impossible de copier ${file} vers ${hostname}"
                continue
            }
            
            # Définir les permissions correctes
            ssh ${SSH_OPTS} root@${ip} "chmod 600 /opt/keybuzz-installer/credentials/${file}" 2>/dev/null || true
        fi
    done
    
    log_success "Credentials copiés vers ${hostname}"
    return 0
}

# Copier les credentials sur tous les serveurs
SUCCESS_COUNT=0
FAIL_COUNT=0

for server_info in "${ALL_SERVERS[@]}"; do
    IFS=':' read -r ip hostname <<< "${server_info}"
    
    if copy_credentials_to_server "${ip}" "${hostname}"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
echo "=============================================================="
log_info "Résumé de la distribution"
echo "=============================================================="
log_success "Serveurs réussis: ${SUCCESS_COUNT}"
if [[ ${FAIL_COUNT} -gt 0 ]]; then
    log_error "Serveurs échoués: ${FAIL_COUNT}"
else
    log_success "Serveurs échoués: ${FAIL_COUNT}"
fi
echo ""

# Vérification finale
log_info "Vérification de la distribution..."
VERIFY_COUNT=0
for server_info in "${ALL_SERVERS[@]}"; do
    IFS=':' read -r ip hostname <<< "${server_info}"
    
    # Vérifier que les fichiers existent
    FILE_COUNT=$(ssh ${SSH_OPTS} root@${ip} "ls -1 /opt/keybuzz-installer/credentials/*.env 2>/dev/null | wc -l" 2>/dev/null || echo "0")
    if [[ ${FILE_COUNT} -gt 0 ]]; then
        VERIFY_COUNT=$((VERIFY_COUNT + 1))
    fi
done

log_info "Serveurs avec credentials vérifiés: ${VERIFY_COUNT}/${#ALL_SERVERS[@]}"

if [[ ${VERIFY_COUNT} -eq ${#ALL_SERVERS[@]} ]]; then
    log_success "✅ Tous les credentials ont été distribués avec succès !"
    exit 0
else
    log_warning "⚠️  Certains serveurs n'ont pas tous les credentials"
    exit 1
fi

