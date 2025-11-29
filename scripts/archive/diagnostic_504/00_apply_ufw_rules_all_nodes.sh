#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Application Automatique Règles UFW sur tous les nœuds K3s"
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

# Script UFW à exécuter
UFW_SCRIPT="00_add_ufw_rules_k3s.sh"

# Vérifier que le script existe
if [[ ! -f "$UFW_SCRIPT" ]]; then
    echo "❌ Script $UFW_SCRIPT introuvable dans le répertoire courant"
    echo "   Assurez-vous d'être dans le bon répertoire"
    exit 1
fi

echo "Total: ${#K3S_NODES[@]} nœuds K3s à traiter"
echo ""

SUCCESS=0
FAIL=0
FAILED_NODES=()

# Obtenir l'IP du nœud actuel
CURRENT_IP=$(hostname -I | awk '{print $1}' || ip addr show | grep -oP 'inet \K[0-9.]+' | grep -v '127.0.0.1' | head -1)

# Pour chaque nœud K3s
for node_info in "${K3S_NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Si c'est le nœud actuel, exécuter directement
    if [[ "$ip" == "$CURRENT_IP" ]] || [[ "$name" == "k3s-master-01" ]]; then
        echo "   ℹ️  Nœud local, exécution directe..."
        if bash "$UFW_SCRIPT" 2>/dev/null; then
            echo "   ✅ Règles UFW ajoutées"
            ((SUCCESS++))
        else
            echo "   ❌ Échec de l'exécution"
            ((FAIL++))
            FAILED_NODES+=("$name")
        fi
        echo ""
        continue
    fi
    
    # Copier le script sur le nœud distant
    echo "1. Copie du script..."
    scp -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$UFW_SCRIPT" root@"$ip":/root/ 2>/dev/null && echo "   ✅ Script copié" || {
        echo "   ❌ Échec de la copie"
        ((FAIL++))
        FAILED_NODES+=("$name")
        echo ""
        continue
    }
    
    # Exécuter le script sur le nœud distant
    echo "2. Exécution du script..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" "chmod +x /root/$UFW_SCRIPT && bash /root/$UFW_SCRIPT" 2>/dev/null && {
        echo "   ✅ Règles UFW ajoutées"
        ((SUCCESS++))
    } || {
        echo "   ❌ Échec de l'exécution"
        ((FAIL++))
        FAILED_NODES+=("$name")
    }
    
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
    echo "⚠️  Vous devrez exécuter manuellement le script sur ces nœuds:"
    echo "   scp $UFW_SCRIPT root@<IP>:/root/"
    echo "   ssh root@<IP> 'bash /root/$UFW_SCRIPT'"
    echo ""
fi

echo "=============================================================="
echo " ✅ Traitement terminé"
echo "=============================================================="
echo ""
echo "Attendez 10 secondes puis testez les URLs pour vérifier"
echo "que le problème 504 est résolu."
echo ""

