#!/bin/bash
set -uo pipefail

export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

WORKER="k8s-worker-03"
MOUNT_POINT="/mnt/k8s-worker"

echo "Traitement de $WORKER..."

# Obtenir l'IP
IP=$(hcloud server describe "$WORKER" -o json | jq -r '.public_net.ipv4.ip')

if [ -z "$IP" ]; then
    echo "ERREUR: Impossible de trouver l'IP pour $WORKER"
    exit 1
fi

echo "IP: $IP"

# Trouver le device
DEVICE=$(ssh root@"$IP" "lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk '{print \"/dev/\"\$1}'")

if [ -z "$DEVICE" ]; then
    echo "ERREUR: Device non trouvé"
    exit 1
fi

echo "Device: $DEVICE"

# Formater
echo "Formatage en XFS..."
ssh root@"$IP" "mkfs.xfs -f $DEVICE" || exit 1

# Créer le point de montage
ssh root@"$IP" "mkdir -p $MOUNT_POINT" || exit 1

# Monter
echo "Montage..."
ssh root@"$IP" "mount $DEVICE $MOUNT_POINT" || exit 1

# Ajouter à fstab
UUID=$(ssh root@"$IP" "blkid -s UUID -o value $DEVICE")
if [ -n "$UUID" ]; then
    if ! ssh root@"$IP" "grep -q \"$MOUNT_POINT\" /etc/fstab"; then
        ssh root@"$IP" "echo \"UUID=$UUID $MOUNT_POINT xfs defaults,noatime 0 2\" >> /etc/fstab"
    fi
fi

echo "OK: $WORKER traité avec succès"

