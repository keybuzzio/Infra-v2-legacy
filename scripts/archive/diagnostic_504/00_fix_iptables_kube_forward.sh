#!/usr/bin/env bash
# Script pour corriger les règles iptables KUBE-FORWARD

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Correction iptables KUBE-FORWARD"
echo "=============================================================="
echo ""

# Liste des nœuds K3s
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
    echo "Correction $node ($ip)..."
    
    # Vérifier et corriger les règles iptables
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" bash <<'EOF'
set +u

echo "  → Vérification règles FORWARD..."

# Vérifier si les règles pour 10.42/10.43 sont en premier
FIRST_RULE=$(iptables -L FORWARD -n --line-numbers | head -10 | grep -E "10.42|10.43" | head -1 | awk '{print $1}')

if [[ -z "$FIRST_RULE" ]]; then
    echo "  → Ajout des règles FORWARD pour K3s..."
    
    # Ajouter les règles en premier (avant KUBE-FORWARD)
    iptables -I FORWARD 1 -s 10.42.0.0/16 -d 10.42.0.0/16 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD 2 -s 10.43.0.0/16 -d 10.43.0.0/16 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD 3 -s 10.42.0.0/16 -d 10.43.0.0/16 -j ACCEPT 2>/dev/null || true
    iptables -I FORWARD 4 -s 10.43.0.0/16 -d 10.42.0.0/16 -j ACCEPT 2>/dev/null || true
    
    echo "  ✓ Règles FORWARD ajoutées"
else
    echo "  ℹ️  Règles FORWARD déjà présentes"
fi

# Vérifier KUBE-FORWARD
echo "  → Vérification KUBE-FORWARD..."
KUBE_FORWARD_RULES=$(iptables -L KUBE-FORWARD -n | wc -l)

if [[ $KUBE_FORWARD_RULES -lt 5 ]]; then
    echo "  ⚠️  KUBE-FORWARD semble incomplet"
else
    echo "  ✓ KUBE-FORWARD configuré ($KUBE_FORWARD_RULES règles)"
fi

# Afficher les premières règles FORWARD
echo "  → Règles FORWARD (premières 10):"
iptables -L FORWARD -n --line-numbers | head -12
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
    echo "✅ Règles iptables corrigées"
    echo ""
    echo "Testez maintenant :"
    echo "  kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s http://10.43.38.57/"
fi

echo ""
echo "=============================================================="

