#!/bin/bash
set -e

echo "=== DIAGNOSTIC INGRESS CLASS ==="
echo ""

echo "1. Vérification IngressClass:"
kubectl get ingressclass
echo ""

echo "2. Vérification Ingress avec IngressClass:"
kubectl get ingress -n keybuzz -o yaml | grep -E "ingressClassName|name:" | head -10
echo ""

echo "3. Vérification Ingress NGINX Controller:"
kubectl get deployment -n ingress-nginx -o yaml | grep -A 5 "ingress-class" || kubectl get daemonset -n ingress-nginx -o yaml | grep -A 5 "ingress-class"
echo ""

echo "4. Config NGINX complète (premiers 200 lignes):"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | head -200
echo ""

echo "=== CORRECTION ==="
echo ""

echo "1. Vérification de l'IngressClass nginx:"
if ! kubectl get ingressclass nginx >/dev/null 2>&1; then
  echo "Création de l'IngressClass nginx..."
  kubectl create ingressclass nginx --controller=k8s.io/ingress-nginx
fi
kubectl get ingressclass nginx
echo ""

echo "2. Vérification que les Ingress utilisent bien l'IngressClass:"
kubectl get ingress -n keybuzz -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.ingressClassName}{"\n"}{end}'
echo ""

echo "3. Redémarrage de l'Ingress Controller pour recharger la config:"
kubectl rollout restart daemonset -n ingress-nginx ingress-nginx-controller || kubectl rollout restart deployment -n ingress-nginx ingress-nginx-controller
echo "Attente 10 secondes..."
sleep 10

echo ""
echo "4. Vérification après redémarrage:"
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app=ingress-nginx -o jsonpath='{.items[0].metadata.name}')
echo "Recherche de platform.keybuzz.io dans la config NGINX:"
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 -B 5 "platform.keybuzz.io" || echo "❌ Toujours pas trouvé"
echo ""

echo "✅ Correction terminée"

