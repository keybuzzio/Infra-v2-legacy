#!/usr/bin/env bash
# Script final pour tester si le problème 504 est résolu

set +e

echo "=============================================================="
echo " [KeyBuzz] Test Final - Problème 504"
echo "=============================================================="
echo ""

# Attendre que les pods soient prêts
echo "Attente que les pods KeyBuzz soient prêts..."
for i in {1..30}; do
    READY=$(kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | awk '{print $2}' | grep -c "1/1" || echo "0")
    if [[ "$READY" -ge 3 ]]; then
        echo "✅ Tous les pods sont prêts"
        break
    fi
    echo "   Attente... ($i/30)"
    sleep 2
done

echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
POD_IP=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}' | xargs kubectl get pod -n keybuzz -o jsonpath='{.status.podIP}' 2>/dev/null || echo "")

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test 1: Ingress -> Service IP
echo "1. Test Ingress -> Service IP ($SVC_IP:80) - 10 tentatives:"
SUCCESS1=0
FAIL1=0
for i in $(seq 1 10); do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo -n "✅"
        SUCCESS1=$((SUCCESS1 + 1))
    else
        echo -n "❌"
        FAIL1=$((FAIL1 + 1))
    fi
    sleep 1
done
echo ""
echo "   Résultat: $SUCCESS1 succès, $FAIL1 échecs"
echo ""

# Test 2: Ingress -> Pod IP direct
if [[ -n "$POD_IP" ]]; then
    echo "2. Test Ingress -> Pod IP direct ($POD_IP:80) - 10 tentatives:"
    SUCCESS2=0
    FAIL2=0
    for i in $(seq 1 10); do
        RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$POD_IP/ 2>&1" | head -1 || echo "FAIL")
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
    echo "   Résultat: $SUCCESS2 succès, $FAIL2 échecs"
    echo ""
fi

# Test 3: Ingress -> Service via Host header (simulation LB)
echo "3. Test Ingress -> Service via Host header (simulation LB) - 10 tentatives:"
SUCCESS3=0
FAIL3=0
for i in $(seq 1 10); do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo -n "✅"
        SUCCESS3=$((SUCCESS3 + 1))
    else
        echo -n "❌"
        FAIL3=$((FAIL3 + 1))
    fi
    sleep 1
done
echo ""
echo "   Résultat: $SUCCESS3 succès, $FAIL3 échecs"
echo ""

# Résumé
echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "Test 1 (Service IP): $SUCCESS1/10"
echo "Test 2 (Pod IP): $SUCCESS2/10"
echo "Test 3 (Host header): $SUCCESS3/10"
echo ""

if [[ $SUCCESS3 -ge 8 ]]; then
    echo "✅ Le problème 504 semble résolu !"
    echo "   Testez maintenant depuis votre navigateur:"
    echo "   - https://platform.keybuzz.io"
    echo "   - https://platform-api.keybuzz.io"
elif [[ $SUCCESS3 -ge 5 ]]; then
    echo "⚠️  Amélioration mais encore des problèmes intermittents"
else
    echo "❌ Le problème persiste. Investigation supplémentaire nécessaire."
fi

echo ""
echo "=============================================================="

