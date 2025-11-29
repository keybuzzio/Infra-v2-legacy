#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Interne 504"
echo "=============================================================="
echo ""

INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}')
POD_IP=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}' | xargs kubectl get pod -n keybuzz -o jsonpath='{.status.podIP}')

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test 1: Résolution DNS depuis Ingress
echo "1. Test résolution DNS depuis Ingress Controller:"
echo "   Test keybuzz-front.keybuzz.svc.cluster.local:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 nslookup keybuzz-front.keybuzz.svc.cluster.local 2>&1" | head -10 || echo "   ❌ Timeout DNS"
echo ""

# Test 2: Test avec IP directe du Service
echo "2. Test avec IP directe du Service (10 tentatives):"
SUCCESS=0
FAIL=0
for i in $(seq 1 10); do
    START=$(date +%s)
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    END=$(date +%s)
    DURATION=$((END - START))
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK (${DURATION}s)"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "  Tentative $i: ❌ ÉCHEC (${DURATION}s)"
        FAIL=$((FAIL + 1))
    fi
    sleep 1
done
echo "  Résultat: $SUCCESS succès, $FAIL échecs"
echo ""

# Test 3: Test avec IP directe du Pod
echo "3. Test avec IP directe du Pod (10 tentatives):"
SUCCESS2=0
FAIL2=0
for i in $(seq 1 10); do
    START=$(date +%s)
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$POD_IP/ 2>&1" | head -1 || echo "FAIL")
    END=$(date +%s)
    DURATION=$((END - START))
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK (${DURATION}s)"
        SUCCESS2=$((SUCCESS2 + 1))
    else
        echo "  Tentative $i: ❌ ÉCHEC (${DURATION}s)"
        FAIL2=$((FAIL2 + 1))
    fi
    sleep 1
done
echo "  Résultat: $SUCCESS2 succès, $FAIL2 échecs"
echo ""

# Test 4: Logs Ingress Controller (erreurs récentes)
echo "4. Logs Ingress Controller (dernières erreurs):"
kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=50 2>&1 | grep -i -E '504|502|503|timeout|upstream|connect|error|failed|keybuzz' | tail -20
echo ""

# Test 5: Configuration NGINX upstream
echo "5. Configuration NGINX upstream pour keybuzz-front:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -B 5 -A 15 "upstream.*keybuzz-front" | head -25
echo ""

# Test 6: Test de connectivité réseau
echo "6. Test connectivité réseau:"
echo "   Ingress -> Service IP ($SVC_IP:80):"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 nc -zv $SVC_IP 80 2>&1" || echo "   ❌ Non accessible"
echo ""
echo "   Ingress -> Pod IP ($POD_IP:80):"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 nc -zv $POD_IP 80 2>&1" || echo "   ❌ Non accessible"
echo ""

# Test 7: Vérifier CoreDNS
echo "7. État CoreDNS:"
kubectl get pods -n kube-system | grep coredns
echo ""

# Test 8: Test DNS depuis un pod KeyBuzz
echo "8. Test DNS depuis un pod KeyBuzz:"
POD=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}')
kubectl exec -n keybuzz "$POD" -- sh -c "nslookup keybuzz-front.keybuzz.svc.cluster.local 2>&1" | head -10 || echo "   ❌ Timeout DNS"
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

