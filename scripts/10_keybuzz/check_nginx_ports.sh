#!/bin/bash
set -e

echo "=== VÉRIFICATION PORTS NGINX ==="

echo ""
echo "=== PODS FRONT (devrait écouter sur 80) ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  echo "  - Ports en écoute:"
  kubectl exec -n keybuzz $POD -- netstat -tlnp 2>/dev/null | grep LISTEN || kubectl exec -n keybuzz $POD -- ss -tlnp 2>/dev/null | grep LISTEN || echo "    (netstat/ss non disponible)"
  echo "  - Test wget localhost:80:"
  kubectl exec -n keybuzz $POD -- wget -qO- http://localhost:80 2>/dev/null | head -3 || echo "    ❌ Erreur"
  echo ""
done

echo "=== PODS API (devrait écouter sur 8080) ==="
for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  echo "Pod: $POD"
  echo "  - Ports en écoute:"
  kubectl exec -n keybuzz $POD -- netstat -tlnp 2>/dev/null | grep LISTEN || kubectl exec -n keybuzz $POD -- ss -tlnp 2>/dev/null | grep LISTEN || echo "    (netstat/ss non disponible)"
  echo "  - Config nginx:"
  kubectl exec -n keybuzz $POD -- cat /etc/nginx/nginx.conf | grep -E "listen|root" || echo "    ❌ Erreur lecture"
  echo "  - Test wget localhost:8080:"
  kubectl exec -n keybuzz $POD -- wget -qO- http://localhost:8080 2>/dev/null | head -3 || echo "    ❌ Erreur"
  echo "  - Test wget localhost:80:"
  kubectl exec -n keybuzz $POD -- wget -qO- http://localhost:80 2>/dev/null | head -3 || echo "    ❌ Erreur"
  echo ""
done

echo "=== SOLUTION: Utiliser le port 80 pour l'API aussi ==="
echo "Le service API expose le port 80 qui redirige vers targetPort 8080"
echo "Mais nginx:alpine écoute par défaut sur 80"
echo "On va configurer nginx pour écouter sur 80 au lieu de 8080"

for POD in $(kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'); do
  echo "Correction pod: $POD"
  
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
  
  # Redémarrer nginx
  kubectl exec -n keybuzz $POD -- nginx -s reload 2>/dev/null || kubectl exec -n keybuzz $POD -- pkill nginx && kubectl exec -n keybuzz $POD -- nginx 2>/dev/null || true
  
  echo "  ✅ Configuré pour écouter sur 80"
done

echo ""
echo "=== MISE À JOUR DU SERVICE API ==="
echo "Le service doit rediriger le port 80 vers targetPort 80 (au lieu de 8080)"

SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: keybuzz-api
spec:
  type: ClusterIP
  selector:
    app: keybuzz-api
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
EOF
)

echo "$SERVICE_YAML" | kubectl apply -f -
echo "✅ Service mis à jour (port 80 → 80)"

echo ""
echo "=== TESTS FINAUX ==="
POD_FRONT=$(kubectl get pod -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[0].metadata.name}')
POD_API=$(kubectl get pod -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[0].metadata.name}')

echo "Test Front (localhost:80):"
kubectl exec -n keybuzz $POD_FRONT -- wget -qO- http://localhost:80 2>/dev/null | grep -q "KeyBuzz Platform" && echo "✅ Front OK" || echo "❌ Front KO"

echo "Test API (localhost:80):"
kubectl exec -n keybuzz $POD_API -- wget -qO- http://localhost:80 2>/dev/null | grep -q "KeyBuzz API" && echo "✅ API OK" || echo "❌ API KO"

echo ""
echo "✅ Correction terminée"

