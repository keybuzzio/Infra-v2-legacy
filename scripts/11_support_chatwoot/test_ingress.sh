#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== TEST INGRESS CHATWOOT ==="
echo ""

# Récupérer un pod Ingress NGINX
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers | head -1 | awk '{print $1}')
echo "Pod Ingress NGINX: $INGRESS_POD"
echo ""

# Vérifier la config NGINX
echo "=== Vérification config NGINX ==="
if kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>/dev/null | grep -q "support.keybuzz"; then
    echo "✅ support.keybuzz trouvé dans nginx.conf"
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>/dev/null | grep -A 10 "support.keybuzz" | head -15
else
    echo "❌ support.keybuzz NON trouvé dans nginx.conf"
    echo "Vérification des logs..."
    kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=20 2>&1 | grep -i "chatwoot\|support\|error" | tail -10
fi

echo ""
echo "=== Test connectivité directe ==="
POD_IP=$(kubectl get pod -n chatwoot chatwoot-web-5ccff59bc4-h6rdk -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")
if [ -n "$POD_IP" ]; then
    echo "IP Pod Chatwoot: $POD_IP"
    echo "Test depuis pod Ingress..."
    kubectl exec -n ingress-nginx "$INGRESS_POD" -- curl -sS -o /dev/null -w "%{http_code}\n" "http://${POD_IP}:3000" 2>&1 || echo "Échec"
else
    echo "Impossible de récupérer l'IP du pod"
fi

echo ""
echo "=== État Ingress ==="
kubectl get ingress -n chatwoot chatwoot-ingress -o yaml | grep -A 5 "status:" || echo "Pas de status"

