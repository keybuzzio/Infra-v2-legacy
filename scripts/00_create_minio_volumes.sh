#!/bin/bash
set -uo pipefail

# Script pour créer, attacher, formater et monter les volumes MinIO manquants
export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

echo "==============================================="
echo "  CREATION VOLUMES MINIO-02 ET MINIO-03"
echo "==============================================="
echo ""

# 1. Récupérer la taille et location de vol-minio-01
echo "Récupération des infos de vol-minio-01..."
SIZE=$(hcloud volume describe vol-minio-01 -o json | jq -r '.size')
LOCATION=$(hcloud volume describe vol-minio-01 -o json | jq -r '.location.name')
echo "Taille: ${SIZE}GB, Location: ${LOCATION}"
echo ""

# 2. Récupérer les IDs des serveurs
echo "Récupération des IDs des serveurs..."
SERVER02_ID=$(hcloud server describe minio-02 -o json | jq -r '.id')
SERVER03_ID=$(hcloud server describe minio-03 -o json | jq -r '.id')
echo "minio-02: ${SERVER02_ID}, minio-03: ${SERVER03_ID}"
echo ""

# 3. Créer les volumes en parallèle
echo "Création des volumes en parallèle..."
(hcloud volume create --name vol-minio-02 --size "$SIZE" --location "$LOCATION" && echo "✓ vol-minio-02 créé") &
PID1=$!
(hcloud volume create --name vol-minio-03 --size "$SIZE" --location "$LOCATION" && echo "✓ vol-minio-03 créé") &
PID2=$!
wait $PID1 $PID2
echo ""

# 4. Attacher les volumes en parallèle
echo "Attachement des volumes en parallèle..."
(hcloud volume attach --server "$SERVER02_ID" vol-minio-02 && echo "✓ vol-minio-02 attaché") &
PID1=$!
(hcloud volume attach --server "$SERVER03_ID" vol-minio-03 && echo "✓ vol-minio-03 attaché") &
PID2=$!
wait $PID1 $PID2
sleep 5
echo ""

# 5. Récupérer les IPs
IP02=$(hcloud server describe minio-02 -o json | jq -r '.public_net.ipv4.ip')
IP03=$(hcloud server describe minio-03 -o json | jq -r '.public_net.ipv4.ip')
echo "IPs: minio-02=$IP02, minio-03=$IP03"
echo ""

# 6. Formater en XFS en parallèle
echo "Formatage en XFS en parallèle..."
(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$IP02" '
    DEV=$(lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk "{print \"/dev/\"\$1}")
    if [ -n "$DEV" ]; then
        mkfs.xfs -f "$DEV" && echo "✓ minio-02: $DEV formaté"
    else
        echo "✗ minio-02: device non trouvé"
    fi
') &
PID1=$!
(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$IP03" '
    DEV=$(lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk "{print \"/dev/\"\$1}")
    if [ -n "$DEV" ]; then
        mkfs.xfs -f "$DEV" && echo "✓ minio-03: $DEV formaté"
    else
        echo "✗ minio-03: device non trouvé"
    fi
') &
PID2=$!
wait $PID1 $PID2
echo ""

# 7. Monter les volumes en parallèle
echo "Montage des volumes en parallèle..."
(ssh -o StrictHostKeyChecking=no root@"$IP02" '
    DEV=$(lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk "{print \"/dev/\"\$1}")
    if [ -n "$DEV" ]; then
        mkdir -p /opt/keybuzz/minio/data
        mount "$DEV" /opt/keybuzz/minio/data
        UUID=$(blkid -s UUID -o value "$DEV")
        if ! grep -q "/opt/keybuzz/minio/data" /etc/fstab; then
            echo "UUID=$UUID /opt/keybuzz/minio/data xfs defaults,noatime 0 2" >> /etc/fstab
        fi
        echo "✓ minio-02: monté sur /opt/keybuzz/minio/data"
    else
        echo "✗ minio-02: device non trouvé"
    fi
') &
PID1=$!
(ssh -o StrictHostKeyChecking=no root@"$IP03" '
    DEV=$(lsblk -n -o NAME,TYPE | grep disk | grep -v sda | head -1 | awk "{print \"/dev/\"\$1}")
    if [ -n "$DEV" ]; then
        mkdir -p /opt/keybuzz/minio/data
        mount "$DEV" /opt/keybuzz/minio/data
        UUID=$(blkid -s UUID -o value "$DEV")
        if ! grep -q "/opt/keybuzz/minio/data" /etc/fstab; then
            echo "UUID=$UUID /opt/keybuzz/minio/data xfs defaults,noatime 0 2" >> /etc/fstab
        fi
        echo "✓ minio-03: monté sur /opt/keybuzz/minio/data"
    else
        echo "✗ minio-03: device non trouvé"
    fi
') &
PID2=$!
wait $PID1 $PID2
echo ""

# 8. Vérification finale
echo "==============================================="
echo "  VERIFICATION FINALE"
echo "==============================================="
echo ""
echo "Volumes:"
hcloud volume list -o json | jq -r '.[] | select(.name | startswith("vol-minio")) | "\(.name): \(.size)GB, server=\(.server // "none")"'
echo ""
echo "Montages:"
ssh -o StrictHostKeyChecking=no root@"$IP02" 'df -h | grep minio' || echo "minio-02: montage non trouvé"
ssh -o StrictHostKeyChecking=no root@"$IP03" 'df -h | grep minio' || echo "minio-03: montage non trouvé"
echo ""
echo "✓ Terminé !"





