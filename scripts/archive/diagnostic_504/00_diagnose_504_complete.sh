#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Complet Erreurs 504"
echo "=============================================================="
echo ""

# Test 1: Pods KeyBuzz
echo "1. État des Pods KeyBuzz:"
kubectl get pods -n keybuzz
echo ""

# Test 2: Services et Endpoints
echo "2. Services et Endpoints:"
kubectl get svc -n keybuzz
echo ""
kubectl get endpoints -n keybuzz
echo ""

# Test 3: Test depuis pod KeyBuzz API
echo "3. Test depuis pod KeyBuzz API (localhost):"
POD=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$POD" ]]; then
    echo "   Pod: $POD"
    kubectl exec -n keybuzz "$POD" -- wget -qO- http://127.0.0.1/ 2>&1 | head -3 || echo "   ❌ Échec"
    echo ""
    
    echo "4. Test connectivité réseau depuis pod:"
    echo "   PostgreSQL (10.0.0.10:5432):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'timeout 3 nc -zv 10.0.0.10 5432 2>&1' || echo "   ❌ Non accessible"
    echo ""
    echo "   PgBouncer (10.0.0.10:4632):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'timeout 3 nc -zv 10.0.0.10 4632 2>&1' || echo "   ❌ Non accessible"
    echo ""
    echo "   Redis (10.0.0.10:6379):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'timeout 3 nc -zv 10.0.0.10 6379 2>&1' || echo "   ❌ Non accessible"
    echo ""
fi

# Test 5: Test Service depuis pod
echo "5. Test Service KeyBuzz API depuis pod:"
if [[ -n "$POD" ]]; then
    kubectl exec -n keybuzz "$POD" -- wget -qO- http://keybuzz-api.keybuzz.svc.cluster.local/ 2>&1 | head -3 || echo "   ❌ Échec"
    echo ""
fi

# Test 6: Ingress Controller
echo "6. Test Ingress Controller:"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}')
if [[ -n "$INGRESS_POD" ]]; then
    echo "   Ingress Pod: $INGRESS_POD"
    echo "   Test vers Service KeyBuzz API:"
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- wget -qO- -T 5 --header='Host: platform-api.keybuzz.io' http://keybuzz-api.keybuzz.svc.cluster.local/ 2>&1 | head -3 || echo "   ❌ Échec"
    echo ""
    echo "   Test localhost (simulation LB):"
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- wget -qO- -T 5 --header='Host: platform.keybuzz.io' http://localhost/ 2>&1 | head -3 || echo "   ❌ Échec"
    echo ""
    
    echo "7. Configuration NGINX (platform.keybuzz.io):"
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -B 5 -A 15 'platform.keybuzz.io' | head -25
    echo ""
    
    echo "8. Logs Ingress Controller (dernières lignes):"
    kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=30 2>&1 | tail -20
    echo ""
fi

# Test 9: NodePort
echo "9. Test NodePort Ingress:"
INGRESS_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' || echo "31695")
echo "   NodePort: $INGRESS_NODEPORT"
kubectl run -it --rm test-ingress-final --image=curlimages/curl --restart=Never -- curl -s -H 'Host: platform.keybuzz.io' "http://10.0.0.100:${INGRESS_NODEPORT}/" 2>&1 | head -5
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

