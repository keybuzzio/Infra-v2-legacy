#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Test de Stabilité 120 secondes"
echo "=============================================================="
echo ""

INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')

if [[ -z "$INGRESS_POD" ]]; then
    echo "❌ Aucun pod Ingress trouvé"
    exit 1
fi

echo "Ingress Pod: $INGRESS_POD"
echo "Durée du test: 120 secondes (1 requête toutes les 2 secondes)"
echo ""

# Test 60 tentatives sur 120 secondes
SUCCESS=0
FAIL=0
FAIL_TIMES=()
START_TIME=$(date +%s)

for i in $(seq 1 60); do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- --header='Host: platform.keybuzz.io' http://localhost/ 2>&1" | head -1 || echo "FAIL")
    
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
        echo -n "✅"
        SUCCESS=$((SUCCESS + 1))
    else
        echo -n "❌"
        FAIL=$((FAIL + 1))
        FAIL_TIMES+=("${ELAPSED}s")
    fi
    
    # Afficher la progression tous les 10 tests
    if [[ $((i % 10)) -eq 0 ]]; then
        echo " (${ELAPSED}s - $i/60)"
    fi
    
    # Attendre 2 secondes entre chaque test
    sleep 2
done

echo ""
echo ""

TOTAL=60
SUCCESS_PCT=$((SUCCESS * 100 / TOTAL))
FAIL_PCT=$((FAIL * 100 / TOTAL))

echo "=============================================================="
echo " Résultats du test (120 secondes)"
echo "=============================================================="
echo ""
echo "  ✅ Succès: $SUCCESS / $TOTAL ($SUCCESS_PCT%)"
echo "  ❌ Échecs: $FAIL / $TOTAL ($FAIL_PCT%)"
echo ""

if [[ ${#FAIL_TIMES[@]} -gt 0 ]]; then
    echo "  Échecs aux temps: ${FAIL_TIMES[*]}"
    echo ""
fi

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Parfait ! Aucun échec détecté sur 120 secondes."
elif [[ $FAIL -le 2 ]]; then
    echo "⚠️  Quelques échecs isolés (acceptable)"
elif [[ $FAIL -le 5 ]]; then
    echo "⚠️  Plusieurs échecs détectés (à surveiller)"
else
    echo "❌ Trop d'échecs détectés. Investigation nécessaire."
fi

echo ""
echo "=============================================================="

