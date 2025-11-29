#!/bin/bash
set -e

echo "=== Création des pages de test ==="

# Page HTML pour le Front
FRONT_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz Platform</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🚀 KeyBuzz Platform</h1><p>Frontend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

# Page HTML pour l'API
API_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz API</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🔌 KeyBuzz API</h1><p>Backend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

echo "Création des pages Front..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "$FRONT_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  echo "  ✅ Front: $POD"
done

echo "Création des pages API..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  kubectl exec -n keybuzz $POD -- sh -c 'mkdir -p /usr/share/nginx/html' 2>/dev/null || true
  echo "$API_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  NGINX_CONF='events { worker_connections 1024; } http { server { listen 8080; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } } }'
  echo "$NGINX_CONF" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /etc/nginx/nginx.conf'
  kubectl exec -n keybuzz $POD -- nginx -s reload 2>/dev/null || true
  echo "  ✅ API: $POD"
done

echo ""
echo "✅ Pages de test créées"
echo "Les URLs devraient maintenant afficher des pages au lieu de 404"

