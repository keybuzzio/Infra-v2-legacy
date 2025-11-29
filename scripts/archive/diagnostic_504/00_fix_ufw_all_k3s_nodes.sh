#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVERS_FILE="${SCRIPT_DIR}/servers.tsv"

if [[ ! -f "$SERVERS_FILE" ]]; then
    echo "❌ Fichier servers.tsv introuvable: $SERVERS_FILE"
    exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Correction UFW sur tous les nœuds K3s"
echo "=============================================================="
echo ""

# Lire servers.tsv et extraire les nœuds K3s
K3S_NODES=()
while IFS=$'\t' read -r name ip role zone; do
    if [[ "$role" == *"k3s"* ]] || [[ "$role" == *"master"* ]] || [[ "$role" == *"worker"* ]]; then
        K3S_NODES+=("$name|$ip")
    fi
done < <(tail -n +2 "$SERVERS_FILE")

if [[ ${#K3S_NODES[@]} -eq 0 ]]; then
    echo "❌ Aucun nœud K3s trouvé dans servers.tsv"
    exit 1
fi

echo "Nœuds K3s trouvés: ${#K3S_NODES[@]}"
echo ""

# Pour chaque nœud K3s, ajouter les règles UFW
for node_info in "${K3S_NODES[@]}"; do
    IFS='|' read -r name ip <<< "$node_info"
    echo "Traitement de $name ($ip)..."
    
    # Vérifier UFW actuel
    echo "  Vérification UFW actuel:"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "ufw status | grep -E '10\.42\.|10\.43\.|K3s' || echo '    Aucune règle K3s trouvée'" 2>/dev/null || echo "    ⚠️  Impossible de se connecter"
    
    # Ajouter les règles UFW
    echo "  Ajout des règles UFW..."
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "bash -c '
        ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\" 2>/dev/null || true
        ufw allow from 10.43.0.0/16 to any comment \"K3s services network\" 2>/dev/null || true
        ufw allow 8472/udp comment \"K3s flannel VXLAN\" 2>/dev/null || true
        ufw allow 10250/tcp comment \"K3s kubelet\" 2>/dev/null || true
        echo \"    ✅ Règles UFW ajoutées\"
    '" 2>/dev/null || echo "    ⚠️  Impossible d'ajouter les règles"
    
    echo ""
done

echo "=============================================================="
echo " ✅ Correction terminée"
echo "=============================================================="
echo ""
echo "Testez maintenant les URLs pour voir si le problème est résolu."
echo ""

