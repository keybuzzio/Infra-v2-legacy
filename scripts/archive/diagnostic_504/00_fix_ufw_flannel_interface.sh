#!/usr/bin/env bash
# Script pour autoriser le trafic sur l'interface flannel.1 dans UFW

set +e

echo "=============================================================="
echo " [KeyBuzz] Autorisation Trafic Flannel dans UFW"
echo "=============================================================="
echo ""

# Liste de tous les nœuds K3s
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

SUCCESS=0
FAIL=0

# Pour chaque nœud
for node_info in "${NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Autoriser le trafic sur l'interface flannel.1
    ssh -o StrictHostKeyChecking=no root@"$ip" "bash -c '
        # Autoriser le trafic sur l''interface flannel.1
        ufw allow in on flannel.1 comment \"K3s Flannel interface\" 2>/dev/null || true
        ufw allow out on flannel.1 comment \"K3s Flannel interface\" 2>/dev/null || true
        
        # Autoriser aussi sur cni0
        ufw allow in on cni0 comment \"K3s CNI interface\" 2>/dev/null || true
        ufw allow out on cni0 comment \"K3s CNI interface\" 2>/dev/null || true
        
        echo \"✅ Règles UFW pour Flannel ajoutées\"
        
        # Vérifier
        echo \"Règles Flannel:\"
        ufw status | grep -E \"flannel|cni0\" || echo \"Aucune règle trouvée\"
    '" 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ Règles ajoutées sur $name"
        ((SUCCESS++))
    else
        echo "   ❌ Échec sur $name"
        ((FAIL++))
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Succès: $SUCCESS / ${#NODES[@]}"
echo "❌ Échecs: $FAIL / ${#NODES[@]}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Toutes les règles UFW pour Flannel ont été ajoutées !"
    echo ""
    echo "Testez maintenant depuis master-01 vers le pod:"
    ssh -o StrictHostKeyChecking=no root@"10.0.0.100" "timeout 5 curl -s http://10.42.5.5/ 2>&1 | head -3" || echo "Test échoué"
else
    echo "⚠️  Certains nœuds ont échoué."
fi

echo ""
echo "=============================================================="

