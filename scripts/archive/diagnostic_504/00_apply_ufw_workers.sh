#!/usr/bin/env bash
set +e

echo "=============================================================="
echo " [KeyBuzz] Application Règles UFW sur tous les Workers"
echo "=============================================================="
echo ""

# Liste des workers avec leurs IPs privées
declare -a WORKERS=(
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-03|10.0.0.112"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

echo "Total: ${#WORKERS[@]} workers à traiter"
echo ""
echo "⚠️  Ce script nécessite un accès SSH configuré vers les workers."
echo "   Si l'accès SSH n'est pas configuré, exécutez manuellement sur chaque worker:"
echo ""
echo "   ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\""
echo "   ufw allow from 10.43.0.0/16 to any comment \"K3s services network\""
echo "   ufw allow 8472/udp comment \"K3s flannel VXLAN\""
echo "   ufw allow 10250/tcp comment \"K3s kubelet\""
echo ""
echo "Appuyez sur Entrée pour continuer ou Ctrl+C pour annuler..."
read

SUCCESS=0
FAIL=0
FAILED_NODES=()

# Pour chaque worker
for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip <<< "$worker_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Tenter la connexion SSH
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" "bash -c '
        ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\" 2>/dev/null || true
        ufw allow from 10.43.0.0/16 to any comment \"K3s services network\" 2>/dev/null || true
        ufw allow 8472/udp comment \"K3s flannel VXLAN\" 2>/dev/null || true
        ufw allow 10250/tcp comment \"K3s kubelet\" 2>/dev/null || true
        echo \"✅ Règles UFW ajoutées\"
    '" 2>&1; then
        echo "   ✅ Règles UFW ajoutées sur $name"
        ((SUCCESS++))
    else
        echo "   ❌ Échec sur $name"
        echo "   ⚠️  Exécutez manuellement sur ce nœud:"
        echo "      ssh root@$ip"
        echo "      ufw allow from 10.42.0.0/16 to any comment \"K3s pods network\""
        echo "      ufw allow from 10.43.0.0/16 to any comment \"K3s services network\""
        echo "      ufw allow 8472/udp comment \"K3s flannel VXLAN\""
        echo "      ufw allow 10250/tcp comment \"K3s kubelet\""
        ((FAIL++))
        FAILED_NODES+=("$name")
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Succès: $SUCCESS / ${#WORKERS[@]}"
echo "❌ Échecs: $FAIL / ${#WORKERS[@]}"
echo ""

if [[ ${#FAILED_NODES[@]} -gt 0 ]]; then
    echo "Nœuds en échec (à traiter manuellement):"
    for node in "${FAILED_NODES[@]}"; do
        echo "  - $node"
    done
    echo ""
fi

echo "=============================================================="
echo " ✅ Traitement terminé"
echo "=============================================================="

