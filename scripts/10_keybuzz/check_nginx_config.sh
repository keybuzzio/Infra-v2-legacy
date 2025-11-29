#!/bin/bash
set -e

echo "=== VÉRIFICATION CONFIG NGINX ==="
echo ""

INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$INGRESS_POD" ]; then
  echo "❌ Aucun pod Ingress trouvé"
  exit 1
fi

echo "Pod: $INGRESS_POD"
echo ""

echo "1. Server blocks dans nginx.conf:"
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 15 "server {" | head -60
echo ""

echo "2. Recherche de 'keybuzz' dans la config:"
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -i keybuzz || echo "❌ Aucune mention de keybuzz"
echo ""

echo "3. Logs Ingress (dernières 30 lignes):"
kubectl logs -n ingress-nginx $INGRESS_POD --tail=30 | tail -20
echo ""

echo "4. Vérification que l'Ingress controller voit les Ingress:"
kubectl get ingress --all-namespaces | grep keybuzz
echo ""

echo "✅ Terminé"

