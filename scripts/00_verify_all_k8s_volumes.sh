#!/bin/bash
set -uo pipefail

echo "==============================================="
echo "  VERIFICATION FINALE - VOLUMES K8S WORKERS"
echo "==============================================="
echo ""

WORKERS=("k8s-worker-01" "k8s-worker-02" "k8s-worker-03" "k8s-worker-04" "k8s-worker-05")
TSV_FILE="/opt/keybuzz-installer/inventory/servers.tsv"
MOUNT_POINT="/mnt/k8s-worker"

SUCCESS=0
FAILED=0

for worker in "${WORKERS[@]}"; do
    IP=$(awk -F'\t' -v w="$worker" '$3==w {print $2}' "$TSV_FILE")
    
    if [ -z "$IP" ]; then
        echo "⚠️  $worker: IP non trouvée dans servers.tsv"
        ((FAILED++))
        continue
    fi
    
    echo "=== $worker ($IP) ==="
    
    if ssh root@"$IP" "mountpoint -q $MOUNT_POINT && df -h $MOUNT_POINT" 2>/dev/null; then
        echo "✓ Volume monté correctement"
        ((SUCCESS++))
    else
        echo "✗ Volume non monté"
        ((FAILED++))
    fi
    echo ""
done

echo "==============================================="
echo "Résumé:"
echo "  ✓ Réussis: $SUCCESS"
if [ $FAILED -gt 0 ]; then
    echo "  ✗ Échecs: $FAILED"
fi
echo "==============================================="

if [ $FAILED -eq 0 ]; then
    exit 0
else
    exit 1
fi

