#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Test de Stabilité"
echo "=============================================================="
echo ""

INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')

if [[ -z "$INGRESS_POD" ]]; then
    echo "❌ Aucun pod Ingress trouvé"
    exit 1
fi

echo "Ingress Pod: $INGRESS_POD"
echo ""

# Test 20 tentatives
echo "Test de connectivité (20 tentatives):"
SUCCESS=0
FAIL=0
FAIL_TIMES=()

for i in $(seq 1 20); do
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo -n "✅"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -n "❌"
        FAIL=$((FAIL + 1))
        FAIL_TIMES+=("$i")
    fi
    if [[ $((i % 10)) -eq 0 ]]; then
        echo " ($i/20)"
    fi
    sleep 1
done
echo ""
echo ""

echo "Résultats:"
TOTAL=20
SUCCESS_PCT=$((SUCCESS * 100 / TOTAL))
FAIL_PCT=$((FAIL * 100 / TOTAL))
echo "  ✅ Succès: $SUCCESS / $TOTAL ($SUCCESS_PCT%)"
echo "  ❌ Échecs: $FAIL / $TOTAL ($FAIL_PCT%)"
if [[ ${#FAIL_TIMES[@]} -gt 0 ]]; then
    echo "  Échecs aux tentatives: ${FAIL_TIMES[*]}"
fi
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Parfait ! Aucun échec détecté."
elif [[ $FAIL -le 2 ]]; then
    echo "⚠️  Quelques échecs isolés (acceptable)"
else
    echo "❌ Trop d'échecs détectés. Investigation nécessaire."
fi

echo ""
echo "=============================================================="

