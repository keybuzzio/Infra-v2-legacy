#!/bin/bash
set -e

echo "=== REDÉMARRAGE INGRESS CONTROLLER ==="
echo ""

# Trouver le namespace
NS=$(kubectl get daemonset nginx-ingress-controller --all-namespaces -o jsonpath='{.items[0].metadata.namespace}' 2>/dev/null || echo "kube-system")

echo "Namespace trouvé: $NS"
echo ""

echo "1. Redémarrage DaemonSet:"
kubectl rollout restart daemonset -n $NS nginx-ingress-controller

echo ""
echo "2. Attente 20 secondes..."
sleep 20

echo ""
echo "3. Vérification pods:"
kubectl get pods -n $NS -l app=ingress-nginx
echo ""

echo "4. Vérification config NGINX:"
INGRESS_POD=$(kubectl get pod -n $NS -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
  echo "Pod: $INGRESS_POD"
  echo "Recherche platform.keybuzz.io:"
  kubectl exec -n $NS $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
  echo ""
  echo "Recherche platform-api.keybuzz.io:"
  kubectl exec -n $NS $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform-api.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
else
  echo "❌ Aucun pod Ingress trouvé"
fi

echo ""
echo "✅ Redémarrage terminé"

