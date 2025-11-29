#!/bin/bash
set -e

echo "=== VÉRIFICATION COMPLÈTE ==="

POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')

echo ""
echo "=== POD FRONT: $POD_FRONT ==="
echo "1. Fichier index.html existe?"
kubectl exec -n keybuzz $POD_FRONT -- test -f /usr/share/nginx/html/index.html && echo "✅ OUI" || echo "❌ NON"

echo "2. Taille du fichier:"
kubectl exec -n keybuzz $POD_FRONT -- wc -c /usr/share/nginx/html/index.html

echo "3. Premiers 200 caractères:"
kubectl exec -n keybuzz $POD_FRONT -- head -c 200 /usr/share/nginx/html/index.html
echo ""

echo "4. Test HTTP complet:"
kubectl exec -n keybuzz $POD_FRONT -- sh -c 'echo "GET / HTTP/1.1
Host: localhost
Connection: close

" | nc localhost 80 | head -20' || echo "Erreur nc"

echo ""
echo "=== POD API: $POD_API ==="
echo "1. Fichier index.html existe?"
kubectl exec -n keybuzz $POD_API -- test -f /usr/share/nginx/html/index.html && echo "✅ OUI" || echo "❌ NON"

echo "2. Taille du fichier:"
kubectl exec -n keybuzz $POD_API -- wc -c /usr/share/nginx/html/index.html

echo "3. Premiers 200 caractères:"
kubectl exec -n keybuzz $POD_API -- head -c 200 /usr/share/nginx/html/index.html
echo ""

echo "4. Test HTTP complet:"
kubectl exec -n keybuzz $POD_API -- sh -c 'echo "GET / HTTP/1.1
Host: localhost
Connection: close

" | nc localhost 80 | head -20' || echo "Erreur nc"

echo ""
echo "=== TEST VIA SERVICE (avec pod test) ==="
echo "Création d'un pod de test..."
kubectl run test-curl-$$ --image=curlimages/curl:latest --restart=Never -n keybuzz -- sleep 3600
sleep 5

echo "Test Front via Service:"
kubectl exec -n keybuzz test-curl-$$ -- curl -s -H "Host: platform.keybuzz.io" http://keybuzz-front.keybuzz.svc.cluster.local:80 | head -c 100 || echo "ERREUR"

echo ""
echo "Test API via Service:"
kubectl exec -n keybuzz test-curl-$$ -- curl -s -H "Host: platform-api.keybuzz.io" http://keybuzz-api.keybuzz.svc.cluster.local:80 | head -c 100 || echo "ERREUR"

echo ""
echo "Nettoyage..."
kubectl delete pod test-curl-$$ -n keybuzz 2>/dev/null || true

echo ""
echo "✅ Vérification terminée"

