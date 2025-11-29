#!/bin/bash
set -e

echo "=== CORRECTION RBAC POUR INGRESS NGINX ==="
echo ""

echo "1. Patch du ClusterRole pour ajouter les permissions manquantes:"
kubectl patch clusterrole ingress-nginx --type=json -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": ["discovery.k8s.io"],
      "resources": ["endpointslices"],
      "verbs": ["get", "list", "watch"]
    }
  },
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": ["coordination.k8s.io"],
      "resources": ["leases"],
      "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]
    }
  }
]'

echo ""
echo "2. Vérification du ClusterRole:"
kubectl get clusterrole ingress-nginx -o yaml | grep -A 5 -E "endpointslices|leases" | head -15
echo ""

echo "3. Redémarrage Ingress Controller:"
kubectl rollout restart daemonset -n ingress-nginx nginx-ingress-controller
echo "Attente 20 secondes..."
sleep 20

echo ""
echo "4. Vérification logs (plus d'erreurs RBAC?):"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
kubectl logs -n ingress-nginx $INGRESS_POD --tail=10 | grep -i "error\|forbidden" || echo "✅ Pas d'erreurs RBAC récentes"
echo ""

echo "5. Vérification config NGINX:"
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -i "platform.keybuzz.io" | head -5 || echo "❌ Toujours pas trouvé"
echo ""

echo "✅ Correction RBAC terminée"

