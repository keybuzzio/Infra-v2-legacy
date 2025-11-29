#!/bin/bash
# migration_k3s_vers_k8s.sh
# Script pour migrer de K3s vers K8s : renommer serveurs et volumes
#
# Usage:
#   bash 00_migration_k3s_vers_k8s.sh
#

set -uo pipefail
# Ne pas arrêter sur erreur (-e retiré) pour continuer même si certains volumes/serveurs n'existent pas

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

# Mapping des serveurs à renommer
declare -A SERVER_MAPPING=(
    ["k3s-master-01"]="k8s-master-01"
    ["k3s-master-02"]="k8s-master-02"
    ["k3s-master-03"]="k8s-master-03"
    ["k3s-worker-01"]="k8s-worker-01"
    ["k3s-worker-02"]="k8s-worker-02"
    ["k3s-worker-03"]="k8s-worker-03"
    ["k3s-worker-04"]="k8s-worker-04"
    ["k3s-worker-05"]="k8s-worker-05"
)

# Vérifier que hcloud est installé
check_dependencies() {
    section "Vérification des dépendances"
    
    if ! command -v hcloud &> /dev/null; then
        ko "hcloud CLI n'est pas installé"
        log "Installation de hcloud..."
        curl -fsSL https://github.com/hetznercloud/cli/releases/latest/download/hcloud-linux-amd64.tar.gz | tar -xz
        sudo mv hcloud /usr/local/bin/
        ok "hcloud installé"
    else
        ok "hcloud est installé"
    fi
    
    if ! command -v jq &> /dev/null; then
        ko "jq n'est pas installé"
        log "Installation de jq..."
        export DEBIAN_FRONTEND=noninteractive
        sudo apt-get update -qq && sudo apt-get install -y -qq jq
        ok "jq installé"
    else
        ok "jq est installé"
    fi
    
    # Vérifier le token
    if ! hcloud server list &> /dev/null; then
        ko "Impossible de se connecter à Hetzner Cloud. Vérifiez le token."
        exit 1
    fi
    ok "Connexion Hetzner Cloud OK"
}

# Lister les volumes attachés à un serveur
get_volumes_for_server() {
    local server_name=$1
    hcloud volume list -o json | jq -r --arg server "$server_name" '.[] | select(.server == $server) | .name'
}

# Détacher un volume
detach_volume() {
    local vol_name=$1
    log "Détachement de $vol_name..."
    
    if hcloud volume detach "$vol_name" 2>/dev/null; then
        ok "$vol_name détaché"
        sleep 2
        return 0
    else
        warn "$vol_name déjà détaché ou erreur"
        return 1
    fi
}

# Renommer un volume (créer nouveau + supprimer ancien)
rename_volume() {
    local old_name=$1
    local new_name=$2
    
    log "Renommage de $old_name → $new_name..."
    
    # Vérifier que l'ancien volume existe
    if ! hcloud volume describe "$old_name" &>/dev/null; then
        warn "$old_name n'existe pas, skip"
        return 1
    fi
    
    # Vérifier que le nouveau nom n'existe pas déjà
    if hcloud volume describe "$new_name" &>/dev/null; then
        warn "$new_name existe déjà, skip"
        return 0  # Considéré comme OK si déjà renommé
    fi
    
    # Récupérer les infos du volume
    local vol_info
    vol_info=$(hcloud volume describe "$old_name" -o json 2>/dev/null)
    if [ -z "$vol_info" ]; then
        ko "Impossible de récupérer les infos de $old_name"
        return 1
    fi
    
    local size location
    size=$(echo "$vol_info" | jq -r '.size')
    location=$(echo "$vol_info" | jq -r '.location.name')
    
    # Vérifier que le volume est bien détaché
    local attached_to
    attached_to=$(echo "$vol_info" | jq -r '.server // empty')
    if [ -n "$attached_to" ] && [ "$attached_to" != "null" ]; then
        warn "$old_name est encore attaché à $attached_to, détachement..."
        detach_volume "$old_name"
        sleep 3
    fi
    
    log "Création du nouveau volume $new_name (${size}GB @ $location)..."
    if hcloud volume create --name "$new_name" --size "$size" --location "$location" &>/dev/null; then
        ok "Volume $new_name créé"
        sleep 2
        
        log "Suppression de l'ancien volume $old_name..."
        if hcloud volume delete "$old_name" &>/dev/null; then
            ok "Ancien volume $old_name supprimé"
            return 0
        else
            warn "Impossible de supprimer $old_name (peut nécessiter un détachement manuel)"
            return 1
        fi
    else
        ko "Échec création de $new_name"
        return 1
    fi
}

# Formater un volume en XFS (sur le serveur)
format_volume_xfs() {
    local server_name=$1
    local vol_name=$2
    
    log "Formatage de $vol_name en XFS sur $server_name..."
    
    # Attendre que le volume soit visible
    sleep 5
    
    # Trouver le device du volume (généralement /dev/sdb ou /dev/sdc)
    local device=""
    local max_attempts=10
    local attempt=0
    
    while [ $attempt -lt $max_attempts ] && [ -z "$device" ]; do
        # Chercher un device non monté et non utilisé pour le système
        device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$server_name" \
            "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE -n | grep -v '^loop' | grep -v '^sr0' | grep -v '/$' | grep -v 'swap' | grep -v 'ext4' | grep -v 'xfs' | head -1 | awk '{print \"/dev/\"\$1}'" 2>/dev/null || echo "")
        
        if [ -n "$device" ]; then
            break
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    if [ -z "$device" ]; then
        # Essayer de trouver n'importe quel device non monté
        device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$server_name" \
            "for dev in /dev/sd[b-z] /dev/vd[b-z]; do [ -b \"\$dev\" ] && ! mount | grep -q \"\$dev\" && echo \"\$dev\" && break; done" 2>/dev/null || echo "")
    fi
    
    if [ -z "$device" ]; then
        warn "Impossible de trouver le device pour $vol_name sur $server_name"
        log "Tentative de détection manuelle..."
        ssh -o StrictHostKeyChecking=no root@"$server_name" "lsblk" || true
        return 1
    fi
    
    log "Device trouvé : $device"
    
    # Installer xfsprogs si nécessaire
    ssh -o StrictHostKeyChecking=no root@"$server_name" "export DEBIAN_FRONTEND=noninteractive && (which mkfs.xfs || (apt-get update -qq && apt-get install -y -qq xfsprogs))" &>/dev/null || true
    
    # Formater en XFS
    if ssh -o StrictHostKeyChecking=no root@"$server_name" "mkfs.xfs -f $device" 2>/dev/null; then
        ok "$vol_name formaté en XFS ($device)"
        return 0
    else
        ko "Échec formatage de $vol_name sur $device"
        return 1
    fi
}

# Attacher un volume à un serveur
attach_volume() {
    local vol_name=$1
    local server_name=$2
    
    log "Attachement de $vol_name → $server_name..."
    
    if hcloud volume attach "$vol_name" --server "$server_name" 2>/dev/null; then
        ok "$vol_name attaché à $server_name"
        sleep 3
        return 0
    else
        ko "Échec attachement de $vol_name"
        return 1
    fi
}

# Renommer un serveur
rename_server() {
    local old_name=$1
    local new_name=$2
    
    log "Renommage du serveur $old_name → $new_name..."
    
    # Vérifier que l'ancien serveur existe
    if ! hcloud server describe "$old_name" &>/dev/null; then
        warn "$old_name n'existe pas"
        return 1
    fi
    
    # Renommer le serveur
    if hcloud server update --name "$new_name" "$old_name" 2>/dev/null; then
        ok "Serveur renommé : $old_name → $new_name"
        sleep 2
        return 0
    else
        ko "Échec renommage de $old_name"
        return 1
    fi
}

# Rebuild un serveur (version silencieuse pour exécution en parallèle)
rebuild_server() {
    local server_name=$1
    local image="ubuntu-24.04"
    
    # Lancer le rebuild
    if ! hcloud server rebuild --image "$image" "$server_name" &>/dev/null; then
        return 1
    fi
    
    # Attendre un peu que le rebuild démarre
    sleep 10
    
    # Attendre que le serveur soit prêt (SSH accessible)
    local max_attempts=60  # 10 minutes max (60 * 10s)
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -o BatchMode=yes root@"$server_name" "echo 'OK'" &>/dev/null 2>&1; then
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 10
    done
    
    # Timeout
    return 1
}

# Phase 1 : Détacher et renommer les volumes
phase1_volumes() {
    section "PHASE 1 : Détachement et renommage des volumes"
    
    local detached=0
    local renamed=0
    local failed=0
    local skipped=0
    
    for old_name in "${!SERVER_MAPPING[@]}"; do
        new_name="${SERVER_MAPPING[$old_name]}"
        old_vol="vol-$old_name"
        new_vol="vol-$new_name"
        
        echo ""
        log "Traitement de $old_name → $new_name"
        
        # Vérifier si le nouveau volume existe déjà
        if hcloud volume describe "$new_vol" &>/dev/null; then
            warn "$new_vol existe déjà, skip"
            ((skipped++))
            continue
        fi
        
        # Détacher le volume
        if detach_volume "$old_vol"; then
            ((detached++))
        fi
        
        # Renommer le volume
        if rename_volume "$old_vol" "$new_vol"; then
            ((renamed++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 1: $detached détachés | $renamed renommés | $skipped déjà faits | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Phase 2 : Renommer les serveurs
phase2_servers() {
    section "PHASE 2 : Renommage des serveurs"
    
    local renamed=0
    local failed=0
    
    for old_name in "${!SERVER_MAPPING[@]}"; do
        new_name="${SERVER_MAPPING[$old_name]}"
        
        echo ""
        log "Renommage de $old_name → $new_name"
        
        if rename_server "$old_name" "$new_name"; then
            ((renamed++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 2: $renamed renommés | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Phase 3 : Rebuild des serveurs (en parallèle)
phase3_rebuild() {
    section "PHASE 3 : Rebuild des serveurs (en parallèle)"
    
    local rebuilt=0
    local failed=0
    local pids=()
    local server_names=()
    
    # Lancer tous les rebuilds en arrière-plan
    for old_name in "${!SERVER_MAPPING[@]}"; do
        new_name="${SERVER_MAPPING[$old_name]}"
        
        echo ""
        log "Lancement du rebuild de $new_name en arrière-plan..."
        
        # Fonction wrapper pour capturer le résultat
        (
            if rebuild_server "$new_name"; then
                echo "SUCCESS:$new_name" > /tmp/rebuild_${new_name}.result
            else
                echo "FAILED:$new_name" > /tmp/rebuild_${new_name}.result
            fi
        ) &
        
        local pid=$!
        pids+=($pid)
        server_names+=("$new_name")
        log "  PID: $pid pour $new_name"
    done
    
    echo ""
    log "Attente de la fin de tous les rebuilds (${#pids[@]} serveurs)..."
    log "Cela peut prendre 3-5 minutes..."
    
    # Attendre tous les processus
    local all_done=0
    local wait_count=0
    local max_wait=600  # 10 minutes max
    
    while [ $all_done -eq 0 ] && [ $wait_count -lt $max_wait ]; do
        all_done=1
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                all_done=0
                break
            fi
        done
        
        if [ $all_done -eq 0 ]; then
            sleep 5
            wait_count=$((wait_count + 5))
            if [ $((wait_count % 30)) -eq 0 ]; then
                log "En attente... ($wait_count secondes écoulées)"
            fi
        fi
    done
    
    # Récupérer les résultats
    echo ""
    for new_name in "${server_names[@]}"; do
        if [ -f "/tmp/rebuild_${new_name}.result" ]; then
            local result
            result=$(cat "/tmp/rebuild_${new_name}.result" 2>/dev/null || echo "")
            if [[ "$result" == "SUCCESS:"* ]]; then
                ok "$new_name : rebuild terminé avec succès"
                ((rebuilt++))
            else
                ko "$new_name : rebuild échoué"
                ((failed++))
            fi
            rm -f "/tmp/rebuild_${new_name}.result"
        else
            warn "$new_name : résultat non trouvé (timeout?)"
            ((failed++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 3: $rebuilt rebuilds réussis | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Obtenir le point de montage pour un serveur
get_mount_point() {
    local hostname=$1
    case "$hostname" in
        k8s-worker-*|k3s-worker-*)
            echo "/var/lib/containerd"
            ;;
        k8s-master-*|k3s-master-*)
            # Pas de volume pour les masters
            echo ""
            ;;
        *)
            echo "/opt/keybuzz/data"
            ;;
    esac
}

# Monter un volume
mount_volume() {
    local server_name=$1
    local vol_name=$2
    local mount_point=$3
    local device=$4
    
    log "Montage de $vol_name sur $mount_point..."
    
    # Créer le point de montage
    ssh -o StrictHostKeyChecking=no root@"$server_name" "mkdir -p $mount_point" &>/dev/null || true
    
    # Monter le volume
    if ssh -o StrictHostKeyChecking=no root@"$server_name" "mount $device $mount_point" 2>/dev/null; then
        ok "$vol_name monté sur $mount_point"
        
        # Ajouter au fstab pour montage automatique
        local uuid
        uuid=$(ssh -o StrictHostKeyChecking=no root@"$server_name" "blkid -s UUID -o value $device" 2>/dev/null || echo "")
        
        if [ -n "$uuid" ]; then
            # Vérifier si déjà dans fstab
            if ! ssh -o StrictHostKeyChecking=no root@"$server_name" "grep -q \"$mount_point\" /etc/fstab" 2>/dev/null; then
                ssh -o StrictHostKeyChecking=no root@"$server_name" "echo \"UUID=$uuid $mount_point xfs defaults,noatime 0 2\" >> /etc/fstab" &>/dev/null
                log "  Ajouté au fstab (UUID: $uuid)"
            fi
        fi
        
        return 0
    else
        ko "Échec montage de $vol_name"
        return 1
    fi
}

# Phase 4 : Attacher, formater et monter les volumes
phase4_attach_format_mount() {
    section "PHASE 4 : Attachement, formatage et montage des volumes"
    
    local attached=0
    local formatted=0
    local mounted=0
    local failed=0
    
    for old_name in "${!SERVER_MAPPING[@]}"; do
        new_name="${SERVER_MAPPING[$old_name]}"
        new_vol="vol-$new_name"
        mount_point=$(get_mount_point "$new_name")
        
        echo ""
        log "Traitement de $new_name"
        
        # Vérifier si le serveur a besoin d'un volume (masters n'ont pas de volume)
        if [ -z "$mount_point" ]; then
            warn "$new_name n'a pas besoin de volume (master)"
            continue
        fi
        
        # Attacher le volume
        if attach_volume "$new_vol" "$new_name"; then
            ((attached++))
            
            # Formater en XFS
            local device=""
            if format_volume_xfs "$new_name" "$new_vol"; then
                ((formatted++))
                
                # Trouver le device après formatage
                sleep 3
                device=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$new_name" \
                    "for dev in /dev/sd[b-z] /dev/vd[b-z]; do [ -b \"\$dev\" ] && ! mount | grep -q \"\$dev\" && blkid \"\$dev\" | grep -q xfs && echo \"\$dev\" && break; done" 2>/dev/null || echo "")
                
                if [ -n "$device" ]; then
                    log "Device XFS trouvé : $device"
                    
                    # Monter le volume
                    if mount_volume "$new_name" "$new_vol" "$mount_point" "$device"; then
                        ((mounted++))
                    else
                        ((failed++))
                    fi
                else
                    warn "Impossible de trouver le device XFS pour $new_name"
                    ((failed++))
                fi
            else
                ((failed++))
            fi
        else
            ((failed++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 4: $attached attachés | $formatted formatés | $mounted montés | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Phase 5 : Mettre à jour servers.tsv
phase5_update_tsv() {
    section "PHASE 5 : Mise à jour de servers.tsv"
    
    local tsv_file="/opt/keybuzz-installer/inventory/servers.tsv"
    
    if [ ! -f "$tsv_file" ]; then
        warn "Fichier $tsv_file introuvable"
        return 1
    fi
    
    log "Mise à jour de $tsv_file..."
    
    # Créer une sauvegarde
    cp "$tsv_file" "${tsv_file}.backup.$(date +%Y%m%d_%H%M%S)"
    ok "Sauvegarde créée"
    
    # Remplacer les noms dans le fichier
    for old_name in "${!SERVER_MAPPING[@]}"; do
        new_name="${SERVER_MAPPING[$old_name]}"
        sed -i "s/$old_name/$new_name/g" "$tsv_file"
        log "  $old_name → $new_name"
    done
    
    # Mettre à jour les rôles et pools
    sed -i 's/k3s-masters/k8s-masters/g' "$tsv_file"
    sed -i 's/k3s-workers/k8s-workers/g' "$tsv_file"
    sed -i 's/k3s/k8s/g' "$tsv_file"
    
    ok "Fichier $tsv_file mis à jour"
}

# Main
main() {
    section "Migration K3s → K8s : Renommage serveurs et volumes"
    
    log "Ce script va :"
    log "  1. Détacher et renommer les volumes (vol-k3s-xxx → vol-k8s-xxx)"
    log "  2. Renommer les serveurs (k3s-xxx → k8s-xxx)"
    log "  3. Rebuild les serveurs avec Ubuntu 24.04"
    log "  4. Attacher et formater les volumes en XFS"
    log "  5. Mettre à jour servers.tsv"
    echo ""
    log "Démarrage automatique (pas de confirmation requise)..."
    echo ""
    
    check_dependencies
    
    phase1_volumes
    phase2_servers
    phase3_rebuild
    phase4_attach_format_mount
    phase5_update_tsv
    
    section "Migration terminée"
    ok "Tous les serveurs et volumes ont été migrés de K3s vers K8s"
    log "Vérifiez le fichier servers.tsv et relancez les scripts d'installation K8s"
}

main "$@"

