#!/bin/bash
set -e

echo "=== FORCE RESTART ET VÉRIFICATION ==="
echo ""

echo "1. Suppression des pods Ingress:"
kubectl delete pods -n ingress-nginx -l app=ingress-nginx
echo ""

echo "2. Attente 30 secondes pour le redémarrage..."
sleep 30

echo ""
echo "3. Vérification pods:"
kubectl get pods -n ingress-nginx -l app=ingress-nginx | head -5
echo ""

echo "4. Vérification logs (erreurs RBAC?):"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
  echo "Pod: $INGRESS_POD"
  kubectl logs -n ingress-nginx $INGRESS_POD --tail=5 | grep -i "error\|forbidden" || echo "✅ Pas d'erreurs récentes"
  echo ""
  
  echo "5. Vérification config NGINX (platform.keybuzz.io):"
  kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
  echo ""
  
  echo "6. Test depuis le pod (simulation requête):"
  kubectl exec -n ingress-nginx $INGRESS_POD -- sh -c 'echo "GET / HTTP/1.1
Host: platform.keybuzz.io
Connection: close

" | nc localhost 80 | head -15' || echo "Erreur test"
fi

echo ""
echo "✅ Terminé"

