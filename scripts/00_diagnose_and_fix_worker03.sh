#!/bin/bash
set -uo pipefail

export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

WORKER="k8s-worker-03"
MOUNT_POINT="/mnt/k8s-worker"
IP="157.90.119.183"

echo "==============================================="
echo "  DIAGNOSTIC ET CORRECTION k8s-worker-03"
echo "==============================================="
echo ""

echo "1. État actuel du serveur:"
ssh root@"$IP" "mount | grep -E 'sdb|k8s-worker' || echo 'Aucun montage sdb/k8s-worker'"
echo ""

echo "2. État du device:"
ssh root@"$IP" "lsblk -f | grep -A 2 sdb || echo 'Device sdb non trouvé'"
echo ""

echo "3. Vérification formatage:"
ssh root@"$IP" "if blkid /dev/sdb 2>/dev/null | grep -q xfs; then echo 'Déjà formaté en XFS'; blkid /dev/sdb; else echo 'Pas formaté en XFS'; fi"
echo ""

echo "4. Vérification montage:"
ssh root@"$IP" "if mountpoint -q $MOUNT_POINT 2>/dev/null; then echo 'Déjà monté sur $MOUNT_POINT'; df -h $MOUNT_POINT; else echo 'Pas monté sur $MOUNT_POINT'; fi"
echo ""

echo "5. Tentative de démontage forcé:"
ssh root@"$IP" "sync; umount -f /dev/sdb 2>/dev/null || true; umount -l /dev/sdb 2>/dev/null || true; umount -f $MOUNT_POINT 2>/dev/null || true; umount -l $MOUNT_POINT 2>/dev/null || true; sleep 2; echo 'Démontage effectué'"
echo ""

echo "6. Vérification processus utilisant le device:"
ssh root@"$IP" "lsof | grep sdb || echo 'Aucun processus utilisant sdb'; fuser -v /dev/sdb 2>/dev/null || echo 'fuser: aucun processus'"
echo ""

echo "7. Tentative de formatage:"
if ssh root@"$IP" "mkfs.xfs -f /dev/sdb 2>&1"; then
    echo "✓ Formatage réussi"
    
    echo "8. Montage:"
    ssh root@"$IP" "mkdir -p $MOUNT_POINT"
    if ssh root@"$IP" "mount /dev/sdb $MOUNT_POINT"; then
        echo "✓ Montage réussi"
        
        UUID=$(ssh root@"$IP" "blkid -s UUID -o value /dev/sdb")
        if [ -n "$UUID" ]; then
            if ! ssh root@"$IP" "grep -q \"$MOUNT_POINT\" /etc/fstab"; then
                ssh root@"$IP" "echo \"UUID=$UUID $MOUNT_POINT xfs defaults,noatime 0 2\" >> /etc/fstab"
                echo "✓ Ajouté à /etc/fstab"
            fi
        fi
        
        echo ""
        echo "9. Vérification finale:"
        ssh root@"$IP" "df -h $MOUNT_POINT"
        echo ""
        echo "✓ $WORKER traité avec succès"
    else
        echo "✗ Erreur montage"
    fi
else
    echo "✗ Erreur formatage - le device est peut-être déjà utilisé"
    echo ""
    echo "Vérification alternative:"
    ssh root@"$IP" "dmesg | tail -20 | grep -i sdb || echo 'Pas de message sdb dans dmesg'"
fi

echo ""
echo "==============================================="

