#!/usr/bin/env bash
# Script à exécuter depuis install-01 pour tester depuis les workers

set +e

echo "=============================================================="
echo " [KeyBuzz] Test Connectivité depuis Workers"
echo "=============================================================="
echo ""

# Se connecter sur master-01 pour récupérer les infos
MASTER_IP="10.0.0.100"

echo "Récupération des informations depuis master-01..."
POD_INFO=$(ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].status.podIP}' 2>/dev/null" || echo "")
SVC_IP=$(ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null" || echo "")

echo "Pod IP: $POD_INFO"
echo "Service IP: $SVC_IP"
echo ""

# Liste des workers
declare -a WORKERS=(
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-03|10.0.0.112"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

# Test depuis chaque worker
for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip <<< "$worker_info"
    echo "=========================================="
    echo "Test depuis $name ($ip)..."
    echo "=========================================="
    
    # Test vers Pod IP
    if [[ -n "$POD_INFO" ]]; then
        echo "1. Test vers Pod KeyBuzz ($POD_INFO:80):"
        ssh -o StrictHostKeyChecking=no root@"$ip" "timeout 5 nc -zv $POD_INFO 80 2>&1" || echo "   ❌ Non accessible"
        echo ""
        
        echo "2. Test HTTP vers Pod KeyBuzz ($POD_INFO:80):"
        RESULT=$(ssh -o StrictHostKeyChecking=no root@"$ip" "timeout 5 curl -s http://$POD_INFO/ 2>&1" | head -1 || echo "FAIL")
        if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
            echo "   ✅ Pod répond: $(echo "$RESULT" | head -1 | cut -c1-50)..."
        else
            echo "   ❌ Pod ne répond pas: $RESULT"
        fi
        echo ""
    fi
    
    # Test vers Service IP
    if [[ -n "$SVC_IP" ]]; then
        echo "3. Test vers Service KeyBuzz ($SVC_IP:80):"
        ssh -o StrictHostKeyChecking=no root@"$ip" "timeout 5 nc -zv $SVC_IP 80 2>&1" || echo "   ❌ Non accessible"
        echo ""
    fi
    
    echo ""
done

echo "=============================================================="
echo " Test depuis Master-01"
echo "=============================================================="
echo ""

# Test depuis master-01
if [[ -n "$POD_INFO" ]]; then
    echo "Test depuis master-01 vers Pod ($POD_INFO:80):"
    ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "timeout 5 nc -zv $POD_INFO 80 2>&1" || echo "   ❌ Non accessible"
    echo ""
    
    echo "Test HTTP depuis master-01 vers Pod ($POD_INFO:80):"
    RESULT=$(ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "timeout 5 curl -s http://$POD_INFO/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "   ✅ Pod répond: $(echo "$RESULT" | head -1 | cut -c1-50)..."
    else
        echo "   ❌ Pod ne répond pas: $RESULT"
    fi
    echo ""
fi

echo "=============================================================="
echo " ✅ Tests terminés"
echo "=============================================================="

