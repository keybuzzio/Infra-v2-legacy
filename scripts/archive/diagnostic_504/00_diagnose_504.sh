#!/usr/bin/env bash
#
# 00_diagnose_504.sh - Diagnostic des erreurs 504
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Erreurs 504"
echo "=============================================================="
echo ""

# Test 1: Service KeyBuzz API depuis pod
echo "1. Test Service KeyBuzz API depuis pod..."
POD=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$POD" ]]; then
    echo "   Pod: $POD"
    kubectl exec -n keybuzz "$POD" -- curl -s http://keybuzz-api.keybuzz.svc.cluster.local/ 2>&1 | head -5
    echo ""
else
    echo "   ⚠️  Aucun pod KeyBuzz API trouvé"
    echo ""
fi

# Test 2: Ingress Controller vers Service
echo "2. Test Ingress Controller vers Service KeyBuzz API..."
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -n "$INGRESS_POD" ]]; then
    echo "   Ingress Pod: $INGRESS_POD"
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- curl -s -H 'Host: platform-api.keybuzz.io' http://keybuzz-api.keybuzz.svc.cluster.local/ 2>&1 | head -5
    echo ""
else
    echo "   ⚠️  Aucun pod Ingress Controller trouvé"
    echo ""
fi

# Test 3: Ingress Controller localhost
echo "3. Test Ingress Controller localhost (simulation LB)..."
if [[ -n "$INGRESS_POD" ]]; then
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- curl -s -H 'Host: platform.keybuzz.io' http://localhost/ 2>&1 | head -5
    echo ""
fi

# Test 4: Connectivité réseau depuis pod
echo "4. Test connectivité réseau depuis pod KeyBuzz..."
if [[ -n "$POD" ]]; then
    echo "   PostgreSQL (10.0.0.10:5432):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'nc -zv 10.0.0.10 5432 2>&1 || echo "  ❌ Non accessible"'
    echo ""
    echo "   PgBouncer (10.0.0.10:4632):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'nc -zv 10.0.0.10 4632 2>&1 || echo "  ❌ Non accessible"'
    echo ""
    echo "   Redis (10.0.0.10:6379):"
    kubectl exec -n keybuzz "$POD" -- sh -c 'nc -zv 10.0.0.10 6379 2>&1 || echo "  ❌ Non accessible"'
    echo ""
fi

# Test 5: Configuration NGINX
echo "5. Configuration NGINX dans Ingress Controller..."
if [[ -n "$INGRESS_POD" ]]; then
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf | grep -A 15 'platform.keybuzz.io' | head -20
    echo ""
fi

# Test 6: Logs Ingress Controller
echo "6. Logs Ingress Controller (dernières erreurs)..."
if [[ -n "$INGRESS_POD" ]]; then
    kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=30 2>&1 | grep -i -E 'platform|keybuzz|504|502|503|error|timeout|upstream' | head -15
    echo ""
fi

# Test 7: NodePort
echo "7. Test NodePort Ingress..."
INGRESS_NODEPORT=$(kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "31695")
echo "   NodePort: $INGRESS_NODEPORT"
kubectl run -it --rm test-ingress-nodeport --image=curlimages/curl --restart=Never -- curl -s -H 'Host: platform.keybuzz.io' "http://10.0.0.100:${INGRESS_NODEPORT}/" 2>&1 | head -10
echo ""

# Test 8: Endpoints
echo "8. Vérification Endpoints..."
kubectl get endpoints -n keybuzz
echo ""

# Test 9: Services
echo "9. Vérification Services..."
kubectl get svc -n keybuzz
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

