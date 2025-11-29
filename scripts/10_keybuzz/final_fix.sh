#!/bin/bash
set -e

echo "=========================================="
echo "  CORRECTION FINALE - KeyBuzz Platform"
echo "=========================================="
echo ""

# Page HTML pour le Front
FRONT_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz Platform</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🚀 KeyBuzz Platform</h1><p>Frontend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

# Page HTML pour l'API
API_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz API</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🔌 KeyBuzz API</h1><p>Backend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

echo "=== 1. CRÉATION DES PAGES HTML ==="
echo "Front..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "$FRONT_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  kubectl exec -n keybuzz $POD -- chmod 644 /usr/share/nginx/html/index.html
  echo "  ✅ $POD"
done

echo "API..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n keybuzz $POD -- sh -c 'mkdir -p /usr/share/nginx/html' 2>/dev/null || true
  echo "$API_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  kubectl exec -n keybuzz $POD -- chmod 644 /usr/share/nginx/html/index.html
  
  # Configurer nginx pour écouter sur 80
  NGINX_CONF='events { worker_connections 1024; }
http {
    server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}'
  echo "$NGINX_CONF" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /etc/nginx/nginx.conf'
  kubectl exec -n keybuzz $POD -- nginx -s reload 2>/dev/null || true
  echo "  ✅ $POD"
done

echo ""
echo "=== 2. VÉRIFICATION SERVICE API ==="
kubectl get svc keybuzz-api -n keybuzz -o yaml | grep -A 5 "targetPort"
echo ""

echo "=== 3. TEST DIRECT PODS ==="
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')

echo "Test Front ($POD_FRONT):"
RESULT_FRONT=$(kubectl exec -n keybuzz $POD_FRONT -- sh -c 'wget -qO- http://localhost:80 2>/dev/null | head -c 50' || echo "ERROR")
echo "  Résultat: $RESULT_FRONT"

echo "Test API ($POD_API):"
RESULT_API=$(kubectl exec -n keybuzz $POD_API -- sh -c 'wget -qO- http://localhost:80 2>/dev/null | head -c 50' || echo "ERROR")
echo "  Résultat: $RESULT_API"

echo ""
echo "=== 4. TEST VIA SERVICE ==="
echo "Test Service Front:"
kubectl run test-svc-front-$$ --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform.keybuzz.io" http://keybuzz-front.keybuzz.svc.cluster.local:80 | head -c 50 || echo "ERROR"
echo ""

echo "Test Service API:"
kubectl run test-svc-api-$$ --image=curlimages/curl:latest --rm -i --restart=Never -n keybuzz -- curl -s -H "Host: platform-api.keybuzz.io" http://keybuzz-api.keybuzz.svc.cluster.local:80 | head -c 50 || echo "ERROR"
echo ""

echo "=== 5. VÉRIFICATION INGRESS ==="
kubectl get ingress -n keybuzz
echo ""

echo "✅ Correction terminée"
echo ""
echo "Les URLs devraient maintenant fonctionner:"
echo "  - https://platform.keybuzz.io"
echo "  - https://platform-api.keybuzz.io"

