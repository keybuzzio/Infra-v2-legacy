#!/bin/bash
set -uo pipefail

# Script pour détacher, formater et remonter les volumes des k8s workers
export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}\n${BLUE}$1${NC}\n${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"; }

section "Reformatage des volumes K8s Workers"

# Liste des serveurs
WORKERS=("k8s-worker-01" "k8s-worker-02" "k8s-worker-03" "k8s-worker-04" "k8s-worker-05")
MOUNT_POINT="/mnt/k8s-worker"

# Phase 1 : Détacher tous les volumes
section "Phase 1 : Détachement des volumes"

detach_volume() {
    local hostname=$1
    local vol_name="vol-$hostname"
    
    log "Détachement de $vol_name pour $hostname..."
    
    # Vérifier si le volume existe
    if ! hcloud volume describe "$vol_name" &>/dev/null; then
        warn "$vol_name n'existe pas, skip"
        return 1
    fi
    
    # Détacher le volume
    if hcloud volume detach "$vol_name" 2>/dev/null; then
        ok "$vol_name détaché"
        sleep 2
        return 0
    else
        warn "$vol_name déjà détaché ou erreur"
        return 1
    fi
}

# Détacher en parallèle
DETACH_PIDS=()
for worker in "${WORKERS[@]}"; do
    detach_volume "$worker" &
    DETACH_PIDS+=($!)
done

# Attendre la fin de tous les détachements
for pid in "${DETACH_PIDS[@]}"; do
    wait $pid
done

echo ""
ok "Tous les volumes ont été détachés"
sleep 3

# Phase 2 : Attacher les volumes
section "Phase 2 : Attachement des volumes"

attach_volume() {
    local hostname=$1
    local vol_name="vol-$hostname"
    
    log "Attachement de $vol_name à $hostname..."
    
    # Obtenir l'ID du serveur
    local server_id
    server_id=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.id // empty')
    
    if [ -z "$server_id" ]; then
        warn "Serveur $hostname non trouvé"
        return 1
    fi
    
    # Attacher le volume
    if hcloud volume attach --server "$server_id" "$vol_name" 2>/dev/null; then
        ok "$vol_name attaché à $hostname"
        sleep 3
        return 0
    else
        warn "$vol_name erreur lors de l'attachement"
        return 1
    fi
}

# Attacher en parallèle
ATTACH_PIDS=()
for worker in "${WORKERS[@]}"; do
    attach_volume "$worker" &
    ATTACH_PIDS+=($!)
done

# Attendre la fin de tous les attachements
for pid in "${ATTACH_PIDS[@]}"; do
    wait $pid
done

echo ""
ok "Tous les volumes ont été attachés"
sleep 5

# Phase 3 : Formater et monter les volumes
section "Phase 3 : Formatage et montage des volumes"

format_and_mount() {
    local hostname=$1
    local vol_name="vol-$hostname"
    
    log "Traitement de $hostname..."
    
    # Obtenir l'IP du serveur
    local server_ip
    server_ip=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty')
    
    if [ -z "$server_ip" ]; then
        warn "Impossible de trouver l'IP pour $hostname"
        return 1
    fi
    
    # Trouver le device
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
        warn "Impossible de trouver le device pour $hostname"
        return 1
    fi
    
    log "Device trouvé : $device"
    
    # Formater en XFS
    log "Formatage de $device en XFS..."
    if ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
        "mkfs.xfs -f $device" 2>/dev/null; then
        ok "$hostname: Volume formaté en XFS"
    else
        warn "$hostname: Erreur lors du formatage"
        return 1
    fi
    
    # Créer le point de montage
    ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
        "mkdir -p $MOUNT_POINT" 2>/dev/null || true
    
    # Monter le volume
    log "Montage du volume sur $MOUNT_POINT..."
    if ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
        "mount $device $MOUNT_POINT" 2>/dev/null; then
        ok "$hostname: Volume monté sur $MOUNT_POINT"
        
        # Ajouter à /etc/fstab
        local uuid
        uuid=$(ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
            "blkid -s UUID -o value $device" 2>/dev/null)
        
        if [ -n "$uuid" ]; then
            if ! ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
                "grep -q \"$MOUNT_POINT\" /etc/fstab" 2>/dev/null; then
                ssh -o StrictHostKeyChecking=no -o PasswordAuthentication=no root@"$server_ip" \
                    "echo \"UUID=$uuid $MOUNT_POINT xfs defaults,noatime 0 2\" >> /etc/fstab" 2>/dev/null
                ok "$hostname: Ajouté à /etc/fstab"
            fi
        fi
        
        return 0
    else
        warn "$hostname: Erreur lors du montage"
        return 1
    fi
}

# Formater et monter en parallèle
FORMAT_PIDS=()
for worker in "${WORKERS[@]}"; do
    format_and_mount "$worker" &
    FORMAT_PIDS+=($!)
done

# Attendre la fin de tous les formatages et montages
for pid in "${FORMAT_PIDS[@]}"; do
    wait $pid
done

echo ""
section "Vérification finale"

# Vérifier les montages
for worker in "${WORKERS[@]}"; do
    log "Vérification de $worker..."
    if hcloud server ssh "$worker" "mountpoint -q $MOUNT_POINT && df -h $MOUNT_POINT" 2>/dev/null; then
        ok "$worker: Volume monté correctement"
    else
        warn "$worker: Volume non monté"
    fi
done

echo ""
section "Terminé"
ok "Tous les volumes K8s Workers ont été reformatés et remontés"

