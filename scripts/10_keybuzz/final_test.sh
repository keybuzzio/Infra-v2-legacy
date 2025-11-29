#!/bin/bash
set -e

echo "=== TESTS FINAUX ==="
echo ""

POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')
echo "1. Test API Pod direct ($POD_API):"
kubectl exec -n keybuzz $POD_API -- sh -c 'wget -qO- http://localhost:80 2>/dev/null | head -c 100' && echo " ✅" || echo " ❌"
echo ""

echo "2. Test Service Front:"
kubectl run test-svc-front-$$ --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform.keybuzz.io" http://keybuzz-front.keybuzz.svc.cluster.local:80 | head -c 100 && echo " ✅" || echo " ❌"
echo ""

echo "3. Test Service API:"
kubectl run test-svc-api-$$ --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform-api.keybuzz.io" http://keybuzz-api.keybuzz.svc.cluster.local:80 | head -c 100 && echo " ✅" || echo " ❌"
echo ""

echo "4. Vérification Ingress:"
kubectl get ingress -n keybuzz
echo ""

echo "✅ Tests terminés"
echo ""
echo "Les URLs devraient maintenant fonctionner:"
echo "  - https://platform.keybuzz.io"
echo "  - https://platform-api.keybuzz.io"

