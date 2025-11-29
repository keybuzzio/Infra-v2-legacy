#!/usr/bin/env bash
#
# 11_ct_02_deploy_chatwoot.sh - Déploie Chatwoot dans Kubernetes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Version de Chatwoot (tag stable)
CHATWOOT_VERSION="${CHATWOOT_VERSION:-v3.12.0}"
CHATWOOT_IMAGE="chatwoot/chatwoot:${CHATWOOT_VERSION}"

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

export KUBECONFIG=/root/.kube/config

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Déploiement Chatwoot"
echo "=============================================================="
echo ""

log_info "Image Chatwoot : ${CHATWOOT_IMAGE}"
echo ""

# Vérifier que ConfigMap et Secret existent
if ! kubectl get configmap chatwoot-config -n chatwoot > /dev/null 2>&1; then
    log_error "ConfigMap chatwoot-config non trouvé. Exécutez d'abord 11_ct_01_prepare_config.sh"
    exit 1
fi

if ! kubectl get secret chatwoot-secrets -n chatwoot > /dev/null 2>&1; then
    log_error "Secret chatwoot-secrets non trouvé. Exécutez d'abord 11_ct_01_prepare_config.sh"
    exit 1
fi

# Récupérer les valeurs depuis ConfigMap et Secret
POSTGRES_HOST=$(kubectl get configmap chatwoot-config -n chatwoot -o jsonpath='{.data.POSTGRES_HOST}')
POSTGRES_PORT=$(kubectl get configmap chatwoot-config -n chatwoot -o jsonpath='{.data.POSTGRES_PORT}')
POSTGRES_DB=$(kubectl get configmap chatwoot-config -n chatwoot -o jsonpath='{.data.POSTGRES_DB}')
POSTGRES_USERNAME=$(kubectl get configmap chatwoot-config -n chatwoot -o jsonpath='{.data.POSTGRES_USERNAME}')

# Déployer Chatwoot Web
log_info "Déploiement de Chatwoot Web..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chatwoot-web
  namespace: chatwoot
  labels:
    app: chatwoot
    component: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: chatwoot
      component: web
  template:
    metadata:
      labels:
        app: chatwoot
        component: web
    spec:
      containers:
      - name: chatwoot-web
        image: ${CHATWOOT_IMAGE}
        command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
        ports:
        - containerPort: 3000
          name: http
        envFrom:
        - configMapRef:
            name: chatwoot-config
        - secretRef:
            name: chatwoot-secrets
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: chatwoot-secrets
              key: POSTGRES_PASSWORD
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: chatwoot-config
              key: REDIS_URL
        - name: RAILS_LOG_TO_STDOUT
          value: "true"
        - name: PORT
          value: "3000"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 120
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 3000
          initialDelaySeconds: 60
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chatwoot-worker
  namespace: chatwoot
  labels:
    app: chatwoot
    component: worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: chatwoot
      component: worker
  template:
    metadata:
      labels:
        app: chatwoot
        component: worker
    spec:
      containers:
      - name: chatwoot-worker
        image: ${CHATWOOT_IMAGE}
        command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
        envFrom:
        - configMapRef:
            name: chatwoot-config
        - secretRef:
            name: chatwoot-secrets
        env:
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: chatwoot-secrets
              key: POSTGRES_PASSWORD
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: chatwoot-config
              key: REDIS_URL
        - name: RAILS_LOG_TO_STDOUT
          value: "true"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
---
apiVersion: v1
kind: Service
metadata:
  name: chatwoot-web
  namespace: chatwoot
  labels:
    app: chatwoot
    component: web
spec:
  type: ClusterIP
  ports:
  - port: 3000
    targetPort: 3000
    protocol: TCP
    name: http
  selector:
    app: chatwoot
    component: web
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: chatwoot-ingress
  namespace: chatwoot
  labels:
    app: chatwoot
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
spec:
  ingressClassName: nginx
  rules:
  - host: support.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: chatwoot-web
            port:
              number: 3000
EOF

log_success "Chatwoot déployé"

echo ""
log_info "Attente du démarrage des pods (30 secondes)..."
sleep 30

echo ""
log_info "État des Deployments:"
kubectl get deployments -n chatwoot

echo ""
log_info "État des Pods:"
kubectl get pods -n chatwoot

echo ""
log_success "✅ Déploiement terminé"
echo ""
log_info "Note: Les pods peuvent prendre quelques minutes pour démarrer complètement"
log_info "Vérifiez l'état avec: kubectl get pods -n chatwoot -w"
echo ""

