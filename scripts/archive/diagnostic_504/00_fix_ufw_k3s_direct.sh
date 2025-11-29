#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Correction UFW sur tous les nœuds K3s"
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

echo "Total: ${#K3S_NODES[@]} nœuds K3s"
echo ""

# Pour chaque nœud K3s, ajouter les règles UFW
for node_info in "${K3S_NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Vérifier UFW actuel
    echo "Vérification UFW actuel:"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "ufw status | grep -E '10\.42\.|10\.43\.|K3s|k3s' || echo 'Aucune règle K3s trouvée'" 2>/dev/null || echo "⚠️  Impossible de se connecter"
    echo ""
    
    # Ajouter les règles UFW nécessaires pour K3s
    echo "Ajout des règles UFW pour K3s..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "bash -c '
        # Autoriser le réseau des pods K3s (10.42.0.0/16)
        ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\" 2>/dev/null || true
        
        # Autoriser le réseau des services K3s (10.43.0.0/16)
        ufw allow from 10.43.0.0/16 to any comment \"K3s services network\" 2>/dev/null || true
        
        # Autoriser Flannel VXLAN (port 8472/udp)
        ufw allow 8472/udp comment \"K3s flannel VXLAN\" 2>/dev/null || true
        
        # Autoriser Kubelet (port 10250/tcp)
        ufw allow 10250/tcp comment \"K3s kubelet\" 2>/dev/null || true
        
        echo \"✅ Règles UFW ajoutées\"
    '" 2>/dev/null && echo "✅ Règles ajoutées sur $name" || echo "❌ Échec sur $name"
    
    echo ""
done

echo "=============================================================="
echo " ✅ Correction terminée"
echo "=============================================================="
echo ""
echo "Attendez 10 secondes puis testez les URLs."
echo ""

