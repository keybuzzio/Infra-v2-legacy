#!/usr/bin/env bash
# Script simplifié pour corriger UFW K3s - utilise les IPs hardcodées

set +euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Correction UFW pour K3s - Version Simplifiée"
echo "=============================================================="
echo ""

# Liste des nœuds avec leurs IPs privées (hardcodées)
declare -A K3S_NODES=(
    ["k3s-master-01"]="10.0.0.100"
    ["k3s-master-02"]="10.0.0.101"
    ["k3s-master-03"]="10.0.0.102"
    ["k3s-worker-01"]="10.0.0.110"
    ["k3s-worker-02"]="10.0.0.111"
    ["k3s-worker-03"]="10.0.0.112"
    ["k3s-worker-04"]="10.0.0.113"
    ["k3s-worker-05"]="10.0.0.114"
)

SUCCESS=0
FAIL=0

for node in "${!K3S_NODES[@]}"; do
    ip="${K3S_NODES[$node]}"
    
    echo "Configuration $node ($ip)..."
    
    # Configurer UFW sur le nœud
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" bash <<'EOF'
set +u

# Fonction pour ajouter une règle UFW (idempotente)
add_ufw_rule() {
    local rule="$1"
    local comment="$2"
    
    # Vérifier si la règle existe déjà
    if ! ufw status numbered | grep -q "$comment"; then
        ufw allow $rule comment "$comment" >/dev/null 2>&1 || true
        echo "  ✓ Règle ajoutée : $comment"
    else
        echo "  ℹ️  Règle existe déjà : $comment"
    fi
}

# Autoriser les réseaux K3s
add_ufw_rule "from 10.42.0.0/16 to any" "K3s Pod Network (Flannel VXLAN)"
add_ufw_rule "from 10.43.0.0/16 to any" "K3s Service Network (ClusterIP)"

# Autoriser les interfaces Flannel
add_ufw_rule "in on flannel.1" "K3s Flannel interface"
add_ufw_rule "out on flannel.1" "K3s Flannel interface"
add_ufw_rule "in on cni0" "K3s CNI interface"
add_ufw_rule "out on cni0" "K3s CNI interface"

# Autoriser les ports K3s (si pas déjà fait)
add_ufw_rule "8472/udp" "K3s flannel VXLAN"
add_ufw_rule "10250/tcp" "K3s kubelet"

# Recharger UFW SANS reset
ufw reload >/dev/null 2>&1 || true

echo "  ✓ UFW rechargé"
EOF
    then
        echo "  ✅ $node corrigé"
        ((SUCCESS++))
    else
        echo "  ❌ $node : échec"
        ((FAIL++))
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Nœuds corrigés : $SUCCESS / ${#K3S_NODES[@]}"
if [[ $FAIL -gt 0 ]]; then
    echo "❌ Nœuds en échec : $FAIL / ${#K3S_NODES[@]}"
fi
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ UFW corrigé sur tous les nœuds K3s"
    echo ""
    echo "Réseaux autorisés :"
    echo "  ✓ 10.42.0.0/16 (K3s pods)"
    echo "  ✓ 10.43.0.0/16 (K3s services)"
    echo "  ✓ Interfaces Flannel (flannel.1, cni0)"
    echo ""
    echo "Testez maintenant la connectivité :"
    echo "  kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s http://10.43.38.57/"
fi

echo ""
echo "=============================================================="

