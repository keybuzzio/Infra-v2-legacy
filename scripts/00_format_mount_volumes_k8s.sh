#!/bin/bash
# format_mount_volumes_k8s.sh
# Script pour formater et monter les volumes sur les serveurs K8s
#
# Usage:
#   bash 00_format_mount_volumes_k8s.sh
#

set -uo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonctions d'affichage
log() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
ko() { echo -e "${RED}[FAIL]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"; }

# Token Hetzner Cloud
export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

# Fichier inventory
INVENTORY_TSV="/opt/keybuzz-installer/inventory/servers.tsv"

# Obtenir l'IP publique d'un serveur (depuis Hetzner Cloud ou servers.tsv)
get_server_ip() {
    local hostname=$1
    
    # D'abord essayer depuis Hetzner Cloud
    local ip
    ip=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty')
    
    # Si pas trouvé, chercher dans servers.tsv
    if [ -z "$ip" ] && [ -f "$INVENTORY_TSV" ]; then
        # Chercher avec le nom exact
        ip=$(grep -E "^prod[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$hostname" "$INVENTORY_TSV" 2>/dev/null | awk '{print $2}' | head -1)
        
        # Si pas trouvé et que c'est un nom k8s-*, chercher avec k3s-*
        if [ -z "$ip" ] && [[ "$hostname" =~ ^k8s- ]]; then
            local old_name
            old_name=$(echo "$hostname" | sed 's/^k8s-/k3s-/')
            ip=$(grep -E "^prod[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$old_name" "$INVENTORY_TSV" 2>/dev/null | awk '{print $2}' | head -1)
        fi
    fi
    
    echo "$ip"
}

# Mapping des serveurs K8s avec leurs points de montage
declare -A SERVER_MOUNT_POINTS=(
    ["k8s-master-01"]=""
    ["k8s-master-02"]=""
    ["k8s-master-03"]=""
    ["k8s-worker-01"]="/var/lib/containerd"
    ["k8s-worker-02"]="/var/lib/containerd"
    ["k8s-worker-03"]="/var/lib/containerd"
    ["k8s-worker-04"]="/var/lib/containerd"
    ["k8s-worker-05"]="/var/lib/containerd"
)

# Attacher un volume à un serveur
attach_volume() {
    local vol_name=$1
    local server_name=$2
    
    log "Attachement de $vol_name → $server_name..."
    
    # Vérifier si déjà attaché
    local current_server
    current_server=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.server // empty')
    
    if [ -n "$current_server" ] && [ "$current_server" != "null" ]; then
        if [ "$current_server" == "$server_name" ]; then
            warn "$vol_name déjà attaché à $server_name"
            return 0
        else
            warn "$vol_name attaché à $current_server, détachement..."
            hcloud volume detach "$vol_name" &>/dev/null
            sleep 3
        fi
    fi
    
    if hcloud volume attach "$vol_name" --server "$server_name" 2>/dev/null; then
        ok "$vol_name attaché à $server_name"
        sleep 3
        return 0
    else
        ko "Échec attachement de $vol_name"
        return 1
    fi
}

# Formater un volume en XFS
format_volume_xfs() {
    local server_ip=$1
    local device=$2
    
    log "Formatage de $device en XFS sur $server_ip..."
    
    # Installer xfsprogs si nécessaire
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "export DEBIAN_FRONTEND=noninteractive && (which mkfs.xfs || (apt-get update -qq && apt-get install -y -qq xfsprogs))" &>/dev/null || true
    
    # Vérifier si déjà formaté en XFS
    local fstype
    fstype=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "blkid -s TYPE -o value $device" 2>/dev/null || echo "")
    
    if [ "$fstype" == "xfs" ]; then
        warn "$device déjà formaté en XFS"
        return 0
    fi
    
    # Formater en XFS
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "mkfs.xfs -f $device" 2>/dev/null; then
        ok "$device formaté en XFS"
        return 0
    else
        ko "Échec formatage de $device"
        return 1
    fi
}

# Monter un volume
mount_volume() {
    local server_ip=$1
    local device=$2
    local mount_point=$3
    
    log "Montage de $device sur $mount_point..."
    
    # Vérifier si déjà monté
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "mountpoint -q $mount_point" 2>/dev/null; then
        warn "$mount_point déjà monté"
        return 0
    fi
    
    # Créer le point de montage
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "mkdir -p $mount_point" &>/dev/null || true
    
    # Monter le volume
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "mount $device $mount_point" 2>/dev/null; then
        ok "$device monté sur $mount_point"
        
        # Ajouter au fstab pour montage automatique
        local uuid
        uuid=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "blkid -s UUID -o value $device" 2>/dev/null || echo "")
        
        if [ -n "$uuid" ]; then
            # Vérifier si déjà dans fstab
            if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "grep -q \"$mount_point\" /etc/fstab" 2>/dev/null; then
                ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" "echo \"UUID=$uuid $mount_point xfs defaults,noatime 0 2\" >> /etc/fstab" &>/dev/null
                log "  Ajouté au fstab (UUID: $uuid)"
            fi
        fi
        
        return 0
    else
        ko "Échec montage de $device"
        return 1
    fi
}

# Trouver le device du volume
find_volume_device() {
    local server_ip=$1
    
    # Attendre un peu que le volume soit visible
    sleep 3
    
    # Chercher un device non monté
    local device
    device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
        "for dev in /dev/sd[b-z] /dev/vd[b-z]; do [ -b \"\$dev\" ] && ! mount | grep -q \"\$dev\" && echo \"\$dev\" && break; done" 2>/dev/null || echo "")
    
    if [ -z "$device" ]; then
        # Essayer avec lsblk
        device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "lsblk -o NAME,TYPE,MOUNTPOINT -n | grep -v '^loop' | grep -v '^sr0' | grep -v '/$' | grep -v 'swap' | grep 'disk' | head -1 | awk '{print \"/dev/\"\$1}'" 2>/dev/null || echo "")
    fi
    
    echo "$device"
}

# Traiter un serveur
process_server() {
    local server_name=$1
    local mount_point=$2
    
    echo ""
    log "Traitement de $server_name"
    
    # Obtenir l'IP publique
    local server_ip
    server_ip=$(get_server_ip "$server_name")
    
    if [ -z "$server_ip" ]; then
        ko "Impossible de trouver l'IP pour $server_name dans $INVENTORY_TSV"
        return 1
    fi
    
    log "IP: $server_ip"
    
    # Vérifier si le serveur a besoin d'un volume
    if [ -z "$mount_point" ]; then
        warn "$server_name n'a pas besoin de volume (master)"
        return 0
    fi
    
    local vol_name="vol-$server_name"
    
    # Vérifier que le volume existe
    if ! hcloud volume describe "$vol_name" &>/dev/null; then
        warn "$vol_name n'existe pas, skip"
        return 1
    fi
    
    # Attacher le volume (utiliser le nom pour hcloud)
    if ! attach_volume "$vol_name" "$server_name"; then
        return 1
    fi
    
    # Attendre un peu que le volume soit visible
    sleep 5
    
    # Trouver le device (utiliser l'IP pour SSH)
    local device
    device=$(find_volume_device "$server_ip")
    
    if [ -z "$device" ]; then
        ko "Impossible de trouver le device pour $vol_name sur $server_name ($server_ip)"
        ssh -o StrictHostKeyChecking=no root@"$server_ip" "lsblk" || true
        return 1
    fi
    
    log "Device trouvé : $device"
    
    # Formater en XFS (utiliser l'IP pour SSH)
    if ! format_volume_xfs "$server_ip" "$device"; then
        return 1
    fi
    
    # Monter le volume (utiliser l'IP pour SSH)
    if ! mount_volume "$server_ip" "$device" "$mount_point"; then
        return 1
    fi
    
    return 0
}

# Main
main() {
    section "Formatage et montage des volumes K8s"
    
    log "Ce script va :"
    log "  1. Attacher les volumes aux serveurs K8s"
    log "  2. Formater les volumes en XFS"
    log "  3. Monter les volumes sur les points de montage appropriés"
    log "  4. Configurer le montage automatique (fstab)"
    echo ""
    log "Démarrage automatique..."
    echo ""
    
    # Vérifier hcloud
    if ! command -v hcloud &> /dev/null; then
        ko "hcloud CLI n'est pas installé"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        ko "jq n'est pas installé"
        exit 1
    fi
    
    # Vérifier le token
    if ! hcloud server list &> /dev/null; then
        ko "Impossible de se connecter à Hetzner Cloud. Vérifiez le token."
        exit 1
    fi
    
    # Vérifier que le fichier inventory existe
    if [ ! -f "$INVENTORY_TSV" ]; then
        ko "Fichier inventory introuvable: $INVENTORY_TSV"
        exit 1
    fi
    
    local attached=0
    local formatted=0
    local mounted=0
    local failed=0
    
    for server_name in "${!SERVER_MOUNT_POINTS[@]}"; do
        mount_point="${SERVER_MOUNT_POINTS[$server_name]}"
        
        if process_server "$server_name" "$mount_point"; then
            ((attached++))
            ((formatted++))
            ((mounted++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    section "Résumé"
    echo "Attachés: $attached"
    echo "Formatés: $formatted"
    echo "Montés: $mounted"
    echo "Échecs: $failed"
    echo ""
    
    if [ $failed -eq 0 ]; then
        ok "Tous les volumes ont été formatés et montés avec succès"
    else
        warn "Certains volumes ont échoué ($failed échecs)"
    fi
}

main "$@"

