#!/usr/bin/env bash
# Test après correction UFW

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Test après Correction UFW"
echo "=============================================================="
echo ""

SVC_IP="10.43.38.57"
POD_IP="10.42.5.5"

# Test 1: Pod vers Service ClusterIP
echo "1. Test Pod -> Service ClusterIP ($SVC_IP:80):"
echo "=============================================================="
kubectl run test-curl-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -- sh <<EOF
echo "Test vers Service..."
timeout 10 curl -s http://$SVC_IP/ | head -3 || echo "❌ ÉCHEC"
EOF
echo ""

# Test 2: Pod vers Pod direct
echo "2. Test Pod -> Pod direct ($POD_IP:80):"
echo "=============================================================="
kubectl run test-curl-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -- sh <<EOF
echo "Test vers Pod direct..."
timeout 10 curl -s http://$POD_IP/ | head -3 || echo "❌ ÉCHEC"
EOF
echo ""

# Test 3: Ingress Controller vers Service
echo "3. Test Ingress Controller -> Service ($SVC_IP:80) - 10 tentatives:"
echo "=============================================================="
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')

if [[ -n "$INGRESS_POD" ]]; then
  SUCCESS=0
  FAIL=0
  for i in {1..10}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
      SUCCESS=$((SUCCESS + 1))
    else
      echo "❌ ÉCHEC"
      FAIL=$((FAIL + 1))
    fi
    sleep 1
  done
  echo ""
  echo "Résultat: $SUCCESS succès, $FAIL échecs sur 10 tentatives"
else
  echo "Ingress Controller pod non trouvé"
fi
echo ""

# Test 4: Test URLs publiques
echo "4. Test URLs publiques:"
echo "=============================================================="
echo -n "platform.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ HTTP $HTTP_CODE"
else
  echo "❌ HTTP $HTTP_CODE"
fi

echo -n "platform-api.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform-api.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✅ HTTP $HTTP_CODE"
else
  echo "❌ HTTP $HTTP_CODE"
fi
echo ""

# Résumé
echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
if [[ $SUCCESS -ge 8 ]]; then
  echo "✅ La connectivité fonctionne ! Le problème 504 devrait être résolu."
else
  echo "⚠️  La connectivité est encore intermittente."
fi
echo ""
echo "=============================================================="
