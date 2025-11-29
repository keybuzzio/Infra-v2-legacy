#!/bin/bash
set -e

echo "=== CORRECTION DES FICHIERS AVEC HEREDOC ==="

echo ""
echo "=== CORRECTION PODS FRONT ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  kubectl exec -n keybuzz $POD -- sh << 'ENDOFFRONT'
mkdir -p /usr/share/nginx/html
cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz Platform</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#667eea 0%,#764ba2 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🚀 KeyBuzz Platform</h1><p>Frontend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>
EOF
chmod 644 /usr/share/nginx/html/index.html
wc -c /usr/share/nginx/html/index.html
ENDOFFRONT
  echo "  ✅ Fichier créé"
done

echo ""
echo "=== CORRECTION PODS API ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  kubectl exec -n keybuzz $POD -- sh << 'ENDOFAPI'
mkdir -p /usr/share/nginx/html
cat > /usr/share/nginx/html/index.html << 'EOF'
<!DOCTYPE html><html><head><meta charset=UTF-8><title>KeyBuzz API</title><style>body{font-family:sans-serif;margin:0;padding:0;background:linear-gradient(135deg,#f093fb 0%,#f5576c 100%);color:white;display:flex;justify-content:center;align-items:center;min-height:100vh}.container{text-align:center;padding:2rem}h1{font-size:3rem;margin-bottom:1rem}.status{background:rgba(255,255,255,0.2);padding:1rem 2rem;border-radius:10px;margin-top:2rem;display:inline-block}</style></head><body><div class=container><h1>🔌 KeyBuzz API</h1><p>Backend déployé avec succès</p><div class=status>✅ Service opérationnel</div></div></body></html>
EOF
chmod 644 /usr/share/nginx/html/index.html
cat > /etc/nginx/nginx.conf << 'EOF'
events { worker_connections 1024; }
http {
    server {
        listen 80;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF
nginx -s reload 2>/dev/null || true
wc -c /usr/share/nginx/html/index.html
ENDOFAPI
  echo "  ✅ Fichier créé"
done

echo ""
echo "=== TESTS FINAUX ==="
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')

echo "Test Front ($POD_FRONT):"
kubectl exec -n keybuzz $POD_FRONT -- sh -c 'echo "GET / HTTP/1.1
Host: localhost
Connection: close

" | nc localhost 80 | head -15'

echo ""
echo "Test API ($POD_API):"
kubectl exec -n keybuzz $POD_API -- sh -c 'echo "GET / HTTP/1.1
Host: localhost
Connection: close

" | nc localhost 80 | head -15'

echo ""
echo "✅ Correction terminée"
echo ""
echo "Les URLs devraient maintenant fonctionner:"
echo "  - https://platform.keybuzz.io"
echo "  - https://platform-api.keybuzz.io"

