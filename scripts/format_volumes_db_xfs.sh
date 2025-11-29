#!/bin/bash
# format_volumes_db_xfs.sh - Formate et monte les volumes XFS pour les serveurs DB
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $*"; }
ko() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }

echo "=== FORMATAGE VOLUMES XFS POUR SERVEURS DB ==="
echo ""

DB_SERVERS=(
    "db-master-01:10.0.0.120:100:/opt/keybuzz/postgres/data"
    "db-slave-01:10.0.0.121:50:/opt/keybuzz/postgres/data"
    "db-slave-02:10.0.0.122:50:/opt/keybuzz/postgres/data"
)

for server_info in "${DB_SERVERS[@]}"; do
    IFS=':' read -r hostname ip size mount_path <<< "$server_info"
    
    echo "=== Traitement de $hostname ($ip) ==="
    
    # Vérifier si déjà monté
    if ssh -o StrictHostKeyChecking=no root@$ip "mountpoint -q $mount_path" 2>/dev/null; then
        fs_type=$(ssh -o StrictHostKeyChecking=no root@$ip "df -T $mount_path | tail -1 | awk '{print \$2}'" 2>/dev/null)
        if [[ "$fs_type" == "xfs" ]]; then
            ok "$hostname : Volume déjà monté en XFS"
            continue
        else
            warn "$hostname : Volume monté mais pas en XFS ($fs_type), démontage..."
            ssh -o StrictHostKeyChecking=no root@$ip "umount $mount_path" 2>/dev/null || true
        fi
    fi
    
    # Détecter le device (sdb généralement)
    device=$(ssh -o StrictHostKeyChecking=no root@$ip bash -s "$size" <<'DEVICE_SCRIPT'
        size=$1
        TARGET_SIZE=$((size * 1000000000))
        TOLERANCE=$((TARGET_SIZE / 10))
        for dev in /dev/sd{b..z} /dev/vd{b..z}; do
            [ -b $dev ] || continue
            DEV_SIZE=$(lsblk -b -n -o SIZE $dev 2>/dev/null | head -1)
            [ -z "$DEV_SIZE" ] && continue
            if [ $DEV_SIZE -gt $((TARGET_SIZE - TOLERANCE)) ] && [ $DEV_SIZE -lt $((TARGET_SIZE + TOLERANCE)) ]; then
                mount | grep -q $dev || { echo $dev; break; }
            fi
        done
DEVICE_SCRIPT
    2>/dev/null || echo "")
    
    if [[ -z "$device" ]]; then
        ko "$hostname : Aucun device trouvé"
        continue
    fi
    
    warn "$hostname : Device détecté: $device"
    
    # Installer xfsprogs si nécessaire
    ssh -o StrictHostKeyChecking=no root@$ip "apt-get update -qq && apt-get install -y -qq xfsprogs" &>/dev/null || true
    
    # Formater en XFS
    warn "$hostname : Formatage XFS de $device..."
    if ssh -o StrictHostKeyChecking=no root@$ip "mkfs.xfs -f -m crc=1,finobt=1 $device" &>/dev/null; then
        ok "$hostname : Formatage XFS terminé"
    else
        ko "$hostname : Échec formatage"
        continue
    fi
    
    # Créer le point de montage
    ssh -o StrictHostKeyChecking=no root@$ip "mkdir -p $mount_path" &>/dev/null || true
    
    # Monter
    if ssh -o StrictHostKeyChecking=no root@$ip "mount -t xfs -o noatime,nodiratime,logbufs=8,logbsize=256k $device $mount_path" &>/dev/null; then
        ok "$hostname : Volume monté"
        
        # Ajouter au fstab
        uuid=$(ssh -o StrictHostKeyChecking=no root@$ip "blkid -s UUID -o value $device" 2>/dev/null || echo "")
        if [[ -n "$uuid" ]]; then
            if ! ssh -o StrictHostKeyChecking=no root@$ip "grep -q '$mount_path' /etc/fstab" 2>/dev/null; then
                ssh -o StrictHostKeyChecking=no root@$ip "echo 'UUID=$uuid $mount_path xfs defaults,noatime,nodiratime,logbufs=8,logbsize=256k,nofail 0 2' >> /etc/fstab" &>/dev/null
                ok "$hostname : Ajouté au fstab"
            fi
        fi
        
        # Permissions
        ssh -o StrictHostKeyChecking=no root@$ip "chown -R 999:999 $mount_path" &>/dev/null || true
    else
        ko "$hostname : Échec montage"
    fi
    
    echo ""
done

echo "=== VERIFICATION FINALE ==="
for server_info in "${DB_SERVERS[@]}"; do
    IFS=':' read -r hostname ip size mount_path <<< "$server_info"
    fs_type=$(ssh -o StrictHostKeyChecking=no root@$ip "df -T $mount_path 2>/dev/null | tail -1 | awk '{print \$2}'" 2>/dev/null || echo "NON_MONTE")
    if [[ "$fs_type" == "xfs" ]]; then
        ok "$hostname : XFS monté sur $mount_path"
    else
        ko "$hostname : Volume non monté ou pas en XFS"
    fi
done

