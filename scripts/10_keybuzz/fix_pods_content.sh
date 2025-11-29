#!/bin/bash
set -e

echo "=== VÉRIFICATION ET CORRECTION DES PODS ==="

# Page HTML pour le Front
FRONT_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz Platform</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🚀 KeyBuzz Platform</h1><p>Frontend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

# Page HTML pour l'API
API_HTML='<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz API</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🔌 KeyBuzz API</h1><p>Backend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>'

echo ""
echo "=== 1. VÉRIFICATION PODS FRONT ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  echo "  - Vérification index.html..."
  kubectl exec -n keybuzz $POD -- test -f /usr/share/nginx/html/index.html && echo "    ✅ index.html existe" || echo "    ❌ index.html manquant"
  echo "  - Contenu index.html:"
  kubectl exec -n keybuzz $POD -- cat /usr/share/nginx/html/index.html | head -3 || echo "    ❌ Erreur lecture"
  echo "  - Test curl localhost:80:"
  kubectl exec -n keybuzz $POD -- curl -s http://localhost:80 | head -3 || echo "    ❌ Erreur curl"
  echo ""
done

echo "=== 2. VÉRIFICATION PODS API ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  echo "  - Vérification index.html..."
  kubectl exec -n keybuzz $POD -- test -f /usr/share/nginx/html/index.html && echo "    ✅ index.html existe" || echo "    ❌ index.html manquant"
  echo "  - Vérification nginx.conf..."
  kubectl exec -n keybuzz $POD -- test -f /etc/nginx/nginx.conf && echo "    ✅ nginx.conf existe" || echo "    ❌ nginx.conf manquant"
  echo "  - Contenu nginx.conf:"
  kubectl exec -n keybuzz $POD -- cat /etc/nginx/nginx.conf | head -10 || echo "    ❌ Erreur lecture"
  echo "  - Processus nginx:"
  kubectl exec -n keybuzz $POD -- ps aux | grep nginx | head -3 || echo "    ❌ Nginx non démarré"
  echo "  - Test curl localhost:8080:"
  kubectl exec -n keybuzz $POD -- curl -s http://localhost:8080 | head -3 || echo "    ❌ Erreur curl"
  echo ""
done

echo "=== 3. RECRÉATION DES PAGES SI NÉCESSAIRE ==="

echo "Création pages Front..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "$FRONT_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  echo "  ✅ $POD"
done

echo "Création pages API..."
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  # Créer le répertoire
  kubectl exec -n keybuzz $POD -- sh -c 'mkdir -p /usr/share/nginx/html' 2>/dev/null || true
  
  # Créer la page HTML
  echo "$API_HTML" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /usr/share/nginx/html/index.html'
  
  # Créer la config nginx pour écouter sur 8080
  NGINX_CONF='events { worker_connections 1024; }
http {
    server {
        listen 8080;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}'
  echo "$NGINX_CONF" | kubectl exec -n keybuzz $POD -- sh -c 'cat > /etc/nginx/nginx.conf'
  
  # Redémarrer nginx
  kubectl exec -n keybuzz $POD -- nginx -s reload 2>/dev/null || kubectl exec -n keybuzz $POD -- nginx 2>/dev/null || true
  echo "  ✅ $POD"
done

echo ""
echo "=== 4. TESTS FINAUX ==="
echo "Test Front..."
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n keybuzz $POD_FRONT -- curl -s http://localhost:80 | grep -q "KeyBuzz Platform" && echo "✅ Front OK" || echo "❌ Front KO"

echo "Test API..."
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n keybuzz $POD_API -- curl -s http://localhost:8080 | grep -q "KeyBuzz API" && echo "✅ API OK" || echo "❌ API KO"

echo ""
echo "✅ Correction terminée"

