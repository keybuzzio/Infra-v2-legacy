#!/usr/bin/env bash
#
# 03_pg_01_prepare_volumes.sh - Préparation des volumes XFS pour PostgreSQL
#
# Ce script prépare les volumes XFS et les répertoires de données sur chaque nœud DB.
#
# Usage:
#   ./03_pg_01_prepare_volumes.sh [servers.tsv]
#
# Prérequis:
#   - Module 2 appliqué sur tous les serveurs DB
#   - Volumes XFS montés (ex: /mnt/postgres-data)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/inventory/servers.tsv}"

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
echo " [KeyBuzz] Module 3 - Préparation Volumes XFS PostgreSQL"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds DB
declare -a DB_NODES
declare -a DB_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod et ROLE=db SUBROLE=postgres
    if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "db" ]] || [[ "${SUBROLE}" != "postgres" ]]; then
        continue
    fi
    
    # Filtrer uniquement les 3 nœuds Patroni
    if [[ "${HOSTNAME}" != "db-master-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-01" ]] && \
       [[ "${HOSTNAME}" != "db-slave-02" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        log_warning "IP privée vide pour ${HOSTNAME}, on saute."
        continue
    fi
    
    DB_NODES+=("${HOSTNAME}")
    DB_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

if [[ ${#DB_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds DB incorrect: ${#DB_NODES[@]} (attendu: 3)"
    exit 1
fi

log_success "3 nœuds DB trouvés: ${DB_NODES[*]}"
echo ""

# Fonction pour préparer les volumes sur un nœud
prepare_volumes_node() {
    local hostname=$1
    local ip=$2
    
    log_info "--------------------------------------------------------------"
    log_info "Préparation volumes sur ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    # Vérifier la connectivité
    if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new "root@${ip}" "exit" 2>/dev/null; then
        log_error "Impossible de se connecter à ${hostname} (${ip})"
        return 1
    fi
    
    # Vérifier que le FS est XFS
    log_info "Vérification du système de fichiers..."
    FS_TYPE=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "df -T /opt/keybuzz/postgres/data 2>/dev/null | tail -1 | awk '{print \$2}' || echo 'none'")
    
    if [[ "${FS_TYPE}" != "xfs" ]]; then
        # Vérifier s'il y a un volume monté quelque part
        XFS_MOUNT=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
            "root@${ip}" "df -T | grep xfs | head -1 | awk '{print \$NF}' || echo ''")
        
        if [[ -z "${XFS_MOUNT}" ]]; then
            log_warning "Aucun volume XFS trouvé sur ${hostname}"
            log_warning "Le script continuera mais il est recommandé d'utiliser XFS pour les performances"
        else
            log_info "Volume XFS trouvé sur ${XFS_MOUNT}"
        fi
    else
        log_success "Système de fichiers XFS détecté"
    fi
    
    # Créer les répertoires
    log_info "Création des répertoires..."
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" <<'EOF'
        set -euo pipefail
        
        # Créer les répertoires
        mkdir -p /opt/keybuzz/postgres/{data,raft,archive}
        
        # Configurer les permissions (UID 999:999 = postgres dans le conteneur)
        chown -R 999:999 /opt/keybuzz/postgres
        chmod 700 /opt/keybuzz/postgres/data
        chmod 700 /opt/keybuzz/postgres/raft
        chmod 755 /opt/keybuzz/postgres/archive
        
        # Vérifier les permissions
        ls -ld /opt/keybuzz/postgres/data
        ls -ld /opt/keybuzz/postgres/raft
        ls -ld /opt/keybuzz/postgres/archive
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "Volumes préparés sur ${hostname}"
        return 0
    else
        log_error "Erreur lors de la préparation des volumes sur ${hostname}"
        return 1
    fi
}

# Préparer les volumes sur tous les nœuds
SUCCESS_COUNT=0
ERROR_COUNT=0

for i in "${!DB_NODES[@]}"; do
    if prepare_volumes_node "${DB_NODES[$i]}" "${DB_IPS[$i]}"; then
        ((SUCCESS_COUNT++))
    else
        ((ERROR_COUNT++))
    fi
    echo ""
done

# Résumé
echo "=============================================================="
echo " [KeyBuzz] Résumé de la préparation des volumes"
echo "=============================================================="
log_success "Nœuds préparés avec succès : ${SUCCESS_COUNT}/${#DB_NODES[@]}"
if [[ ${ERROR_COUNT} -gt 0 ]]; then
    log_error "Nœuds en erreur : ${ERROR_COUNT}/${#DB_NODES[@]}"
fi
echo "=============================================================="

if [[ ${ERROR_COUNT} -eq 0 ]]; then
    log_success "✅ Tous les volumes sont prêts pour l'installation Patroni"
    exit 0
else
    log_error "⚠️  Certains volumes n'ont pas pu être préparés"
    exit 1
fi

