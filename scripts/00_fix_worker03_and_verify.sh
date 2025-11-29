#!/bin/bash
set -uo pipefail

export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

WORKER="k8s-worker-03"
MOUNT_POINT="/mnt/k8s-worker"

echo "==============================================="
echo "  CORRECTION k8s-worker-03"
echo "==============================================="
echo ""

# Obtenir l'IP depuis servers.tsv
IP=$(awk -F'\t' -v w="$WORKER" '$3==w {print $2}' /opt/keybuzz-installer/inventory/servers.tsv)

if [ -z "$IP" ]; then
    echo "ERREUR: Impossible de trouver l'IP pour $WORKER"
    exit 1
fi

echo "Traitement de $WORKER ($IP)..."

# Démonter si nécessaire
echo "Vérification des montages existants..."
ssh root@"$IP" "sync; umount -f /dev/sdb 2>/dev/null || true; umount -l /dev/sdb 2>/dev/null || true; umount -f $MOUNT_POINT 2>/dev/null || true; umount -l $MOUNT_POINT 2>/dev/null || true" || true
sleep 3

# Forcer la libération du device
echo "Libération du device..."
ssh root@"$IP" "partprobe /dev/sdb 2>/dev/null || true; sleep 2" || true

# Trouver le device
DEVICE=$(ssh root@"$IP" "lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk '{print \"/dev/\"\$1}'")

if [ -z "$DEVICE" ]; then
    echo "ERREUR: Device non trouvé"
    exit 1
fi

echo "Device: $DEVICE"

# Formater
echo "Formatage en XFS..."
if ssh root@"$IP" "mkfs.xfs -f $DEVICE"; then
    echo "✓ Formatage réussi"
else
    echo "✗ Erreur formatage"
    exit 1
fi

# Créer le point de montage
ssh root@"$IP" "mkdir -p $MOUNT_POINT" || exit 1

# Monter
echo "Montage..."
if ssh root@"$IP" "mount $DEVICE $MOUNT_POINT"; then
    echo "✓ Montage réussi"
else
    echo "✗ Erreur montage"
    exit 1
fi

# Ajouter à fstab
UUID=$(ssh root@"$IP" "blkid -s UUID -o value $DEVICE")
if [ -n "$UUID" ]; then
    if ! ssh root@"$IP" "grep -q \"$MOUNT_POINT\" /etc/fstab"; then
        ssh root@"$IP" "echo \"UUID=$UUID $MOUNT_POINT xfs defaults,noatime 0 2\" >> /etc/fstab"
        echo "✓ Ajouté à /etc/fstab"
    fi
fi

echo ""
echo "✓ $WORKER traité avec succès"
echo ""

echo "==============================================="
echo "  VERIFICATION FINALE"
echo "==============================================="
echo ""

for worker in k8s-worker-01 k8s-worker-02 k8s-worker-03 k8s-worker-04 k8s-worker-05; do
    IP=$(awk -F'\t' -v w="$worker" '$3==w {print $2}' /opt/keybuzz-installer/inventory/servers.tsv)
    if [ -n "$IP" ]; then
        echo "=== $worker ($IP) ==="
        if ssh root@"$IP" "mountpoint -q $MOUNT_POINT && df -h $MOUNT_POINT" 2>/dev/null; then
            echo "✓ Volume monté correctement"
        else
            echo "✗ Volume non monté"
        fi
        echo ""
    fi
done

echo "==============================================="

