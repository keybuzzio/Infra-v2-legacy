#!/usr/bin/env bash
# Script simplifié pour créer les DaemonSets KeyBuzz

set -euo pipefail

MASTER_IP="10.0.0.100"

echo "Création DaemonSet KeyBuzz API..."
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: keybuzz-api
spec:
  selector:
    matchLabels:
      app: keybuzz-api
  template:
    metadata:
      labels:
        app: keybuzz-api
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
      tolerations:
      - operator: Exists
      containers:
      - name: keybuzz-api
        image: nginx:alpine
        ports:
        - containerPort: 8080
          hostPort: 8080
          name: http
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo 'server { listen 8080; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf
          echo '<!DOCTYPE html><html><head><title>KeyBuzz API</title></head><body><h1>KeyBuzz API</h1><p>API deployee avec succes</p></body></html>' > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
EOF

echo "Création DaemonSet KeyBuzz Front..."
kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: keybuzz-front
  namespace: keybuzz
  labels:
    app: keybuzz-front
spec:
  selector:
    matchLabels:
      app: keybuzz-front
  template:
    metadata:
      labels:
        app: keybuzz-front
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
      tolerations:
      - operator: Exists
      containers:
      - name: keybuzz-front
        image: nginx:alpine
        ports:
        - containerPort: 3000
          hostPort: 3000
          name: http
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo 'server { listen 3000; root /usr/share/nginx/html; index index.html; location / { try_files $uri $uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf
          echo '<!DOCTYPE html><html><head><title>KeyBuzz Platform</title></head><body><h1>KeyBuzz Platform</h1><p>Frontend deploye avec succes</p></body></html>' > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
EOF

echo "Mise à jour Services en NodePort..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-api
  namespace: keybuzz
spec:
  type: NodePort
  selector:
    app: keybuzz-api
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
---
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-front
  namespace: keybuzz
spec:
  type: NodePort
  selector:
    app: keybuzz-front
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30000
EOF

echo "Attente 20 secondes..."
sleep 20

echo "Vérification..."
kubectl get daemonset -n keybuzz
echo ""
kubectl get pods -n keybuzz -o wide
echo ""
kubectl get svc -n keybuzz

