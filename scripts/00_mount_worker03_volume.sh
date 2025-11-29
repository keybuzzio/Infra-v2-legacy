#!/bin/bash
set -uo pipefail

WORKER="k8s-worker-03"
MOUNT_POINT="/mnt/k8s-worker"
IP="157.90.119.183"

echo "==============================================="
echo "  MONTAGE VOLUME k8s-worker-03"
echo "==============================================="
echo ""

echo "1. Vérification du device:"
ssh root@"$IP" "lsblk -o NAME,TYPE,SIZE,MOUNTPOINT,FSTYPE | grep -E '^sda|^NAME'"
echo ""

echo "2. Vérification formatage:"
if ssh root@"$IP" "blkid /dev/sda | grep -q xfs"; then
    echo "✓ Déjà formaté en XFS"
    ssh root@"$IP" "blkid /dev/sda"
else
    echo "✗ Pas formaté en XFS"
    exit 1
fi
echo ""

echo "3. Montage:"
ssh root@"$IP" "mkdir -p $MOUNT_POINT"
if ssh root@"$IP" "mount /dev/sda $MOUNT_POINT"; then
    echo "✓ Montage réussi"
    
    UUID=$(ssh root@"$IP" "blkid -s UUID -o value /dev/sda")
    if [ -n "$UUID" ]; then
        if ! ssh root@"$IP" "grep -q \"$MOUNT_POINT\" /etc/fstab"; then
            ssh root@"$IP" "echo \"UUID=$UUID $MOUNT_POINT xfs defaults,noatime 0 2\" >> /etc/fstab"
            echo "✓ Ajouté à /etc/fstab"
        else
            echo "✓ Déjà dans /etc/fstab"
        fi
    fi
    
    echo ""
    echo "4. Vérification finale:"
    ssh root@"$IP" "df -h $MOUNT_POINT"
    echo ""
    echo "✓ $WORKER traité avec succès"
else
    echo "✗ Erreur montage"
    exit 1
fi

echo ""
echo "==============================================="

