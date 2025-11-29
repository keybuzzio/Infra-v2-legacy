#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Correction Erreur 504 Ingress"
echo "=============================================================="
echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$INGRESS_POD" ]]; then
    INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep Running | head -1 | awk '{print $1}' || echo "")
fi
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-api -o jsonpath='{.spec.clusterIP}')
SVC_PORT=$(kubectl get svc -n keybuzz keybuzz-api -o jsonpath='{.spec.ports[0].port}')

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Service Port: $SVC_PORT"
echo ""

# Test 1: Configuration NGINX
echo "1. Configuration NGINX pour platform.keybuzz.io:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -B 5 -A 25 'platform.keybuzz.io' | head -35
echo ""

# Test 2: Test DNS depuis Ingress Controller
echo "2. Test DNS depuis Ingress Controller:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- nslookup keybuzz-api.keybuzz.svc.cluster.local 2>&1 | head -10
echo ""

# Test 3: Test avec IP directe
echo "3. Test avec IP directe du Service:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- wget -qO- -T 5 "http://${SVC_IP}:${SVC_PORT}/" 2>&1 | head -5
echo ""

# Test 4: Test avec nom de service complet
echo "4. Test avec nom de service complet:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- wget -qO- -T 5 "http://keybuzz-api.keybuzz.svc.cluster.local:${SVC_PORT}/" 2>&1 | head -5
echo ""

# Test 5: Test avec nom court
echo "5. Test avec nom court:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- wget -qO- -T 5 "http://keybuzz-api.keybuzz:${SVC_PORT}/" 2>&1 | head -5
echo ""

# Test 6: Logs Ingress Controller
echo "6. Logs Ingress Controller (erreurs récentes):"
kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=30 2>&1 | grep -i -E 'platform|keybuzz|504|502|503|timeout|upstream|connect' | head -20
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

