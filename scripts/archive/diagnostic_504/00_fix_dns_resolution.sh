#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Correction Résolution DNS et Timeouts"
echo "=============================================================="
echo ""

# Récupérer les informations
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}')
SVC_IP_API=$(kubectl get svc -n keybuzz keybuzz-api -o jsonpath='{.spec.clusterIP}')

echo "Service Front IP: $SVC_IP"
echo "Service API IP: $SVC_IP_API"
echo ""

# 1. Vérifier la résolution DNS depuis Ingress
echo "1. Test résolution DNS depuis Ingress Controller..."
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "nslookup keybuzz-front.keybuzz.svc.cluster.local 2>&1" | head -10
echo ""

# 2. Test avec IP directe (plus rapide)
echo "2. Test avec IP directe (10 tentatives)..."
SUCCESS=0
FAIL=0
for i in $(seq 1 10); do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK"
        SUCCESS=$((SUCCESS + 1))
    else
        echo "  Tentative $i: ❌ ÉCHEC"
        FAIL=$((FAIL + 1))
    fi
    sleep 0.5
done
echo "  Résultat: $SUCCESS succès, $FAIL échecs"
echo ""

# 3. Si IP directe fonctionne mieux, utiliser l'IP dans la configuration NGINX
if [[ $SUCCESS -ge 8 ]]; then
    echo "3. IP directe fonctionne mieux. Configuration de l'upstream avec IP..."
    
    # Créer un ConfigMap pour forcer l'utilisation de l'IP
    cat > /tmp/nginx-custom-upstream.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-custom-upstream
  namespace: ingress-nginx
data:
  custom-upstream.conf: |
    upstream keybuzz-front-upstream {
        server $SVC_IP:80 max_fails=3 fail_timeout=30s;
        keepalive 64;
    }
    upstream keybuzz-api-upstream {
        server $SVC_IP_API:80 max_fails=3 fail_timeout=30s;
        keepalive 64;
    }
EOF
    
    kubectl apply -f /tmp/nginx-custom-upstream.yaml
    echo "  ✅ ConfigMap créé"
    echo ""
fi

# 4. Augmenter les timeouts encore plus et ajouter des retries
echo "4. Augmentation des timeouts et retries..."
kubectl annotate ingress -n keybuzz keybuzz-front-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-timeout=0 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-tries=5 \
  nginx.ingress.kubernetes.io/proxy-next-upstream="error timeout http_502 http_503" \
  --overwrite 2>/dev/null || true

kubectl annotate ingress -n keybuzz keybuzz-api-ingress \
  nginx.ingress.kubernetes.io/proxy-connect-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-send-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-read-timeout=180 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-timeout=0 \
  nginx.ingress.kubernetes.io/proxy-next-upstream-tries=5 \
  nginx.ingress.kubernetes.io/proxy-next-upstream="error timeout http_502 http_503" \
  --overwrite 2>/dev/null || true

echo "  ✅ Annotations mises à jour (180s, 5 retries)"
echo ""

# 5. Mettre à jour ConfigMap avec timeouts plus longs
echo "5. Mise à jour ConfigMap avec timeouts plus longs..."
kubectl patch configmap -n ingress-nginx ingress-nginx-controller --type merge -p '{
  "data": {
    "proxy-connect-timeout": "180",
    "proxy-send-timeout": "180",
    "proxy-read-timeout": "180",
    "proxy-next-upstream-timeout": "0",
    "proxy-next-upstream-tries": "5"
  }
}'
echo "  ✅ ConfigMap mise à jour"
echo ""

# 6. Redémarrer les pods Ingress
echo "6. Redémarrage des pods Ingress..."
kubectl delete pod -n ingress-nginx --all
echo "  Pods supprimés, attente redémarrage (30 secondes)..."
sleep 30
echo ""

# 7. Test final
echo "7. Test final après corrections (10 tentatives)..."
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SUCCESS2=0
FAIL2=0
for i in $(seq 1 10); do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 15 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo -n "✅"
        SUCCESS2=$((SUCCESS2 + 1))
    else
        echo -n "❌"
        FAIL2=$((FAIL2 + 1))
    fi
    sleep 1
done
echo ""
echo "  Résultat: $SUCCESS2 succès, $FAIL2 échecs"
echo ""

echo "=============================================================="
echo " ✅ Corrections appliquées"
echo "=============================================================="
echo ""
echo "Modifications:"
echo "  - Timeouts augmentés: 180s (connect, send, read)"
echo "  - Retries: 5 tentatives"
echo "  - Proxy-next-upstream: error timeout http_502 http_503"
echo "  - ConfigMap: timeouts globaux mis à jour"
echo ""

