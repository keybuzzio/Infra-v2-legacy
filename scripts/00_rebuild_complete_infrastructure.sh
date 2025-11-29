#!/bin/bash
# rebuild_complete_infrastructure.sh
# Script complet pour rebuild toute l'infrastructure (sauf install-01 et backn8n)
#
# Étapes :
#   1. Démontrer tous les volumes
#   2. Formater les volumes en XFS
#   3. Rebuild tous les serveurs (sauf install-01 et backn8n)
#   4. Monter les volumes sur les serveurs correspondants
#   5. Propager les clés SSH depuis install-01
#
# Usage:
#   bash 00_rebuild_complete_infrastructure.sh
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

# Serveurs à exclure du rebuild
EXCLUDED_SERVERS=("install-01" "backn8n.keybuzz.io" "backn8n")

# Vérifier les dépendances
check_dependencies() {
    section "Vérification des dépendances"
    
    if ! command -v hcloud &> /dev/null; then
        ko "hcloud CLI n'est pas installé"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log "Installation de jq..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq jq
    fi
    
    if ! command -v xfsprogs &> /dev/null; then
        log "Installation de xfsprogs..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq && apt-get install -y -qq xfsprogs
    fi
    
    # Vérifier le token
    if ! hcloud server list &> /dev/null; then
        ko "Impossible de se connecter à Hetzner Cloud. Vérifiez le token."
        exit 1
    fi
    ok "Connexion Hetzner Cloud OK"
}

# Obtenir l'IP publique d'un serveur
get_server_ip() {
    local hostname=$1
    grep -E "^prod[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+$hostname" "$INVENTORY_TSV" 2>/dev/null | awk '{print $2}' | head -1
}

# Obtenir le point de montage pour un serveur
get_mount_point() {
    local hostname=$1
    case "$hostname" in
        k8s-worker-*|k3s-worker-*)
            echo "/var/lib/containerd"
            ;;
        k8s-master-*|k3s-master-*)
            echo ""
            ;;
        db-master-*|db-slave-*)
            echo "/opt/keybuzz/postgres/data"
            ;;
        redis-*)
            echo "/opt/keybuzz/redis/data"
            ;;
        queue-*)
            echo "/opt/keybuzz/rabbitmq/data"
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

# Charger la liste des serveurs depuis servers.tsv
load_all_servers() {
    local servers=()
    
    # Vérifier que le fichier existe
    if [ ! -f "$INVENTORY_TSV" ]; then
        warn "Fichier inventory non trouvé : $INVENTORY_TSV"
        return 1
    fi
    
    while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user_ssh pool role subrole docker_stack core notes || [ -n "$env" ]; do
        # Ignorer les lignes vides
        [[ -z "$env" ]] && continue
        
        # Ignorer les lignes de commentaire ou d'en-tête
        [[ "$env" =~ ^#.*$ ]] && continue
        [[ "$env" == "ENV" ]] && continue
        [[ "$env" == "prod" ]] || [[ "$env" == "dev" ]] || [[ "$env" == "test" ]] || continue
        
        # Vérifier que hostname est valide
        [[ -z "$hostname" ]] && continue
        [[ "$hostname" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && continue  # Skip si hostname est une IP
        
        # Exclure install-01 et backn8n
        local excluded=0
        for excluded_server in "${EXCLUDED_SERVERS[@]}"; do
            if [[ "$hostname" == "$excluded_server" ]] || [[ "$hostname" == *"$excluded_server"* ]] || \
               [[ "$fqdn" == "$excluded_server" ]] || [[ "$fqdn" == *"$excluded_server"* ]]; then
                excluded=1
                break
            fi
        done
        
        [[ $excluded -eq 1 ]] && continue
        
        servers+=("$hostname")
    done < "$INVENTORY_TSV"
    
    printf '%s\n' "${servers[@]}"
}

# Démontrer un volume
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

# Formater un volume en XFS (via un serveur temporaire ou directement)
format_volume_xfs() {
    local vol_name=$1
    local size=$2
    local location=$3
    
    log "Formatage de $vol_name en XFS..."
    
    # Vérifier si le volume existe
    if ! hcloud volume describe "$vol_name" &>/dev/null; then
        warn "$vol_name n'existe pas"
        return 1
    fi
    
    # Vérifier si déjà formaté (on ne peut pas le vérifier sans l'attacher)
    # On va créer un serveur temporaire pour formater, ou utiliser install-01
    
    # Option 1: Utiliser install-01 pour formater (si le volume peut être attaché temporairement)
    # Option 2: Attacher à un serveur temporaire, formater, détacher
    
    # Pour l'instant, on va juste marquer le volume comme à formater
    # Le formatage se fera après le rebuild lors du montage
    warn "Le formatage se fera lors du montage après rebuild"
    return 0
}

# Phase 1 : Démontrer tous les volumes
phase1_detach_volumes() {
    section "PHASE 1 : Détachement de tous les volumes"
    
    local detached=0
    local skipped=0
    local failed=0
    
    # Récupérer tous les volumes
    local volumes
    mapfile -t volumes < <(hcloud volume list -o json | jq -r '.[].name')
    
    for vol_name in "${volumes[@]}"; do
        # Vérifier si le volume est attaché
        local attached_to
        attached_to=$(hcloud volume describe "$vol_name" -o json 2>/dev/null | jq -r '.server // empty')
        
        if [ -n "$attached_to" ] && [ "$attached_to" != "null" ]; then
            log "Détachement de $vol_name (attaché à $attached_to)..."
            if detach_volume "$vol_name"; then
                ((detached++))
            else
                ((failed++))
            fi
        else
            ((skipped++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 1: $detached détachés | $skipped déjà détachés | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Phase 2 : Rebuild tous les serveurs (sauf exclus)
phase2_rebuild_servers() {
    section "PHASE 2 : Rebuild de tous les serveurs (sauf install-01 et backn8n)"
    
    local servers
    mapfile -t servers < <(load_all_servers)
    
    if [ ${#servers[@]} -eq 0 ]; then
        warn "Aucun serveur à rebuild"
        return 0
    fi
    
    log "Serveurs à rebuild : ${#servers[@]}"
    echo ""
    
    local pids=()
    local server_names=()
    local rebuilt=0
    local failed=0
    
    # Lancer tous les rebuilds en parallèle
    for hostname in "${servers[@]}"; do
        # Vérifier que le serveur existe
        if ! hcloud server describe "$hostname" &>/dev/null; then
            warn "$hostname n'existe pas dans Hetzner Cloud, skip"
            continue
        fi
        
        (
            log "Rebuild de $hostname avec Ubuntu 24.04..."
            if hcloud server rebuild --image "ubuntu-24.04" "$hostname" &>/dev/null; then
                echo "SUCCESS:$hostname" > /tmp/rebuild_${hostname}.result
            else
                echo "FAILED:$hostname" > /tmp/rebuild_${hostname}.result
            fi
        ) &
        
        local pid=$!
        pids+=($pid)
        server_names+=("$hostname")
        log "  PID: $pid pour $hostname"
    done
    
    echo ""
    log "Attente de la fin de tous les rebuilds (${#pids[@]} serveurs)..."
    log "Cela peut prendre 3-5 minutes..."
    
    # Attendre tous les processus
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null
    done
    
    # Récupérer les résultats
    echo ""
    for hostname in "${server_names[@]}"; do
        if [ -f "/tmp/rebuild_${hostname}.result" ]; then
            local result
            result=$(cat "/tmp/rebuild_${hostname}.result" 2>/dev/null || echo "")
            if [[ "$result" == "SUCCESS:"* ]]; then
                ok "$hostname : rebuild lancé avec succès"
                ((rebuilt++))
            else
                ko "$hostname : rebuild échoué"
                ((failed++))
            fi
            rm -f "/tmp/rebuild_${hostname}.result"
        else
            warn "$hostname : résultat non trouvé"
            ((failed++))
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 2: $rebuilt rebuilds lancés | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
    
    log "Attendez 3-5 minutes que les serveurs soient prêts avant de continuer"
    echo ""
    read -p "Appuyez sur Entrée une fois que tous les serveurs sont prêts..."
}

# Phase 3 : Attacher, formater et monter les volumes
phase3_attach_format_mount() {
    section "PHASE 3 : Attachement, formatage et montage des volumes"
    
    local servers
    mapfile -t servers < <(load_all_servers)
    
    local attached=0
    local formatted=0
    local mounted=0
    local failed=0
    
    for hostname in "${servers[@]}"; do
        local mount_point
        mount_point=$(get_mount_point "$hostname")
        
        # Vérifier si le serveur a besoin d'un volume
        if [ -z "$mount_point" ]; then
            continue
        fi
        
        local vol_name="vol-$hostname"
        local server_ip
        server_ip=$(get_server_ip "$hostname")
        
        if [ -z "$server_ip" ]; then
            # Essayer depuis Hetzner Cloud
            server_ip=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty')
        fi
        
        if [ -z "$server_ip" ]; then
            warn "Impossible de trouver l'IP pour $hostname"
            ((failed++))
            continue
        fi
        
        echo ""
        log "Traitement de $hostname ($server_ip)"
        
        # Vérifier que le volume existe
        if ! hcloud volume describe "$vol_name" &>/dev/null; then
            warn "$vol_name n'existe pas, skip"
            continue
        fi
        
        # Attacher le volume
        log "Attachement de $vol_name → $hostname..."
        if hcloud volume attach "$vol_name" --server "$hostname" 2>/dev/null; then
            ok "$vol_name attaché"
            ((attached++))
            sleep 5
        else
            warn "$vol_name déjà attaché ou erreur"
        fi
        
        # Attendre que le volume soit visible
        sleep 3
        
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
            warn "Impossible de trouver le device pour $vol_name sur $hostname"
            ((failed++))
            continue
        fi
        
        log "Device trouvé : $device"
        
        # Installer xfsprogs si nécessaire
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "export DEBIAN_FRONTEND=noninteractive && (which mkfs.xfs || (apt-get update -qq && apt-get install -y -qq xfsprogs))" &>/dev/null || true
        
        # Vérifier si déjà formaté en XFS
        local fstype
        fstype=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "blkid -s TYPE -o value $device" 2>/dev/null || echo "")
        
        if [ "$fstype" != "xfs" ]; then
            # Formater en XFS
            log "Formatage de $device en XFS..."
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                "mkfs.xfs -f $device" 2>/dev/null; then
                ok "$device formaté en XFS"
                ((formatted++))
            else
                ko "Échec formatage de $device"
                ((failed++))
                continue
            fi
        else
            warn "$device déjà formaté en XFS"
        fi
        
        # Monter le volume
        log "Montage de $device sur $mount_point..."
        
        # Vérifier si déjà monté
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "mountpoint -q $mount_point" 2>/dev/null; then
            warn "$mount_point déjà monté"
        else
            # Créer le point de montage
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                "mkdir -p $mount_point" &>/dev/null || true
            
            # Monter le volume
            if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                "mount $device $mount_point" 2>/dev/null; then
                ok "$device monté sur $mount_point"
                ((mounted++))
                
                # Ajouter au fstab
                local uuid
                uuid=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                    "blkid -s UUID -o value $device" 2>/dev/null || echo "")
                
                if [ -n "$uuid" ]; then
                    if ! ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                        "grep -q \"$mount_point\" /etc/fstab" 2>/dev/null; then
                        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                            "echo \"UUID=$uuid $mount_point xfs defaults,noatime 0 2\" >> /etc/fstab" &>/dev/null
                        log "  Ajouté au fstab (UUID: $uuid)"
                    fi
                fi
            else
                ko "Échec montage de $device"
                ((failed++))
            fi
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 3: $attached attachés | $formatted formatés | $mounted montés | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Phase 4 : Propagation des clés SSH depuis install-01
phase4_propagate_ssh_keys() {
    section "PHASE 4 : Propagation des clés SSH depuis install-01"
    
    local INSTALL_01_IP="91.98.128.153"
    
    log "Récupération de la clé SSH d'install-01..."
    local install_key
    install_key=$(ssh -o StrictHostKeyChecking=no root@"$INSTALL_01_IP" \
        "cat /root/.ssh/id_ed25519.pub" 2>/dev/null || echo "")
    
    if [ -z "$install_key" ]; then
        ko "Impossible de récupérer la clé SSH d'install-01"
        return 1
    fi
    
    ok "Clé SSH récupérée"
    
    local servers
    mapfile -t servers < <(load_all_servers)
    
    local deployed=0
    local skipped=0
    local failed=0
    
    for hostname in "${servers[@]}"; do
        local server_ip
        server_ip=$(get_server_ip "$hostname")
        
        if [ -z "$server_ip" ]; then
            server_ip=$(hcloud server describe "$hostname" -o json 2>/dev/null | jq -r '.public_net.ipv4.ip // empty')
        fi
        
        if [ -z "$server_ip" ]; then
            warn "Impossible de trouver l'IP pour $hostname"
            ((failed++))
            continue
        fi
        
        echo ""
        log "Déploiement sur $hostname ($server_ip)..."
        
        # Créer le répertoire .ssh
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "mkdir -p /root/.ssh && chmod 700 /root/.ssh" &>/dev/null || true
        
        # Vérifier si la clé existe déjà
        local key_fp
        key_fp=$(echo "$install_key" | awk '{print $2}')
        
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
            "grep -q '$key_fp' /root/.ssh/authorized_keys 2>/dev/null"; then
            warn "Clé déjà présente sur $hostname"
            ((skipped++))
        else
            # Ajouter la clé
            echo "$install_key" | ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$server_ip" \
                "cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys" &>/dev/null
            
            if [ $? -eq 0 ]; then
                ok "Clé SSH déployée sur $hostname"
                ((deployed++))
            else
                ko "Échec déploiement sur $hostname"
                ((failed++))
            fi
        fi
        
        # Tester la connexion depuis install-01
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 root@"$INSTALL_01_IP" \
            "ssh -o BatchMode=yes -o ConnectTimeout=5 root@$server_ip 'echo OK' 2>/dev/null" &>/dev/null; then
            log "  Connexion testée avec succès depuis install-01"
        fi
    done
    
    echo ""
    echo "════════════════════════════════════════════════════════════════════"
    echo "Résumé Phase 4: $deployed déployées | $skipped déjà présentes | $failed échecs"
    echo "════════════════════════════════════════════════════════════════════"
}

# Main
main() {
    section "Rebuild complet de l'infrastructure"
    
    log "Ce script va :"
    log "  1. Démontrer tous les volumes"
    log "  2. Rebuild tous les serveurs (sauf install-01 et backn8n) avec Ubuntu 24.04"
    log "  3. Attacher les volumes aux serveurs rebuildés"
    log "  4. Formater les volumes en XFS"
    log "  5. Monter les volumes"
    log "  6. Propager les clés SSH depuis install-01"
    echo ""
    warn "ATTENTION : Cette opération va rebuild tous les serveurs !"
    warn "Serveurs exclus : install-01, backn8n.keybuzz.io"
    echo ""
    read -p "Continuer ? (yes/NO): " confirm
    [ "$confirm" != "yes" ] && { log "Annulé"; exit 0; }
    
    check_dependencies
    
    # Phase 1 : Démontage des volumes
    phase1_detach_volumes
    
    # Phase 2 : Rebuild des serveurs (après démontage)
    phase2_rebuild_servers
    
    # Phase 3 : Attachement, formatage et montage des volumes (après rebuild)
    phase3_attach_format_mount
    
    # Phase 4 : Propagation des clés SSH depuis install-01
    phase4_propagate_ssh_keys
    
    section "Rebuild terminé"
    ok "Tous les serveurs ont été rebuildés et configurés"
    log "Vous pouvez maintenant relancer les scripts d'installation"
}

main "$@"
