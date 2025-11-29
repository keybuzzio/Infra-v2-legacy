#!/usr/bin/env bash
# Script pour corriger les Services ClusterIP dans K3s

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Correction Services ClusterIP K3s"
echo "=============================================================="
echo ""

# Liste des nœuds K3s avec leurs IPs privées
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

# 1. Vérifier kube-proxy sur tous les nœuds
echo "1. Vérification kube-proxy:"
echo "=============================================================="
for node in "${!K3S_NODES[@]}"; do
    ip="${K3S_NODES[$node]}"
    echo -n "$node ($ip): "
    
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "crictl ps 2>/dev/null | grep -q kube-proxy" 2>/dev/null; then
        echo "✅ kube-proxy présent"
    else
        echo "❌ kube-proxy absent"
    fi
done
echo ""

# 2. Vérifier les règles iptables NAT sur master-01
echo "2. Vérification règles iptables NAT (master-01):"
echo "=============================================================="
MASTER01_IP="10.0.0.100"
SVC_IP="10.43.38.57"

echo "Règles KUBE-SERVICES pour $SVC_IP:"
ssh -o StrictHostKeyChecking=no root@"$MASTER01_IP" "iptables -t nat -L KUBE-SERVICES -n | grep $SVC_IP | head -5" || echo "Aucune règle trouvée"
echo ""

# 3. Redémarrer kube-proxy sur tous les nœuds
echo "3. Redémarrage kube-proxy sur tous les nœuds:"
echo "=============================================================="
for node in "${!K3S_NODES[@]}"; do
    ip="${K3S_NODES[$node]}"
    echo "Redémarrage kube-proxy sur $node ($ip)..."
    
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" bash <<'EOF'
set +u

# Trouver le conteneur kube-proxy
KUBE_PROXY_ID=$(crictl ps 2>/dev/null | grep kube-proxy | awk '{print $1}' | head -1)

if [[ -n "$KUBE_PROXY_ID" ]]; then
    echo "  → Arrêt de kube-proxy (ID: $KUBE_PROXY_ID)"
    crictl stop "$KUBE_PROXY_ID" 2>/dev/null || true
    sleep 3
    echo "  ✓ kube-proxy redémarré (K3s le relancera automatiquement)"
else
    echo "  ℹ️  kube-proxy non trouvé (peut-être intégré dans k3s)"
    # Redémarrer k3s pour forcer la reconfiguration
    if systemctl is-active --quiet k3s 2>/dev/null || systemctl is-active --quiet k3s-agent 2>/dev/null; then
        echo "  → Redémarrage K3s pour forcer la reconfiguration réseau"
        systemctl restart k3s 2>/dev/null || systemctl restart k3s-agent 2>/dev/null || true
        sleep 5
        echo "  ✓ K3s redémarré"
    fi
fi
EOF
    then
        echo "  ✅ $node traité"
        ((SUCCESS++))
    else
        echo "  ❌ $node : échec"
        ((FAIL++))
    fi
    
    echo ""
done

# 4. Attendre que kube-proxy se relance
echo "4. Attente que kube-proxy se relance (10 secondes)..."
sleep 10
echo ""

# 5. Vérifier les règles iptables après redémarrage
echo "5. Vérification règles iptables après redémarrage:"
echo "=============================================================="
echo "Règles KUBE-SERVICES pour $SVC_IP:"
ssh -o StrictHostKeyChecking=no root@"$MASTER01_IP" "iptables -t nat -L KUBE-SERVICES -n | grep $SVC_IP | head -5" || echo "Aucune règle trouvée"
echo ""

# 6. Test final
echo "6. Test final - Service ClusterIP:"
echo "=============================================================="
echo "Test depuis un pod vers le Service ($SVC_IP:80)..."
kubectl run test-curl-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -- sh <<EOF
timeout 10 curl -s http://$SVC_IP/ | head -3 || echo "❌ ÉCHEC"
EOF
echo ""

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Nœuds traités : $SUCCESS / ${#K3S_NODES[@]}"
if [[ $FAIL -gt 0 ]]; then
    echo "❌ Nœuds en échec : $FAIL / ${#K3S_NODES[@]}"
fi
echo ""
echo "Si le problème persiste, vérifiez :"
echo "  1. Les logs kube-proxy : kubectl logs -n kube-system -l k8s-app=kube-proxy"
echo "  2. La configuration K3s : /etc/rancher/k3s/config.yaml"
echo "  3. Les règles iptables : iptables -t nat -L KUBE-SERVICES -n"
echo ""
echo "=============================================================="

