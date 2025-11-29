#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== VALIDATION MODULE 11 V2 ==="
echo ""

# 1. Vérifier namespace
echo "1. Vérification namespace..."
kubectl get namespace chatwoot > /dev/null 2>&1 && echo "✓ Namespace chatwoot existe" || echo "✗ Namespace chatwoot manquant"

# 2. Vérifier deployments
echo ""
echo "2. Vérification deployments..."
WEB_READY=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WEB_DESIRED=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
WORKER_READY=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_DESIRED=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "$WEB_READY" = "$WEB_DESIRED" ] && [ "$WEB_DESIRED" != "0" ]; then
    echo "✓ Deployment chatwoot-web : $WEB_READY/$WEB_DESIRED Ready"
else
    echo "✗ Deployment chatwoot-web : $WEB_READY/$WEB_DESIRED Ready (attendu: $WEB_DESIRED/$WEB_DESIRED)"
fi

if [ "$WORKER_READY" = "$WORKER_DESIRED" ] && [ "$WORKER_DESIRED" != "0" ]; then
    echo "✓ Deployment chatwoot-worker : $WORKER_READY/$WORKER_DESIRED Ready"
else
    echo "✗ Deployment chatwoot-worker : $WORKER_READY/$WORKER_DESIRED Ready (attendu: $WORKER_DESIRED/$WORKER_DESIRED)"
fi

# 3. Vérifier pods
echo ""
echo "3. Vérification pods..."
PODS_RUNNING=$(kubectl get pods -n chatwoot -l app=chatwoot --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
PODS_TOTAL=$(kubectl get pods -n chatwoot -l app=chatwoot --no-headers 2>/dev/null | wc -l)
echo "Pods Running : $PODS_RUNNING/$PODS_TOTAL"

# 4. Vérifier service
echo ""
echo "4. Vérification service..."
kubectl get svc chatwoot-web -n chatwoot > /dev/null 2>&1 && echo "✓ Service chatwoot-web existe" || echo "✗ Service chatwoot-web manquant"

# 5. Vérifier ingress
echo ""
echo "5. Vérification ingress..."
INGRESS_HOST=$(kubectl get ingress chatwoot-ingress -n chatwoot -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
if [ "$INGRESS_HOST" = "support.keybuzz.io" ]; then
    echo "✓ Ingress configuré pour support.keybuzz.io"
else
    echo "✗ Ingress non configuré correctement (host: $INGRESS_HOST)"
fi

# 6. Test interne
echo ""
echo "6. Test HTTP interne..."
HTTP_CODE=$(curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -s -o /dev/null -w "%{http_code}" --max-time 10 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ]; then
    echo "✓ Test HTTP interne : $HTTP_CODE"
else
    echo "✗ Test HTTP interne : $HTTP_CODE"
fi

echo ""
echo "=== VALIDATION TERMINEE ==="

