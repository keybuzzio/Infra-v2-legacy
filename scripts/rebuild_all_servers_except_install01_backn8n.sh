#!/usr/bin/env bash
#
# rebuild_all_servers_except_install01_backn8n.sh
# Rebuild tous les serveurs sauf install-01 et backn8n.keybuzz.io
# Formate les volumes en XFS et supprime toutes les données
#
# Usage: ./rebuild_all_servers_except_install01_backn8n.sh [--force]

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
TSV_FILE="${1:-../../servers.tsv}"
LOG_DIR="/tmp/rebuild_logs_$(date +%Y%m%d_%H%M%S)"
FORCE="${2:-}"

# Serveurs à exclure
EXCLUDED_SERVERS=("install-01" "backn8n.keybuzz.io")

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

# Vérifier hcloud
if ! command -v hcloud >/dev/null 2>&1; then
    log_error "hcloud CLI non trouvé"
    exit 1
fi

# Vérifier token
if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    log_error "HCLOUD_TOKEN non défini"
    exit 1
fi

# Créer le répertoire de logs
mkdir -p "$LOG_DIR"

echo "=============================================================="
echo "  REBUILD COMPLET DES SERVEURS (sauf install-01 et backn8n)"
echo "=============================================================="
echo ""
log_info "Fichier TSV: $TSV_FILE"
log_info "Logs: $LOG_DIR"
echo ""

# Lire la liste des serveurs depuis servers.tsv
declare -a SERVERS_TO_REBUILD=()
declare -a SERVER_IPS=()

log_info "Lecture de servers.tsv..."

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]] || [[ -z "${HOSTNAME}" ]]; then
        continue
    fi
    
    # Skip non-prod
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    # Exclure install-01 et backn8n.keybuzz.io
    if [[ "${HOSTNAME}" == "install-01" ]] || [[ "${HOSTNAME}" == "backn8n.keybuzz.io" ]]; then
        log_warning "Serveur exclu: ${HOSTNAME}"
        continue
    fi
    
    SERVERS_TO_REBUILD+=("${HOSTNAME}")
    SERVER_IPS+=("${IP_PUBLIQUE}")
done < "$TSV_FILE"

TOTAL_SERVERS=${#SERVERS_TO_REBUILD[@]}

if [[ $TOTAL_SERVERS -eq 0 ]]; then
    log_error "Aucun serveur à rebuild"
    exit 1
fi

echo ""
log_info "Serveurs à rebuild: $TOTAL_SERVERS"
for i in "${!SERVERS_TO_REBUILD[@]}"; do
    echo "  - ${SERVERS_TO_REBUILD[$i]} (${SERVER_IPS[$i]})"
done
echo ""

# Confirmation
if [[ "$FORCE" != "--force" ]]; then
    log_warning "⚠️  ATTENTION: Toutes les données seront supprimées !"
    log_warning "Serveurs exclus: install-01, backn8n.keybuzz.io"
    echo ""
    read -rp "Tapez 'OUI' pour confirmer le rebuild de $TOTAL_SERVERS serveurs: " confirm
    if [[ "$confirm" != "OUI" ]]; then
        log_error "Annulé"
        exit 1
    fi
fi

# Obtenir l'image Ubuntu 24.04
log_info "Recherche de l'image Ubuntu 24.04..."
IMAGE_ID=$(hcloud image list --output columns=id,name --selector name=ubuntu-24.04 | tail -n +2 | head -1 | awk '{print $1}')

if [[ -z "$IMAGE_ID" ]]; then
    # Essayer une autre méthode
    IMAGE_ID=$(hcloud image list --output json | jq -r '.[] | select(.name | contains("ubuntu-24.04")) | .id' | head -1)
fi

if [[ -z "$IMAGE_ID" ]]; then
    log_error "Image Ubuntu 24.04 non trouvée"
    exit 1
fi

log_success "Image trouvée: $IMAGE_ID"

# Fonction pour rebuild un serveur
rebuild_server() {
    local hostname=$1
    local log_file="$LOG_DIR/rebuild_${hostname}.log"
    
    echo "[$(date +%H:%M:%S)] Début rebuild: $hostname" > "$log_file"
    
    # Obtenir l'ID du serveur
    local server_id=$(hcloud server list --output columns=id,name | grep -w "$hostname" | awk '{print $1}')
    
    if [[ -z "$server_id" ]]; then
        echo "ERREUR: Serveur $hostname non trouvé dans Hetzner" >> "$log_file"
        return 1
    fi
    
    # Rebuild le serveur
    if hcloud server rebuild "$server_id" --image "$IMAGE_ID" >> "$log_file" 2>&1; then
        echo "[$(date +%H:%M:%S)] Rebuild initié: $hostname" >> "$log_file"
        return 0
    else
        echo "ERREUR: Échec rebuild $hostname" >> "$log_file"
        return 1
    fi
}

# Fonction pour formater les volumes en XFS
format_volumes_xfs() {
    local hostname=$1
    local ip_publique=$2
    local log_file="$LOG_DIR/format_${hostname}.log"
    
    echo "[$(date +%H:%M:%S)] Formatage volumes XFS: $hostname" > "$log_file"
    
    # Attendre que le serveur soit accessible
    local max_attempts=30
    local attempt=0
    
    while [[ $attempt -lt $max_attempts ]]; do
        if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
            "root@${ip_publique}" "echo 'OK'" >> "$log_file" 2>&1; then
            break
        fi
        attempt=$((attempt + 1))
        sleep 10
    done
    
    if [[ $attempt -eq $max_attempts ]]; then
        echo "ERREUR: Serveur $hostname non accessible après rebuild" >> "$log_file"
        return 1
    fi
    
    # Installer xfsprogs et formater tous les volumes non montés
    ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@${ip_publique}" bash <<'FORMAT_SCRIPT' >> "$log_file" 2>&1
        # Installer xfsprogs
        apt-get update -qq
        apt-get install -y -qq xfsprogs
        
        # Lister tous les disques non montés
        for device in /dev/sd{b..z} /dev/vd{b..z}; do
            [ -b "$device" ] || continue
            
            # Vérifier si le device est monté
            if mount | grep -q "$device"; then
                echo "  $device déjà monté, skip"
                continue
            fi
            
            # Formater en XFS
            echo "  Formatage XFS de $device..."
            wipefs -af "$device" 2>/dev/null || true
            mkfs.xfs -f -m crc=1,finobt=1 "$device" 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                echo "  ✓ $device formaté en XFS"
            else
                echo "  ✗ Échec formatage $device"
            fi
        done
        
        # Formater aussi les volumes Hetzner (via /dev/disk/by-id)
        for vol in /dev/disk/by-id/scsi-*; do
            [ -L "$vol" ] || continue
            device=$(readlink -f "$vol")
            [ -b "$device" ] || continue
            
            # Vérifier si monté
            if mount | grep -q "$device"; then
                continue
            fi
            
            # Vérifier si déjà en XFS
            if blkid "$device" 2>/dev/null | grep -q 'TYPE="xfs"'; then
                continue
            fi
            
            echo "  Formatage XFS de $device (volume Hetzner)..."
            wipefs -af "$device" 2>/dev/null || true
            mkfs.xfs -f -m crc=1,finobt=1 "$device" 2>/dev/null
            
            if [[ $? -eq 0 ]]; then
                echo "  ✓ $device formaté en XFS"
            fi
        done
FORMAT_SCRIPT
    
    echo "[$(date +%H:%M:%S)] Formatage terminé: $hostname" >> "$log_file"
    return 0
}

# Phase 1: Rebuild tous les serveurs en parallèle
echo "=============================================================="
log_info "Phase 1/2: Rebuild des serveurs"
echo "=============================================================="
echo ""

REBUILD_PIDS=()
FAILED_REBUILDS=()

for i in "${!SERVERS_TO_REBUILD[@]}"; do
    hostname="${SERVERS_TO_REBUILD[$i]}"
    log_info "Lancement rebuild: $hostname..."
    
    rebuild_server "$hostname" &
    pid=$!
    REBUILD_PIDS+=($pid)
    
    # Petit délai pour éviter le rate limiting
    sleep 0.3
done

log_success "$TOTAL_SERVERS rebuilds lancés"
echo ""

# Attendre la fin des rebuilds
log_info "Attente de la fin des rebuilds (2-3 minutes)..."
echo ""

for pid in "${REBUILD_PIDS[@]}"; do
    wait $pid || FAILED_REBUILDS+=($pid)
done

if [[ ${#FAILED_REBUILDS[@]} -gt 0 ]]; then
    log_error "${#FAILED_REBUILDS[@]} rebuild(s) échoué(s)"
else
    log_success "Tous les rebuilds sont terminés"
fi

echo ""
echo "=============================================================="
log_info "Phase 2/2: Formatage volumes XFS"
echo "=============================================================="
echo ""

# Attendre un peu pour que les serveurs soient prêts
log_info "Attente de la disponibilité des serveurs (30 secondes)..."
sleep 30

FORMAT_PIDS=()
FAILED_FORMATS=()

for i in "${!SERVERS_TO_REBUILD[@]}"; do
    hostname="${SERVERS_TO_REBUILD[$i]}"
    ip_publique="${SERVER_IPS[$i]}"
    
    log_info "Formatage volumes: $hostname..."
    
    format_volumes_xfs "$hostname" "$ip_publique" &
    pid=$!
    FORMAT_PIDS+=($pid)
    
    sleep 1
done

log_success "$TOTAL_SERVERS formatages lancés"
echo ""

# Attendre la fin des formatages
log_info "Attente de la fin des formatages..."
echo ""

for pid in "${FORMAT_PIDS[@]}"; do
    wait $pid || FAILED_FORMATS+=($pid)
done

if [[ ${#FAILED_FORMATS[@]} -gt 0 ]]; then
    log_error "${#FAILED_FORMATS[@]} formatage(s) échoué(s)"
else
    log_success "Tous les formatages sont terminés"
fi

# Résumé final
echo ""
echo "=============================================================="
log_info "Résumé final"
echo "=============================================================="
echo ""
log_success "Serveurs rebuilds: $TOTAL_SERVERS"
log_success "Logs disponibles dans: $LOG_DIR"
echo ""

if [[ ${#FAILED_REBUILDS[@]} -gt 0 ]] || [[ ${#FAILED_FORMATS[@]} -gt 0 ]]; then
    log_warning "Certaines opérations ont échoué, consultez les logs"
    exit 1
else
    log_success "✅ Tous les serveurs ont été rebuilds et volumes formatés en XFS"
    exit 0
fi


