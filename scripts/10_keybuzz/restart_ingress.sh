#!/bin/bash
set -e

echo "=== REDÉMARRAGE INGRESS CONTROLLER ==="
echo ""

echo "1. Recherche du DaemonSet/Deployment:"
kubectl get daemonset -n ingress-nginx
kubectl get deployment -n ingress-nginx
echo ""

echo "2. Redémarrage:"
DS_NAME=$(kubectl get daemonset -n ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
DEP_NAME=$(kubectl get deployment -n ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$DS_NAME" ]; then
  echo "Redémarrage DaemonSet: $DS_NAME"
  kubectl rollout restart daemonset -n ingress-nginx $DS_NAME
elif [ -n "$DEP_NAME" ]; then
  echo "Redémarrage Deployment: $DEP_NAME"
  kubectl rollout restart deployment -n ingress-nginx $DEP_NAME
else
  echo "❌ Aucun DaemonSet ou Deployment trouvé"
  exit 1
fi

echo ""
echo "3. Attente 20 secondes..."
sleep 20

echo ""
echo "4. Vérification pods:"
kubectl get pods -n ingress-nginx
echo ""

echo "5. Vérification config NGINX:"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
  echo "Pod: $INGRESS_POD"
  echo "Recherche platform.keybuzz.io:"
  kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
else
  echo "❌ Aucun pod Ingress trouvé"
fi

echo ""
echo "✅ Redémarrage terminé"

