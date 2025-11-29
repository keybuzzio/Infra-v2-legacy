#!/bin/bash
set -e

echo "=== VÉRIFICATION CONFIGURATION INGRESS CONTROLLER ==="
echo ""

echo "1. IngressClass:"
kubectl get ingressclass nginx -o yaml
echo ""

echo "2. DaemonSet args (recherche ingress-class):"
kubectl get daemonset -n ingress-nginx nginx-ingress-controller -o yaml | grep -A 20 "args:" | grep -i "ingress-class\|watch-ingress" | head -10
echo ""

echo "3. Tous les args du DaemonSet:"
kubectl get daemonset -n ingress-nginx nginx-ingress-controller -o jsonpath='{.spec.template.spec.containers[0].args[*]}' | tr ' ' '\n' | grep -E "ingress-class|watch" || echo "Pas d'arg ingress-class trouvé"
echo ""

echo "4. Vérification Ingress:"
kubectl get ingress -n keybuzz -o yaml | grep -E "ingressClassName|name:" | head -10
echo ""

echo "=== SOLUTION: Ajouter --ingress-class=nginx au DaemonSet ==="
echo ""

# Patch du DaemonSet pour ajouter l'arg --ingress-class=nginx
kubectl patch daemonset -n ingress-nginx nginx-ingress-controller --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--ingress-class=nginx"
  }
]' 2>/dev/null || echo "L'arg existe peut-être déjà"

echo ""
echo "5. Redémarrage après patch:"
kubectl rollout restart daemonset -n ingress-nginx nginx-ingress-controller
echo "Attente 20 secondes..."
sleep 20

echo ""
echo "6. Vérification config NGINX:"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
  echo "Pod: $INGRESS_POD"
  echo "Recherche platform.keybuzz.io:"
  kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
fi

echo ""
echo "✅ Terminé"

