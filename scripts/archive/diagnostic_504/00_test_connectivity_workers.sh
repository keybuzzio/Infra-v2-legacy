#!/usr/bin/env bash
# Script à exécuter depuis install-01 pour tester la connectivité depuis les workers

set +e

echo "=============================================================="
echo " [KeyBuzz] Test Connectivité depuis Workers"
echo "=============================================================="
echo ""

# Liste des workers avec leurs IPs PRIVÉES
declare -a WORKERS=(
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-03|10.0.0.112"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

# Récupérer les IPs des pods KeyBuzz
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
POD_IPS=$(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].status.podIP}' 2>/dev/null || echo "")

echo "Service IP: $SVC_IP"
echo "Pod IPs: $POD_IPS"
echo ""

# Test depuis chaque worker
for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip <<< "$worker_info"
    echo "=========================================="
    echo "Test depuis $name ($ip)..."
    echo "=========================================="
    
    # Test DNS
    echo "1. Test DNS (google.com):"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "nslookup google.com 2>&1 | head -3" || echo "   ❌ DNS échoué"
    echo ""
    
    # Test connectivité Internet
    echo "2. Test connectivité Internet (curl google.com):"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "timeout 5 curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://google.com 2>&1" || echo "   ❌ Internet non accessible"
    echo ""
    
    # Test vers Service IP
    if [[ -n "$SVC_IP" ]]; then
        echo "3. Test vers Service KeyBuzz ($SVC_IP:80):"
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "timeout 5 nc -zv $SVC_IP 80 2>&1" || echo "   ❌ Service non accessible"
        echo ""
    fi
    
    # Test vers Pod IPs
    if [[ -n "$POD_IPS" ]]; then
        for pod_ip in $POD_IPS; do
            echo "4. Test vers Pod KeyBuzz ($pod_ip:80):"
            ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "timeout 5 nc -zv $pod_ip 80 2>&1" || echo "   ❌ Pod $pod_ip non accessible"
            echo ""
        done
    fi
    
    echo ""
done

echo "=============================================================="
echo " Test depuis Pods KeyBuzz"
echo "=============================================================="
echo ""

# Test depuis les pods KeyBuzz
PODS=$(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [[ -n "$PODS" ]]; then
    for pod in $PODS; do
        echo "Test depuis pod $pod:"
        echo "1. DNS (google.com):"
        kubectl exec -n keybuzz "$pod" -- nslookup google.com 2>&1 | head -3 || echo "   ❌ DNS échoué"
        echo ""
        echo "2. Internet (curl google.com):"
        kubectl exec -n keybuzz "$pod" -- sh -c "timeout 5 curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://google.com 2>&1" || echo "   ❌ Internet non accessible"
        echo ""
        echo "3. Service KeyBuzz ($SVC_IP:80):"
        kubectl exec -n keybuzz "$pod" -- sh -c "timeout 5 wget -qO- http://$SVC_IP/ 2>&1 | head -1" || echo "   ❌ Service non accessible"
        echo ""
    done
else
    echo "Aucun pod KeyBuzz trouvé"
fi

echo "=============================================================="
echo " ✅ Tests terminés"
echo "=============================================================="

