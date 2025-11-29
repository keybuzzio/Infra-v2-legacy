#!/usr/bin/env bash
# Script de test réseau depuis un pod de test

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Test Réseau depuis Pod de Test"
echo "=============================================================="
echo ""

SVC_IP="10.43.38.57"
POD_IP="10.42.5.5"

echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test avec un pod curl
echo "Création d'un pod de test..."
kubectl run test-curl-$(date +%s) --image=curlimages/curl:latest --rm -i --restart=Never -- sh <<EOF
echo "=== Test depuis pod de test ==="
echo ""
echo "1. Test vers Service ($SVC_IP:80):"
timeout 10 curl -v http://$SVC_IP/ 2>&1 | head -20
echo ""
echo "2. Test vers Pod direct ($POD_IP:80):"
timeout 10 curl -v http://$POD_IP/ 2>&1 | head -20
echo ""
echo "3. Vérification DNS:"
nslookup kubernetes.default.svc.cluster.local || echo "DNS échoué"
echo ""
echo "4. Vérification routes:"
ip route | grep -E "10.42|10.43" | head -10
EOF

echo ""
echo "=============================================================="

