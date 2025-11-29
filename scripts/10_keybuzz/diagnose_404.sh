#!/bin/bash
set -e

echo "=========================================="
echo "  DIAGNOSTIC 404 - KeyBuzz Platform"
echo "=========================================="
echo ""

echo "=== 1. VÉRIFICATION INGRESS ==="
kubectl get ingress -n keybuzz -o yaml | grep -A 30 "name: keybuzz-front-ingress" | head -35
echo ""
kubectl get ingress -n keybuzz -o yaml | grep -A 30 "name: keybuzz-api-ingress" | head -35
echo ""

echo "=== 2. VÉRIFICATION SERVICES ==="
kubectl get svc -n keybuzz
echo ""

echo "=== 3. VÉRIFICATION ENDPOINTS ==="
kubectl get endpoints -n keybuzz
echo ""

echo "=== 4. VÉRIFICATION PODS ==="
kubectl get pods -n keybuzz -o wide
echo ""

echo "=== 5. TEST SERVICE FRONT (direct) ==="
kubectl run test-front-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform.keybuzz.io" http://keybuzz-front.keybuzz.svc.cluster.local:80 | head -10 || echo "ERREUR"
echo ""

echo "=== 6. TEST SERVICE API (direct) ==="
kubectl run test-api-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform-api.keybuzz.io" http://keybuzz-api.keybuzz.svc.cluster.local:80 | head -10 || echo "ERREUR"
echo ""

echo "=== 7. TEST POD FRONT (direct) ==="
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_FRONT"
kubectl exec -n keybuzz $POD_FRONT -- curl -s http://localhost:80 | head -10 || echo "ERREUR"
echo ""

echo "=== 8. TEST POD API (direct) ==="
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_API"
kubectl exec -n keybuzz $POD_API -- curl -s http://localhost:8080 | head -10 || echo "ERREUR"
echo ""

echo "=== 9. VÉRIFICATION NGINX CONFIG (API) ==="
kubectl exec -n keybuzz $POD_API -- cat /etc/nginx/nginx.conf | head -20
echo ""

echo "=== 10. TEST INGRESS CONTROLLER ==="
kubectl run test-ingress-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform.keybuzz.io" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local:80/ | head -10 || echo "ERREUR"
echo ""

echo "=== 11. LOGS INGRESS (dernières 30 lignes) ==="
kubectl logs -n ingress-nginx -l app=ingress-nginx --tail=30 | tail -20
echo ""

echo "=== 12. VÉRIFICATION INGRESS NGINX CONFIG ==="
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml | grep -A 5 "use-forwarded-headers\|compute-full-forwarded-for" || echo "Config par défaut"
echo ""

echo "=========================================="
echo "  FIN DU DIAGNOSTIC"
echo "=========================================="

