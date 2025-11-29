#!/usr/bin/env bash
#
# deploy_platform_apps.sh - Déploiement des applications Platform (API, UI, My)
#
# Usage:
#   ./deploy_platform_apps.sh [PLATFORM_API_IMAGE] [PLATFORM_UI_IMAGE] [PLATFORM_MY_IMAGE]
#
# Prérequis:
#   - Namespace keybuzz créé
#   - ConfigMap et Secret créés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Images Docker (par défaut: nginx pour test, à remplacer par les vraies images)
PLATFORM_API_IMAGE="${1:-nginx:alpine}"
PLATFORM_UI_IMAGE="${2:-nginx:alpine}"
PLATFORM_MY_IMAGE="${3:-nginx:alpine}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

export KUBECONFIG=/root/.kube/config

log_warning "⚠️  Images Docker utilisées:"
log_warning "  API: ${PLATFORM_API_IMAGE}"
log_warning "  UI: ${PLATFORM_UI_IMAGE}"
log_warning "  My: ${PLATFORM_MY_IMAGE}"
log_warning "⚠️  NOTE: Remplacez par vos vraies images Platform"
echo ""

# ============================================================
# 1. DÉPLOIEMENT API (platform-api.keybuzz.io)
# ============================================================
log_info "=============================================================="
log_info "Déploiement Platform API"
log_info "=============================================================="

cat > /tmp/keybuzz-api-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: platform-api
      component: backend
  template:
    metadata:
      labels:
        app: platform-api
        component: backend
    spec:
      containers:
      - name: api
        image: ${PLATFORM_API_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secret
              key: DATABASE_URL
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secret
              key: REDIS_URL
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secret
              key: RABBITMQ_URL
        - name: MINIO_ENDPOINT
          valueFrom:
            configMapKeyRef:
              name: keybuzz-api-config
              key: MINIO_ENDPOINT
        - name: MARIADB_HOST
          valueFrom:
            configMapKeyRef:
              name: keybuzz-api-config
              key: MARIADB_HOST
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
EOF

kubectl apply -f /tmp/keybuzz-api-deployment.yaml
log_success "Deployment keybuzz-api créé"

# Service ClusterIP
cat > /tmp/keybuzz-api-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: platform-api
    component: backend
EOF

kubectl apply -f /tmp/keybuzz-api-service.yaml
log_success "Service keybuzz-api créé"

# Ingress
cat > /tmp/keybuzz-api-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-api-ingress
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  ingressClassName: nginx
  rules:
  - host: platform-api.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-api
            port:
              number: 8080
EOF

kubectl apply -f /tmp/keybuzz-api-ingress.yaml
log_success "Ingress keybuzz-api créé"

echo ""

# ============================================================
# 2. DÉPLOIEMENT UI (platform.keybuzz.io)
# ============================================================
log_info "=============================================================="
log_info "Déploiement Platform UI"
log_info "=============================================================="

cat > /tmp/keybuzz-ui-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keybuzz-ui
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: platform
      component: frontend
  template:
    metadata:
      labels:
        app: platform
        component: frontend
    spec:
      containers:
      - name: ui
        image: ${PLATFORM_UI_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        env:
        - name: API_URL
          value: "https://platform-api.keybuzz.io"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF

kubectl apply -f /tmp/keybuzz-ui-deployment.yaml
log_success "Deployment keybuzz-ui créé"

# Service ClusterIP
cat > /tmp/keybuzz-ui-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-ui
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: platform
    component: frontend
EOF

kubectl apply -f /tmp/keybuzz-ui-service.yaml
log_success "Service keybuzz-ui créé"

# Ingress
cat > /tmp/keybuzz-ui-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-ui-ingress
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
spec:
  ingressClassName: nginx
  rules:
  - host: platform.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-ui
            port:
              number: 80
EOF

kubectl apply -f /tmp/keybuzz-ui-ingress.yaml
log_success "Ingress keybuzz-ui créé"

echo ""

# ============================================================
# 3. DÉPLOIEMENT MY (my.keybuzz.io)
# ============================================================
log_info "=============================================================="
log_info "Déploiement My Portal"
log_info "=============================================================="

cat > /tmp/keybuzz-my-ui-deployment.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keybuzz-my-ui
  namespace: keybuzz
  labels:
    app: my
    component: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my
      component: frontend
  template:
    metadata:
      labels:
        app: my
        component: frontend
    spec:
      containers:
      - name: my-ui
        image: ${PLATFORM_MY_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        env:
        - name: API_URL
          value: "https://platform-api.keybuzz.io"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF

kubectl apply -f /tmp/keybuzz-my-ui-deployment.yaml
log_success "Deployment keybuzz-my-ui créé"

# Service ClusterIP
cat > /tmp/keybuzz-my-ui-service.yaml <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-my-ui
  namespace: keybuzz
  labels:
    app: my
    component: frontend
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: my
    component: frontend
EOF

kubectl apply -f /tmp/keybuzz-my-ui-service.yaml
log_success "Service keybuzz-my-ui créé"

# Ingress
cat > /tmp/keybuzz-my-ui-ingress.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-my-ui-ingress
  namespace: keybuzz
  labels:
    app: my
    component: frontend
spec:
  ingressClassName: nginx
  rules:
  - host: my.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-my-ui
            port:
              number: 80
EOF

kubectl apply -f /tmp/keybuzz-my-ui-ingress.yaml
log_success "Ingress keybuzz-my-ui créé"

echo ""
log_success "✅ Tous les déploiements terminés"
echo ""
log_info "Résumé:"
log_info "  - API: keybuzz-api (3 replicas, port 8080)"
log_info "  - UI: keybuzz-ui (3 replicas, port 80)"
log_info "  - My: keybuzz-my-ui (3 replicas, port 80)"
echo ""
log_info "URLs configurées:"
log_info "  - https://platform-api.keybuzz.io"
log_info "  - https://platform.keybuzz.io"
log_info "  - https://my.keybuzz.io"
echo ""

