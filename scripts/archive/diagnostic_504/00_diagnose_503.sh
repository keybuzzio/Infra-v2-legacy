#!/usr/bin/env bash
# Diagnostic du problème 503

set -euo pipefail

MASTER_IP="10.0.0.100"

echo "=== Diagnostic 503 KeyBuzz ==="
echo ""

echo "1. Test direct des pods (hostNetwork):"
echo "----------------------------------------"
for worker in 10.0.0.110 10.0.0.111 10.0.0.112; do
    echo -n "  API sur $worker:8080 ... "
    HTTP_CODE=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" http://$worker:8080 2>/dev/null || echo "TIMEOUT")
    echo "$HTTP_CODE"
    
    echo -n "  Front sur $worker:3000 ... "
    HTTP_CODE=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" http://$worker:3000 2>/dev/null || echo "TIMEOUT")
    echo "$HTTP_CODE"
done
echo ""

echo "2. Test des Services NodePort:"
echo "----------------------------------------"
echo -n "  API NodePort 30080 ... "
HTTP_CODE=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" http://10.0.0.110:30080 2>/dev/null || echo "TIMEOUT")
echo "$HTTP_CODE"

echo -n "  Front NodePort 30000 ... "
HTTP_CODE=$(timeout 3 curl -s -o /dev/null -w "%{http_code}" http://10.0.0.110:30000 2>/dev/null || echo "TIMEOUT")
echo "$HTTP_CODE"
echo ""

echo "3. Test via Ingress NGINX (NodePort 31695):"
echo "----------------------------------------"
echo -n "  platform.keybuzz.io ... "
HTTP_CODE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" -H "Host: platform.keybuzz.io" http://10.0.0.110:31695 2>/dev/null || echo "TIMEOUT")
echo "$HTTP_CODE"

echo -n "  platform-api.keybuzz.io ... "
HTTP_CODE=$(timeout 5 curl -s -o /dev/null -w "%{http_code}" -H "Host: platform-api.keybuzz.io" http://10.0.0.110:31695 2>/dev/null || echo "TIMEOUT")
echo "$HTTP_CODE"
echo ""

echo "4. Endpoints des Services:"
echo "----------------------------------------"
kubectl get endpoints -n keybuzz
echo ""

echo "5. Logs Ingress NGINX (dernières erreurs):"
echo "----------------------------------------"
kubectl logs -n ingress-nginx -l app=ingress-nginx --tail=30 2>&1 | grep -i "keybuzz\|503\|upstream\|connect" | tail -10 || echo "Aucune erreur récente"
echo ""

echo "=== Fin Diagnostic ==="

