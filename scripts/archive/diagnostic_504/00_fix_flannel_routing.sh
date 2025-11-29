#!/usr/bin/env bash
# Script pour diagnostiquer et corriger le problème de routage Flannel

set +e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Routage Flannel"
echo "=============================================================="
echo ""

MASTER_IP="10.0.0.100"

# Vérifier Flannel sur tous les nœuds
echo "1. Vérification Flannel sur tous les nœuds..."
echo ""

declare -a NODES=(
    "k3s-master-01|10.0.0.100"
    "k3s-master-02|10.0.0.101"
    "k3s-master-03|10.0.0.102"
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-03|10.0.0.112"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

for node_info in "${NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "$name ($ip):"
    echo "=========================================="
    
    # Vérifier Flannel
    ssh -o StrictHostKeyChecking=no root@"$ip" "bash -c '
        echo \"Flannel pods:\"
        kubectl get pods -n kube-system -l app=flannel 2>/dev/null | head -3 || echo \"   Flannel non trouvé\"
        echo \"\"
        echo \"Routes réseau (10.42.x.x):\"
        ip route | grep \"10.42\" | head -5 || echo \"   Aucune route 10.42 trouvée\"
        echo \"\"
        echo \"Interface Flannel:\"
        ip addr show | grep -A 5 \"flannel\" | head -10 || echo \"   Interface flannel non trouvée\"
    '" 2>&1 | head -20
    
    echo ""
done

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

