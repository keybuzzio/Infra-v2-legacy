#!/bin/bash
set -e

echo "=== CRÉATION INGRESS CLASS ==="
echo ""

echo "1. Vérification IngressClass existante:"
kubectl get ingressclass
echo ""

echo "2. Création de l'IngressClass nginx:"
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF

echo ""
echo "3. Vérification IngressClass créée:"
kubectl get ingressclass nginx
echo ""

echo "4. Vérification Ingress Controller:"
kubectl get daemonset -n ingress-nginx ingress-nginx-controller -o yaml | grep -A 10 "args:" | head -15 || kubectl get deployment -n ingress-nginx ingress-nginx-controller -o yaml | grep -A 10 "args:" | head -15
echo ""

echo "5. Redémarrage Ingress Controller:"
kubectl rollout restart daemonset -n ingress-nginx ingress-nginx-controller 2>/dev/null || kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller
echo "Attente 15 secondes pour le redémarrage..."
sleep 15

echo ""
echo "6. Vérification que les pods sont prêts:"
kubectl get pods -n ingress-nginx
echo ""

echo "7. Vérification config NGINX après redémarrage:"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$INGRESS_POD" ]; then
  echo "Pod: $INGRESS_POD"
  echo "Recherche de platform.keybuzz.io:"
  kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" | head -20 || echo "❌ Toujours pas trouvé"
else
  echo "❌ Aucun pod Ingress trouvé"
fi

echo ""
echo "✅ Correction terminée"

