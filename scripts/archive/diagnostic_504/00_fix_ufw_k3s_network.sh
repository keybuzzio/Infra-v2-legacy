#!/usr/bin/env bash
set -e

# Chercher servers.tsv dans plusieurs emplacements possibles
SERVERS_FILE=""
for path in "/root/install-01/servers.tsv" "/root/servers.tsv" "$(dirname "${BASH_SOURCE[0]}")/../servers.tsv" "$(dirname "${BASH_SOURCE[0]}")/../../servers.tsv"; do
    if [[ -f "$path" ]]; then
        SERVERS_FILE="$path"
        break
    fi
done

if [[ ! -f "$SERVERS_FILE" ]]; then
    echo "❌ Fichier servers.tsv introuvable: $SERVERS_FILE"
    exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Correction UFW sur tous les nœuds K3s"
echo "=============================================================="
echo ""

# Lire servers.tsv et extraire les nœuds K3s avec leurs IPs
declare -a K3S_NODES=()
while IFS=$'\t' read -r name ip role zone; do
    if [[ "$role" == *"k3s"* ]] || [[ "$role" == *"master"* ]] || [[ "$role" == *"worker"* ]]; then
        K3S_NODES+=("$name|$ip")
        echo "Nœud K3s trouvé: $name ($ip)"
    fi
done < <(tail -n +2 "$SERVERS_FILE")

if [[ ${#K3S_NODES[@]} -eq 0 ]]; then
    echo "❌ Aucun nœud K3s trouvé dans servers.tsv"
    exit 1
fi

echo ""
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

