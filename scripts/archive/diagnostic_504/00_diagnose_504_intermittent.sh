#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Intermittent 504"
echo "=============================================================="
echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}')
POD_NAME=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}')
POD_IP=$(kubectl get pod -n keybuzz "$POD_NAME" -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test 1: Logs Ingress Controller (erreurs récentes)
echo "1. Logs Ingress Controller (dernières 50 lignes avec erreurs):"
kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=50 2>&1 | grep -i -E '504|502|503|timeout|upstream|connect|error|failed' | head -30
echo ""

# Test 2: Configuration NGINX complète pour platform.keybuzz.io
echo "2. Configuration NGINX complète (platform.keybuzz.io):"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -B 10 -A 50 'platform.keybuzz.io' | head -70
echo ""

# Test 3: Test de connectivité répété (10 fois)
echo "3. Test de connectivité répété (10 tentatives):"
SUCCESS=0
FAIL=0
for i in {1..10}; do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 3 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK"
        ((SUCCESS++))
    else
        echo "  Tentative $i: ❌ ÉCHEC ($RESULT)"
        ((FAIL++))
    fi
    sleep 1
done
echo ""
echo "  Résultat: $SUCCESS succès, $FAIL échecs"
echo ""

# Test 4: Test DNS depuis Ingress
echo "4. Test DNS depuis Ingress Controller:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "nslookup keybuzz-front.keybuzz.svc.cluster.local 2>&1 || echo 'DNS échoué'" | head -10
echo ""

# Test 5: Test avec IP directe (10 fois)
echo "5. Test avec IP directe du Service (10 tentatives):"
SUCCESS2=0
FAIL2=0
for i in {1..10}; do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 3 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo "  Tentative $i: ✅ OK"
        ((SUCCESS2++))
    else
        echo "  Tentative $i: ❌ ÉCHEC"
        ((FAIL2++))
    fi
    sleep 1
done
echo ""
echo "  Résultat: $SUCCESS2 succès, $FAIL2 échecs"
echo ""

# Test 6: Vérifier les endpoints
echo "6. Vérification Endpoints:"
kubectl get endpoints -n keybuzz keybuzz-front -o yaml | grep -A 20 'subsets:'
echo ""

# Test 7: Vérifier la configuration upstream NGINX
echo "7. Configuration upstream NGINX:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -A 10 "upstream.*keybuzz-front" | head -15
echo ""

# Test 8: Vérifier les timeouts actuels
echo "8. Timeouts NGINX actuels:"
kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>&1 | grep -E 'proxy_connect_timeout|proxy_send_timeout|proxy_read_timeout|proxy_next_upstream|keepalive' | head -15
echo ""

# Test 9: Vérifier les annotations Ingress
echo "9. Annotations Ingress:"
kubectl get ingress -n keybuzz keybuzz-front-ingress -o yaml | grep -A 10 'annotations:'
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

