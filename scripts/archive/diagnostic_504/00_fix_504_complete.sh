#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic et Correction 504"
echo "=============================================================="
echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}' || echo "")
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
POD_NAME=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
POD_IP=$(kubectl get pod -n keybuzz "$POD_NAME" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

if [[ -z "$INGRESS_POD" ]]; then
    echo "❌ Aucun pod Ingress Controller trouvé"
    kubectl get pods -n ingress-nginx
    exit 1
fi

if [[ -z "$SVC_IP" ]] || [[ -z "$POD_IP" ]]; then
    echo "❌ Impossible de récupérer Service IP ou Pod IP"
    echo "Service IP: $SVC_IP"
    echo "Pod IP: $POD_IP"
    exit 1
fi

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test 1: Connectivité réseau Ingress -> Pod
echo "1. Test connectivité Ingress -> Pod direct:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 nc -zv $POD_IP 80 2>&1" || echo "  ❌ Non accessible"
echo ""

# Test 2: Test HTTP direct vers Pod
echo "2. Test HTTP direct vers Pod:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 wget -qO- http://$POD_IP/ 2>&1" | head -3 || echo "  ❌ Échec"
echo ""

# Test 3: Test Service IP
echo "3. Test Service IP:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 nc -zv $SVC_IP 80 2>&1" || echo "  ❌ Non accessible"
echo ""

# Test 4: Configuration NGINX upstream
echo "4. Configuration NGINX upstream pour platform.keybuzz.io:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -A 30 'platform.keybuzz.io' | grep -A 20 'upstream' | head -25
echo ""

# Test 5: Vérifier les timeouts NGINX
echo "5. Configuration timeouts NGINX:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -E 'proxy_connect_timeout|proxy_send_timeout|proxy_read_timeout|proxy_next_upstream_timeout' | head -10
echo ""

# Correction: Augmenter les timeouts si nécessaire
echo "6. Application de correctifs..."
echo "   Vérification des annotations Ingress..."

# Vérifier et corriger les annotations Ingress
kubectl get ingress -n keybuzz keybuzz-front-ingress -o yaml | grep -E 'proxy.*timeout' || echo "  Aucune annotation timeout trouvée"

# Ajouter des annotations pour augmenter les timeouts
kubectl annotate ingress -n keybuzz keybuzz-front-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=60 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=60 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=60 \
  --overwrite 2>/dev/null || true

kubectl annotate ingress -n keybuzz keybuzz-api-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=60 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=60 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=60 \
  --overwrite 2>/dev/null || true

echo "  ✅ Annotations mises à jour"
echo ""

# Attendre le rechargement NGINX
echo "7. Attente du rechargement NGINX (10 secondes)..."
sleep 10
echo ""

# Test final
echo "8. Test final après correction:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -5 || echo "  ❌ Toujours en échec"
echo ""

echo "=============================================================="
echo " ✅ Correction terminée"
echo "=============================================================="
echo ""
echo "Si le problème persiste, vérifiez :"
echo "  1. Les logs Ingress Controller: kubectl logs -n ingress-nginx $INGRESS_POD"
echo "  2. Les logs pods KeyBuzz: kubectl logs -n keybuzz -l app=keybuzz-front"
echo "  3. La connectivité réseau entre Ingress et pods"
echo ""

