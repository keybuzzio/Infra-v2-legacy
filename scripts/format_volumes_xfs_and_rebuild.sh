#!/usr/bin/env bash
#
# format_volumes_xfs_and_rebuild.sh
# Rebuild les serveurs puis formate les volumes en XFS en les attachant aux serveurs respectifs
#
# Usage: ./format_volumes_xfs_and_rebuild.sh [--force]

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
FORCE="${1:-}"
TSV_FILE="/opt/keybuzz-installer/servers.tsv"

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

echo "=============================================================="
echo "  REBUILD SERVEURS ET FORMATAGE VOLUMES XFS"
echo "=============================================================="
echo ""

# Lire servers.tsv
if [[ ! -f "$TSV_FILE" ]]; then
    log_error "Fichier servers.tsv non trouvé: $TSV_FILE"
    exit 1
fi

declare -a SERVERS_TO_REBUILD=()
declare -a SERVER_IPS=()
declare -A SERVER_VOLUMES=()  # hostname -> volume_name

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

log_info "Serveurs à rebuild: $TOTAL_SERVERS"
echo ""

# Confirmation
if [[ "$FORCE" != "--force" ]]; then
    log_warning "⚠️  ATTENTION: Tous les serveurs seront rebuilds et volumes formatés !"
    echo ""
    read -rp "Tapez 'OUI' pour confirmer: " confirm
    if [[ "$confirm" != "OUI" ]]; then
        log_error "Annulé"
        exit 1
    fi
fi

# Obtenir l'image Ubuntu 24.04
log_info "Recherche de l'image Ubuntu 24.04..."
IMAGE_ID=$(hcloud image list --output json | jq -r '.[] | select(.name | contains("ubuntu-24.04")) | .id' | head -1)

if [[ -z "$IMAGE_ID" ]]; then
    log_error "Image Ubuntu 24.04 non trouvée"
    exit 1
fi

log_success "Image trouvée: $IMAGE_ID"
echo ""

# Phase 1: Rebuild des serveurs
echo "=============================================================="
log_info "Phase 1/3: Rebuild des serveurs"
echo "=============================================================="
echo ""

rebuild_server() {
    local hostname=$1
    
    # Obtenir l'ID du serveur
    local server_id=$(hcloud server list --output json | jq -r ".[] | select(.name == \"$hostname\") | .id")
    
    if [[ -z "$server_id" ]]; then
        log_error "Serveur $hostname non trouvé"
        return 1
    fi
    
    # Rebuild le serveur
    if hcloud server rebuild "$server_id" --image "$IMAGE_ID" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Rebuild en parallèle
log_info "Lancement des rebuilds en parallèle..."
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

# Phase 2: Attendre que les serveurs soient prêts
echo "=============================================================="
log_info "Phase 2/3: Attente que les serveurs soient prêts"
echo "=============================================================="
echo ""

MAX_WAIT=300
WAIT_TIME=0
ALL_RUNNING=false

while [[ $WAIT_TIME -lt $MAX_WAIT ]] && [[ "$ALL_RUNNING" == "false" ]]; do
    RUNNING_COUNT=0
    
    for hostname in "${SERVERS_TO_REBUILD[@]}"; do
        status=$(hcloud server list --output json | jq -r ".[] | select(.name == \"$hostname\") | .status")
        if [[ "$status" == "running" ]]; then
            ((RUNNING_COUNT++))
        fi
    done
    
    printf "\rServeurs running: %d/%d  " $RUNNING_COUNT $TOTAL_SERVERS
    
    if [[ $RUNNING_COUNT -eq $TOTAL_SERVERS ]]; then
        ALL_RUNNING=true
        echo ""
        log_success "Tous les serveurs sont running !"
    else
        sleep 10
        ((WAIT_TIME+=10))
    fi
done

echo ""
log_info "Attente supplémentaire pour SSH (30 secondes)..."
sleep 30
echo ""

# Phase 3: Attacher les volumes et formater en XFS
echo "=============================================================="
log_info "Phase 3/3: Attachement volumes et formatage XFS"
echo "=============================================================="
echo ""

# Obtenir la liste de tous les volumes avec leur serveur cible
VOLUMES=$(hcloud volume list --output json | jq -r '.[] | "\(.id)|\(.name)|\(.server // "none")"')

VOLUME_COUNT=$(echo "$VOLUMES" | wc -l)
log_info "Volumes trouvés: $VOLUME_COUNT"
echo ""

# Fonction pour formater un volume sur un serveur
format_volume_on_server() {
    local vol_id=$1
    local vol_name=$2
    local target_server=$3
    local server_ip=$4
    
    log_info "Traitement volume: $vol_name -> $target_server"
    
    # Détacher le volume s'il est attaché ailleurs
    current_server=$(hcloud volume list --output json | jq -r ".[] | select(.id == $vol_id) | .server // \"none\"")
    if [[ "$current_server" != "none" ]] && [[ "$current_server" != "$target_server" ]]; then
        log_info "  Détachement depuis $current_server..."
        hcloud volume detach "$vol_id" 2>/dev/null || true
        sleep 2
    fi
    
    # Attacher le volume au serveur cible
    log_info "  Attachement à $target_server..."
    if hcloud volume attach "$vol_id" "$target_server" 2>/dev/null; then
        sleep 5
        
        # Attendre que SSH soit accessible
        local ssh_attempts=0
        local max_ssh_attempts=30
        
        while [[ $ssh_attempts -lt $max_ssh_attempts ]]; do
            if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
                "root@${server_ip}" "echo 'OK'" >/dev/null 2>&1; then
                break
            fi
            ssh_attempts=$((ssh_attempts + 1))
            sleep 5
        done
        
        if [[ $ssh_attempts -eq $max_ssh_attempts ]]; then
            log_error "  SSH non accessible sur $target_server"
            return 1
        fi
        
        # Formater le volume en XFS via SSH
        log_info "  Formatage XFS via SSH..."
        if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "root@${server_ip}" bash <<'FORMAT_SCRIPT'
            # Installer xfsprogs
            apt-get update -qq
            apt-get install -y -qq xfsprogs >/dev/null 2>&1
            
            # Trouver le device du volume (dernier disque non monté)
            DEVICE=""
            
            # Essayer via /dev/disk/by-id (volumes Hetzner)
            for vol in /dev/disk/by-id/scsi-*; do
                [ -L "$vol" ] || continue
                device=$(readlink -f "$vol")
                [ -b "$device" ] || continue
                
                # Vérifier si monté
                if mount | grep -q "$device"; then
                    continue
                fi
                
                DEVICE="$device"
                break
            done
            
            # Si pas trouvé, chercher dans /dev/sd* et /dev/vd*
            if [[ -z "$DEVICE" ]]; then
                for dev in /dev/sd{b..z} /dev/vd{b..z}; do
                    [ -b "$dev" ] || continue
                    
                    # Vérifier si monté
                    if mount | grep -q "$dev"; then
                        continue
                    fi
                    
                    DEVICE="$dev"
                    break
                done
            fi
            
            if [[ -z "$DEVICE" ]] || [[ ! -b "$DEVICE" ]]; then
                echo "ERREUR: Device non trouvé"
                exit 1
            fi
            
            # Formater en XFS
            wipefs -af "$DEVICE" 2>/dev/null || true
            mkfs.xfs -f -m crc=1,finobt=1 "$DEVICE" >/dev/null 2>&1
            
            if [[ $? -eq 0 ]]; then
                echo "OK: Volume formaté en XFS"
            else
                echo "ERREUR: Échec formatage"
                exit 1
            fi
FORMAT_SCRIPT
        then
            log_success "  Volume $vol_name formaté en XFS sur $target_server"
            return 0
        else
            log_error "  Échec formatage $vol_name sur $target_server"
            return 1
        fi
    else
        log_error "  Échec attachement de $vol_name à $target_server"
        return 1
    fi
}

# Pour chaque volume, trouver son serveur cible et formater
SUCCESS_COUNT=0
FAIL_COUNT=0

while IFS='|' read -r vol_id vol_name current_server; do
    # Extraire le nom du serveur depuis le nom du volume (ex: vol-db-master-01 -> db-master-01)
    target_server=""
    
    # Chercher dans servers.tsv quel serveur correspond à ce volume
    while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
        if [[ "${ENV}" == "ENV" ]] || [[ -z "${HOSTNAME}" ]]; then
            continue
        fi
        
        if [[ "${ENV}" != "prod" ]]; then
            continue
        fi
        
        # Vérifier si le nom du volume correspond à ce serveur
        if [[ "$vol_name" == *"${HOSTNAME}"* ]] || [[ "$vol_name" == "vol-${HOSTNAME}" ]]; then
            target_server="$HOSTNAME"
            server_ip="$IP_PUBLIQUE"
            break
        fi
    done < "$TSV_FILE"
    
    if [[ -z "$target_server" ]]; then
        log_warning "Serveur cible non trouvé pour $vol_name, skip"
        continue
    fi
    
    # Vérifier que le serveur est dans la liste des serveurs à rebuild
    if [[ ! " ${SERVERS_TO_REBUILD[@]} " =~ " ${target_server} " ]]; then
        log_warning "Serveur $target_server exclu, skip volume $vol_name"
        continue
    fi
    
    # Formater le volume
    if format_volume_on_server "$vol_id" "$vol_name" "$target_server" "$server_ip"; then
        ((SUCCESS_COUNT++))
    else
        ((FAIL_COUNT++))
    fi
    
    echo ""
    
done <<< "$VOLUMES"

# Résumé final
echo "=============================================================="
log_success "Résumé final"
echo "=============================================================="
echo ""
log_success "Serveurs rebuilds: $TOTAL_SERVERS"
log_success "Volumes formatés avec succès: $SUCCESS_COUNT"
if [[ $FAIL_COUNT -gt 0 ]]; then
    log_error "Volumes en échec: $FAIL_COUNT"
fi
echo ""
log_info "Prochaine étape: Redéployer les clés SSH puis relancer l'installation"
echo ""
