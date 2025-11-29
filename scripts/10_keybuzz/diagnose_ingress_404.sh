#!/bin/bash
set -e

echo "=========================================="
echo "  DIAGNOSTIC COMPLET - 404 Ingress"
echo "=========================================="
echo ""

echo "=== 1. VÉRIFICATION INGRESS ==="
kubectl get ingress -n keybuzz -o yaml | grep -A 50 "name: keybuzz-front-ingress" | head -60
echo ""

echo "=== 2. VÉRIFICATION SERVICES ==="
kubectl get svc -n keybuzz -o yaml | grep -A 20 "name: keybuzz-front"
echo ""

echo "=== 3. VÉRIFICATION ENDPOINTS ==="
kubectl get endpoints -n keybuzz
echo ""

echo "=== 4. TEST DIRECT POD FRONT ==="
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $POD_FRONT"
kubectl exec -n keybuzz $POD_FRONT -- wget -qO- http://localhost:80 2>/dev/null | head -c 100 && echo " ✅" || echo " ❌"
echo ""

echo "=== 5. TEST SERVICE FRONT (depuis pod dans cluster) ==="
kubectl run test-svc-$$ --image=curlimages/curl:latest --restart=Never -n keybuzz -- sleep 3600
sleep 3
echo "Test avec Host header:"
kubectl exec -n keybuzz test-svc-$$ -- curl -s -v -H "Host: platform.keybuzz.io" http://keybuzz-front.keybuzz.svc.cluster.local:80 2>&1 | head -30
echo ""
echo "Test sans Host header:"
kubectl exec -n keybuzz test-svc-$$ -- curl -s -v http://keybuzz-front.keybuzz.svc.cluster.local:80 2>&1 | head -30
echo ""

echo "=== 6. TEST INGRESS CONTROLLER DIRECT ==="
INGRESS_SVC=$(kubectl get svc -n ingress-nginx -o jsonpath='{.items[?(@.metadata.name=="ingress-nginx-controller")].metadata.name}')
if [ -n "$INGRESS_SVC" ]; then
  echo "Service Ingress: $INGRESS_SVC"
  kubectl exec -n keybuzz test-svc-$$ -- curl -s -v -H "Host: platform.keybuzz.io" http://${INGRESS_SVC}.ingress-nginx.svc.cluster.local:80/ 2>&1 | head -40
else
  echo "Service Ingress non trouvé, test via DaemonSet..."
  # Tester via un pod Ingress directement
  INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
  echo "Pod Ingress: $INGRESS_POD"
  kubectl exec -n ingress-nginx $INGRESS_POD -- curl -s -v -H "Host: platform.keybuzz.io" http://localhost:80/ 2>&1 | head -40
fi
echo ""

echo "=== 7. CONFIGURATION INGRESS NGINX ==="
kubectl get configmap -n ingress-nginx 2>/dev/null | grep -i ingress || echo "Pas de ConfigMap trouvé"
echo ""

echo "=== 8. LOGS INGRESS (dernières 50 lignes avec platform) ==="
kubectl logs -n ingress-nginx -l app=ingress-nginx --tail=100 | grep -i "platform\|404\|keybuzz" | tail -20 || echo "Pas de logs récents"
echo ""

echo "=== 9. TEST DEPUIS NODE K3S (simulation LB) ==="
# Tester depuis un node K3s directement sur le NodePort
NODE_IP=$(kubectl get node -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "Node IP: $NODE_IP"
echo "Test HTTP sur NodePort 31695:"
kubectl run test-nodeport-$$ --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -v -H "Host: platform.keybuzz.io" http://${NODE_IP}:31695/ 2>&1 | head -40
echo ""

echo "=== 10. VÉRIFICATION ROUTING INGRESS ==="
# Vérifier la configuration NGINX générée par l'Ingress
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
echo "Pod Ingress: $INGRESS_POD"
echo "Recherche de platform.keybuzz.io dans la config NGINX:"
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" || echo "❌ platform.keybuzz.io non trouvé dans la config NGINX"
echo ""

echo "=== 11. NETTOYAGE ==="
kubectl delete pod test-svc-$$ -n keybuzz 2>/dev/null || true

echo ""
echo "=========================================="
echo "  FIN DU DIAGNOSTIC"
echo "=========================================="

