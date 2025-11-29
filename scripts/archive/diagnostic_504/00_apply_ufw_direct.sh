#!/usr/bin/env bash
set +e  # Ne pas arrêter en cas d'erreur

echo "=============================================================="
echo " [KeyBuzz] Application Directe Règles UFW sur tous les nœuds K3s"
echo "=============================================================="
echo ""

# Liste des nœuds K3s (masters + workers) avec leurs IPs
declare -a K3S_NODES=(
    "k3s-master-01|91.98.124.228"
    "k3s-master-02|91.98.117.26"
    "k3s-master-03|91.98.165.238"
    "k3s-worker-01|116.203.135.192"
    "k3s-worker-02|91.99.164.62"
    "k3s-worker-03|157.90.119.183"
    "k3s-worker-04|91.98.200.38"
    "k3s-worker-05|188.245.45.242"
)

echo "Total: ${#K3S_NODES[@]} nœuds K3s à traiter"
echo ""

SUCCESS=0
FAIL=0
FAILED_NODES=()

# Obtenir l'IP du nœud actuel
CURRENT_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || ip addr show | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -1)

# Pour chaque nœud K3s
for node_info in "${K3S_NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Si c'est le nœud actuel, exécuter directement
    if [[ "$name" == "k3s-master-01" ]] || [[ "$ip" == "$CURRENT_IP" ]]; then
        echo "   ℹ️  Nœud local, exécution directe..."
        ufw allow from 10.42.0.0/16 to any comment "K3s pods network" 2>/dev/null || true
        ufw allow from 10.43.0.0/16 to any comment "K3s services network" 2>/dev/null || true
        ufw allow 8472/udp comment "K3s flannel VXLAN" 2>/dev/null || true
        ufw allow 10250/tcp comment "K3s kubelet" 2>/dev/null || true
        echo "   ✅ Règles UFW ajoutées sur $name"
        ((SUCCESS++))
        echo ""
        continue
    fi
    
    # Exécuter les commandes UFW directement via SSH pour les nœuds distants
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" "bash -c '
        ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\" 2>/dev/null || true
        ufw allow from 10.43.0.0/16 to any comment \"K3s services network\" 2>/dev/null || true
        ufw allow 8472/udp comment \"K3s flannel VXLAN\" 2>/dev/null || true
        ufw allow 10250/tcp comment \"K3s kubelet\" 2>/dev/null || true
        echo \"✅ Règles UFW ajoutées\"
    '" 2>/dev/null; then
        echo "   ✅ Règles UFW ajoutées sur $name"
        ((SUCCESS++))
    else
        echo "   ❌ Échec sur $name (vérifiez l'accès SSH)"
        ((FAIL++))
        FAILED_NODES+=("$name")
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Succès: $SUCCESS / ${#K3S_NODES[@]}"
echo "❌ Échecs: $FAIL / ${#K3S_NODES[@]}"
echo ""

if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
    echo "Nœuds en échec:"
    for node in "${FAILED_NODES[@]}"; do
        echo "  - $node"
    done
    echo ""
    echo "⚠️  Pour les nœuds en échec, exécutez manuellement:"
    echo "   ssh root@<IP> 'ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\"'"
    echo "   ssh root@<IP> 'ufw allow from 10.43.0.0/16 to any comment \"K3s services network\"'"
    echo ""
fi

echo "=============================================================="
echo " ✅ Traitement terminé"
echo "=============================================================="
echo ""
echo "Attendez 10 secondes puis testez les URLs pour vérifier"
echo "que le problème 504 est résolu."
echo ""

