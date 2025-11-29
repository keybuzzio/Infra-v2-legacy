#!/usr/bin/env bash
# Script pour corriger les routes Flannel manquantes

set +e

echo "=============================================================="
echo " [KeyBuzz] Correction Routes Flannel Manquantes"
echo "=============================================================="
echo ""

# Le pod KeyBuzz est sur 10.42.5.5 (réseau 10.42.5.0/24)
# Worker-03 gère ce réseau (10.42.5.0/24)
# Il faut ajouter la route vers 10.42.5.0/24 sur tous les autres nœuds

WORKER03_IP="10.0.0.112"
WORKER03_FLANNEL_IP="10.42.5.0"  # IP Flannel de worker-03

echo "Worker-03 Flannel IP: $WORKER03_FLANNEL_IP"
echo "Réseau à router: 10.42.5.0/24"
echo ""

# Liste de tous les nœuds SAUF worker-03
declare -a NODES=(
    "k3s-master-01|10.0.0.100"
    "k3s-master-02|10.0.0.101"
    "k3s-master-03|10.0.0.102"
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

SUCCESS=0
FAIL=0

# Pour chaque nœud (sauf worker-03)
for node_info in "${NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Vérifier si la route existe déjà
    echo "Vérification route existante:"
    ssh -o StrictHostKeyChecking=no root@"$ip" "ip route | grep '10.42.5.0/24' || echo 'Route non trouvée'" 2>&1
    
    # Ajouter la route si elle n'existe pas
    echo "Ajout de la route 10.42.5.0/24..."
    ssh -o StrictHostKeyChecking=no root@"$ip" "bash -c '
        # Vérifier si la route existe
        if ! ip route | grep -q \"10.42.5.0/24\"; then
            # Ajouter la route via flannel.1
            ip route add 10.42.5.0/24 via $WORKER03_FLANNEL_IP dev flannel.1 onlink 2>/dev/null || true
            echo \"✅ Route ajoutée\"
        else
            echo \"ℹ️  Route déjà présente\"
        fi
        
        # Vérifier
        echo \"Routes 10.42.5.x:\"
        ip route | grep \"10.42.5\"
    '" 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ Route configurée sur $name"
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
    echo "✅ Toutes les routes ont été ajoutées !"
    echo ""
    echo "Testez maintenant depuis master-01 vers le pod:"
    ssh -o StrictHostKeyChecking=no root@"10.0.0.100" "timeout 5 curl -s http://10.42.5.5/ 2>&1 | head -3" || echo "Test échoué"
else
    echo "⚠️  Certains nœuds ont échoué."
fi

echo ""
echo "=============================================================="

