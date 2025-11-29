#!/usr/bin/env bash
# Script pour corriger les règles iptables FORWARD pour Flannel

set +e

echo "=============================================================="
echo " [KeyBuzz] Correction iptables FORWARD pour Flannel"
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
    
    # Ajouter les règles iptables pour autoriser le trafic Flannel
    ssh -o StrictHostKeyChecking=no root@"$ip" "bash -c '
        # Autoriser le trafic FORWARD pour Flannel (10.42.0.0/16)
        iptables -I FORWARD -s 10.42.0.0/16 -d 10.42.0.0/16 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -s 10.43.0.0/16 -d 10.43.0.0/16 -j ACCEPT 2>/dev/null || true
        
        # Autoriser le trafic sur l''interface flannel.1
        iptables -I FORWARD -i flannel.1 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -o flannel.1 -j ACCEPT 2>/dev/null || true
        
        # Autoriser le trafic sur l''interface cni0
        iptables -I FORWARD -i cni0 -j ACCEPT 2>/dev/null || true
        iptables -I FORWARD -o cni0 -j ACCEPT 2>/dev/null || true
        
        echo \"✅ Règles iptables ajoutées\"
        
        # Vérifier
        echo \"Règles FORWARD (premières 10):\"
        iptables -L FORWARD -n -v | head -15
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
    echo "✅ Toutes les règles iptables ont été ajoutées !"
    echo ""
    echo "Testez maintenant depuis master-01 vers le pod:"
    ssh -o StrictHostKeyChecking=no root@"10.0.0.100" "timeout 5 curl -s http://10.42.5.5/ 2>&1 | head -3" || echo "Test échoué"
else
    echo "⚠️  Certains nœuds ont échoué."
fi

echo ""
echo "=============================================================="

