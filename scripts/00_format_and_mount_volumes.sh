#!/bin/bash
set -uo pipefail

# Script pour formater et monter les volumes (sans rebuild)
# Usage: bash 00_format_and_mount_volumes.sh

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Fonctions utilitaires
log() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}\n${BLUE}$1${NC}\n${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"; }

# Configuration
export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'
INVENTORY_TSV="${INVENTORY_TSV:-/opt/keybuzz-installer/inventory/servers.tsv}"

# Vérifier les dépendances
check_dependencies() {
    section "Vérification des dépendances"
    
    if ! command -v hcloud &> /dev/null; then
        error "hcloud CLI non trouvé"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log "Installation de jq..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq jq > /dev/null
    fi
    
    if ! command -v mkfs.xfs &> /dev/null; then
        log "Installation de xfsprogs..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq xfsprogs > /dev/null
    fi
    
    if [ -z "$HCLOUD_TOKEN" ]; then
        error "HCLOUD_TOKEN non défini"
        exit 1
    fi
    if hcloud server list &>/dev/null; then
        ok "Connexion Hetzner Cloud OK"
    else
        error "Impossible de se connecter à Hetzner Cloud"
        exit 1
    fi
}

# Obtenir l'IP d'un serveur
get_server_ip() {
    local hostname=$1
    
    # Essayer depuis servers.tsv
    if [ -f "$INVENTORY_TSV" ]; then
        local ip
        ip=$(awk -F'\t' -v h="$hostname" '$3 == h {print $2; exit}' "$INVENTORY_TSV" 2>/dev/null)
        if [ -n "$ip" ] && [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    fi
    
    # Fallback : Hetzner Cloud
    hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty'
}

# Obtenir le point de montage selon le hostname
get_mount_point() {
    local hostname=$1
    
    case "$hostname" in
        k8s-worker-*)
            echo "/mnt/k8s-worker"
            ;;
        db-*)
            echo "/opt/keybuzz/postgresql/data"
            ;;
        redis-*)
            echo "/opt/keybuzz/redis/data"
            ;;
        queue-*)
            echo "/opt/keybuzz/queue/data"
            ;;
        minio-*)
            echo "/opt/keybuzz/minio/data"
            ;;
        backup-*)
            echo "/opt/keybuzz/backup/data"
            ;;
        haproxy-*)
            echo "/opt/keybuzz/haproxy/data"
            ;;
        *)
            echo "/opt/keybuzz/data"
            ;;
    esac
}

# Obtenir la configuration du volume (taille et point de montage)
get_volume_config() {
    local hostname=$1
    local vol_name="vol-$hostname"
    
    # Vérifier si le volume existe
    if ! hcloud volume describe "$vol_name" &>/dev/null; then
        return 1
    fi
    
    local size
    size=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.size // empty')
    local mount_point
    mount_point=$(get_mount_point "$hostname")
    
    echo "$size|$mount_point"
}

# Attacher un volume à un serveur
attach_volume() {
    local vol_name=$1
    local hostname=$2
    
    log "Vérification de $vol_name pour $hostname..."
    
    # Obtenir l'ID du serveur
    local server_id
    server_id=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.id // empty')
    
    if [ -z "$server_id" ]; then
        warn "Serveur $hostname non trouvé"
        return 1
    fi
    
    # Vérifier si le volume est déjà attaché à ce serveur
    local attached_server_id
    attached_server_id=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.server // empty')
    
    if [ -n "$attached_server_id" ] && [ "$attached_server_id" == "$server_id" ]; then
        log "$vol_name déjà attaché à $hostname"
        return 0
    fi
    
    # Si attaché à un autre serveur, le détacher d'abord
    if [ -n "$attached_server_id" ] && [ "$attached_server_id" != "$server_id" ]; then
        log "Détachement de $vol_name du serveur $attached_server_id..."
        hcloud volume detach "$vol_name" 2>/dev/null || true
        sleep 2
    fi
    
    log "Attachement de $vol_name à $hostname (server_id: $server_id)..."
    local attach_output
    attach_output=$(hcloud volume attach --server "$server_id" "$vol_name" 2>&1)
    local attach_ret=$?
    
    if [ $attach_ret -eq 0 ]; then
        ok "$vol_name attaché à $hostname"
        sleep 3  # Attendre que le volume soit disponible
        return 0
    else
        # Vérifier à nouveau si attaché (peut-être attaché entre temps)
        attached_server_id=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.server // empty')
        if [ -n "$attached_server_id" ] && [ "$attached_server_id" == "$server_id" ]; then
            log "$vol_name finalement attaché à $hostname"
            return 0
        fi
        warn "$vol_name erreur lors de l'attachement: $attach_output"
        return 1
    fi
}

# Formater un volume en XFS
format_volume_xfs() {
    local hostname=$1
    local server_ip=$2
    
    log "Formatage du volume sur $hostname ($server_ip)..."
    
    # Trouver le device (généralement /dev/sdb ou /dev/sdc)
    local device=""
    for dev in /dev/sdb /dev/sdc /dev/sdd; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "test -b $dev && lsblk -n -o NAME,SIZE,TYPE $dev | grep -q disk" 2>/dev/null; then
            # Vérifier si déjà formaté
            if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
                "blkid $dev | grep -q xfs" 2>/dev/null; then
                warn "Volume déjà formaté en XFS sur $dev"
                echo "$dev"
                return 0
            fi
            device="$dev"
            break
        fi
    done
    
    if [ -z "$device" ]; then
        warn "Aucun device trouvé pour $hostname"
        return 1
    fi
    
    log "Formatage de $device en XFS..."
    if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
        "mkfs.xfs -f $device" 2>/dev/null; then
        ok "Volume formaté en XFS sur $device"
        echo "$device"
        return 0
    else
        warn "Erreur lors du formatage"
        return 1
    fi
}

# Monter un volume
mount_volume() {
    local hostname=$1
    local server_ip=$2
    local device=$3
    local mount_point=$4
    
    log "Montage du volume sur $hostname ($server_ip) vers $mount_point..."
    
    # Créer le point de montage
    ssh -o StrictHostKeyChecking=no root@"$server_ip" \
        "mkdir -p $mount_point" 2>/dev/null || true
    
    # Vérifier si déjà monté
    if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
        "mountpoint -q $mount_point" 2>/dev/null; then
        warn "Volume déjà monté sur $mount_point"
        return 0
    fi
    
    # Monter le volume
    if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
        "mount $device $mount_point" 2>/dev/null; then
        ok "Volume monté sur $mount_point"
        
        # Ajouter à /etc/fstab si pas déjà présent
        local uuid
        uuid=$(ssh -o StrictHostKeyChecking=no root@"$server_ip" \
            "blkid -s UUID -o value $device" 2>/dev/null)
        
        if [ -n "$uuid" ]; then
            if ! ssh -o StrictHostKeyChecking=no root@"$server_ip" \
                "grep -q \"$mount_point\" /etc/fstab" 2>/dev/null; then
                ssh -o StrictHostKeyChecking=no root@"$server_ip" \
                    "echo \"UUID=$uuid $mount_point xfs defaults,noatime 0 2\" >> /etc/fstab" 2>/dev/null
                ok "Ajouté à /etc/fstab"
            fi
        fi
        
        return 0
    else
        warn "Erreur lors du montage"
        return 1
    fi
}

# Phase principale : Attacher, formater et monter tous les volumes
phase_attach_format_mount() {
    section "Attachement, formatage et montage des volumes"
    
    # Charger tous les serveurs depuis servers.tsv
    local servers=()
    while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user_ssh pool role subrole docker_stack core notes || [ -n "$env" ]; do
        [[ -z "$env" ]] && continue
        [[ "$env" =~ ^#.*$ ]] && continue
        [[ "$env" == "ENV" ]] && continue
        [[ "$env" == "prod" ]] || [[ "$env" == "dev" ]] || [[ "$env" == "test" ]] || continue
        [[ -z "$hostname" ]] && continue
        [[ "$hostname" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue
        
        servers+=("$hostname")
    done < "$INVENTORY_TSV"
    
    local attached=0
    local formatted=0
    local mounted=0
    local failed=0
    
    for hostname in "${servers[@]}"; do
        local mount_point
        mount_point=$(get_mount_point "$hostname")
        
        # Vérifier si le serveur a besoin d'un volume
        if [ -z "$mount_point" ] || [ "$mount_point" == "/opt/keybuzz/data" ]; then
            # Vérifier si un volume existe pour ce serveur
            local vol_name="vol-$hostname"
            if ! hcloud volume describe "$vol_name" &>/dev/null; then
                continue  # Pas de volume pour ce serveur
            fi
        fi
        
        local vol_name="vol-$hostname"
        local server_ip
        server_ip=$(get_server_ip "$hostname")
        
        if [ -z "$server_ip" ]; then
            warn "Impossible de trouver l'IP pour $hostname"
            ((failed++))
            continue
        fi
        
        echo ""
        log "Traitement de $hostname ($server_ip)..."
        
        # 1. Attacher le volume
        if ! attach_volume "$vol_name" "$hostname"; then
            # Vérifier si le volume est quand même attaché au bon serveur
            local attached_server_id
            attached_server_id=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.server // empty')
            local server_id
            server_id=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.id // empty')
            
            if [ -n "$attached_server_id" ] && [ "$attached_server_id" == "$server_id" ]; then
                log "Volume déjà attaché au bon serveur, continuation..."
                ((attached++))
            else
                warn "Impossible d'attacher le volume $vol_name, skip"
                ((failed++))
                continue
            fi
        else
            ((attached++))
        fi
        
        # Attendre que le volume soit visible
        sleep 3
        
        # 2. Trouver le device
        local device=""
        local max_attempts=10
        local attempt=0
        
        while [ $attempt -lt $max_attempts ] && [ -z "$device" ]; do
            device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                "for dev in /dev/sd[b-z] /dev/vd[b-z]; do [ -b \"\$dev\" ] && ! mount | grep -q \"\$dev\" && echo \"\$dev\" && break; done" 2>/dev/null || echo "")
            
            if [ -z "$device" ]; then
                attempt=$((attempt + 1))
                sleep 2
            fi
        done
        
        if [ -z "$device" ]; then
            warn "Impossible de trouver le device pour $vol_name sur $hostname"
            ((failed++))
            continue
        fi
        
        log "Device trouvé : $device"
        
        # 3. Formater le volume
        if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
            "blkid $device | grep -q xfs" 2>/dev/null; then
            log "Volume déjà formaté en XFS"
            ((formatted++))
        else
            log "Formatage de $device en XFS..."
            if ssh -o StrictHostKeyChecking=no root@"$server_ip" \
                "mkfs.xfs -f $device" 2>/dev/null; then
                ok "Volume formaté en XFS"
                ((formatted++))
            else
                warn "Erreur lors du formatage"
                ((failed++))
                continue
            fi
        fi
        
        # 4. Monter le volume
        if mount_volume "$hostname" "$server_ip" "$device" "$mount_point"; then
            ((mounted++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    section "Résumé Phase : $attached attachés | $formatted formatés | $mounted montés | $failed échecs"
}

# Main
main() {
    section "Formatage et montage des volumes"
    
    log "Ce script va :"
    log "  1. Attacher tous les volumes aux serveurs"
    log "  2. Formater les volumes en XFS"
    log "  3. Monter les volumes aux bons emplacements"
    echo ""
    
    check_dependencies
    phase_attach_format_mount
    
    section "Terminé"
    ok "Tous les volumes ont été formatés et montés"
}

main "$@"

