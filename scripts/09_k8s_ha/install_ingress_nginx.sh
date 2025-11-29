#!/usr/bin/env bash
#
# install_ingress_nginx.sh - Installe ingress-nginx en DaemonSet + hostNetwork
#
# Usage:
#   ./install_ingress_nginx.sh
#
# Prérequis:
#   - Cluster Kubernetes opérationnel
#   - kubectl configuré
#   - Exécuter depuis install-01
#

set -euo pipefail

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

# Vérifier kubectl
if ! command -v kubectl &> /dev/null; then
    log_error "kubectl n'est pas installé"
    exit 1
fi

# Vérifier la connexion au cluster
if ! kubectl cluster-info &> /dev/null; then
    log_error "Impossible de se connecter au cluster Kubernetes"
    exit 1
fi

log_info "=============================================================="
log_info " Installation ingress-nginx (DaemonSet + hostNetwork)"
log_info "=============================================================="
echo ""

# Créer le namespace
log_info "Création du namespace ingress-nginx..."
kubectl create namespace ingress-nginx --dry-run=client -o yaml | kubectl apply -f -
log_success "Namespace créé"

# Télécharger le manifest officiel
log_info "Téléchargement du manifest ingress-nginx..."
MANIFEST_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/baremetal/deploy.yaml"
TMP_MANIFEST="/tmp/ingress-nginx-manifest.yaml"

curl -sL "${MANIFEST_URL}" -o "${TMP_MANIFEST}"
log_success "Manifest téléchargé"

# Modifier le manifest pour DaemonSet + hostNetwork
log_info "Modification du manifest pour DaemonSet + hostNetwork..."

# Créer un manifest modifié
cat > /tmp/ingress-nginx-daemonset.yaml <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
data:
  allow-snippet-annotations: "true"
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/component: controller
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/instance: ingress-nginx
      app.kubernetes.io/component: controller
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ingress-nginx
        app.kubernetes.io/instance: ingress-nginx
        app.kubernetes.io/component: controller
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      serviceAccountName: ingress-nginx
      containers:
      - name: controller
        image: registry.k8s.io/ingress-nginx/controller:v1.9.5
        args:
        - /nginx-ingress-controller
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx-controller
        - --election-id=ingress-nginx-leader
        - --ingress-class=nginx
        - --configmap=$(POD_NAMESPACE)/ingress-nginx-controller
        - --validating-webhook=:8443
        - --validating-webhook-certificate=/usr/local/certificates/cert
        - --validating-webhook-key=/usr/local/certificates/key
        ports:
        - name: http
          containerPort: 80
          hostPort: 80
        - name: https
          containerPort: 443
          hostPort: 443
        - name: webhook
          containerPort: 8443
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: LD_PRELOAD
          value: /usr/local/lib/libmimalloc.so
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 3
        resources:
          requests:
            cpu: 100m
            memory: 90Mi
          limits:
            cpu: 1000m
            memory: 512Mi
        securityContext:
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
          runAsUser: 101
          allowPrivilegeEscalation: false
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
      - operator: Exists
EOF

log_success "Manifest DaemonSet créé"

# Appliquer le manifest
log_info "Application du manifest ingress-nginx..."
kubectl apply -f /tmp/ingress-nginx-daemonset.yaml
log_success "Manifest appliqué"

# Attendre que les pods soient prêts
log_info "Attente que les pods ingress-nginx soient prêts (60 secondes)..."
sleep 60

# Vérifier le statut
log_info "Vérification du statut..."
kubectl get daemonset -n ingress-nginx ingress-nginx-controller
kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller

log_success "ingress-nginx installé en DaemonSet + hostNetwork"
log_info "Les ports 80 et 443 sont maintenant exposés sur tous les nœuds"

