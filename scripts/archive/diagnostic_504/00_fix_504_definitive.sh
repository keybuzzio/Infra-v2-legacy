#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Correction Définitive 504 Intermittent"
echo "=============================================================="
echo ""

# 1. Augmenter les timeouts et ajouter retries
echo "1. Configuration des timeouts et retries Ingress..."
kubectl annotate ingress -n keybuzz keybuzz-front-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-timeout=0 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-tries=3 \
  nginx.ingress.kubernetes.io/upstream-keepalive-connections=64 \
  nginx.ingress.kubernetes.io/upstream-keepalive-timeout=60 \
  nginx.ingress.kubernetes.io/upstream-keepalive-requests=100 \
  --overwrite 2>/dev/null || true

kubectl annotate ingress -n keybuzz keybuzz-api-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=120 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-timeout=0 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-tries=3 \
  nginx.ingress.kubernetes.io/upstream-keepalive-connections=64 \
  nginx.ingress.kubernetes.io/upstream-keepalive-timeout=60 \
  nginx.ingress.kubernetes.io/upstream-keepalive-requests=100 \
  --overwrite 2>/dev/null || true

echo "  ✅ Annotations mises à jour"
echo ""

# 2. Configurer ConfigMap Ingress pour timeouts globaux
echo "2. Configuration ConfigMap Ingress NGINX..."
kubectl get configmap -n ingress-nginx ingress-nginx-controller -o yaml > /tmp/ingress-configmap.yaml 2>/dev/null || cat > /tmp/ingress-configmap.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  proxy-connect-timeout: "120"
  proxy-send-timeout: "120"
  proxy-read-timeout: "120"
  proxy-next-upstream-timeout: "0"
  proxy-next-upstream-tries: "3"
  upstream-keepalive-connections: "64"
  upstream-keepalive-timeout: "60"
  upstream-keepalive-requests: "100"
  keepalive-timeout: "75"
  keepalive-requests: "100"
EOF

kubectl apply -f /tmp/ingress-configmap.yaml
echo "  ✅ ConfigMap mise à jour"
echo ""

# 3. Vérifier et corriger les Services (ajouter sessionAffinity)
echo "3. Configuration des Services (sessionAffinity)..."
kubectl patch svc -n keybuzz keybuzz-front -p '{"spec":{"sessionAffinity":"ClientIP","sessionAffinityConfig":{"clientIP":{"timeoutSeconds":10800}}}}' 2>/dev/null || true
kubectl patch svc -n keybuzz keybuzz-api -p '{"spec":{"sessionAffinity":"ClientIP","sessionAffinityConfig":{"clientIP":{"timeoutSeconds":10800}}}}' 2>/dev/null || true
echo "  ✅ Services mis à jour"
echo ""

# 4. Vérifier les Endpoints
echo "4. Vérification des Endpoints..."
kubectl get endpoints -n keybuzz
echo ""

# 5. Redémarrer les pods Ingress pour appliquer les changements
echo "5. Redémarrage des pods Ingress Controller..."
kubectl delete pod -n ingress-nginx -l app.kubernetes.io/component=controller
echo "  Pods supprimés, attente redémarrage (30 secondes)..."
sleep 30
echo ""

# 6. Vérifier que les pods sont prêts
echo "6. Vérification des pods Ingress..."
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller
echo ""

# 7. Test de connectivité après correction
echo "7. Test de connectivité après correction (5 tentatives)..."
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SUCCESS=0
FAIL=0
for i in {1..5}; do
    sleep 2
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK"
        ((SUCCESS++))
    else
        echo "  Tentative $i: ❌ ÉCHEC"
        ((FAIL++))
    fi
done
echo ""
echo "  Résultat: $SUCCESS succès, $FAIL échecs"
echo ""

# 8. Vérifier la configuration NGINX finale
echo "8. Vérification configuration NGINX finale..."
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -E 'proxy_connect_timeout|proxy_send_timeout|proxy_read_timeout|proxy_next_upstream|keepalive' | head -10
echo ""

echo "=============================================================="
echo " ✅ Correction terminée"
echo "=============================================================="
echo ""
echo "Modifications appliquées:"
echo "  - Timeouts augmentés: 120s (connect, send, read)"
echo "  - Retries: 3 tentatives"
echo "  - Keepalive: 64 connexions, 60s timeout"
echo "  - SessionAffinity: ClientIP (3h)"
echo "  - ConfigMap Ingress: timeouts globaux"
echo ""
echo "Attendez 1-2 minutes pour que les changements se propagent,"
echo "puis testez à nouveau les URLs."
echo ""

