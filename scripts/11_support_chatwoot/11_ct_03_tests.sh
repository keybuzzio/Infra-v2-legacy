#!/usr/bin/env bash
#
# 11_ct_03_tests.sh - Tests de validation Chatwoot
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

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

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Tests de Validation Chatwoot"
echo "=============================================================="
echo ""

# 1. Vérifier le namespace
log_info "Vérification du namespace..."
if kubectl get namespace chatwoot > /dev/null 2>&1; then
    log_success "Namespace chatwoot existe"
else
    log_error "Namespace chatwoot non trouvé"
    exit 1
fi

# 2. Vérifier les Deployments
log_info "Vérification des Deployments..."
WEB_READY=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WEB_REPLICAS=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
WORKER_READY=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_REPLICAS=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "${WEB_READY}" = "${WEB_REPLICAS}" ] && [ "${WEB_REPLICAS}" != "0" ]; then
    log_success "Deployment chatwoot-web : ${WEB_READY}/${WEB_REPLICAS} Ready"
else
    log_error "Deployment chatwoot-web : ${WEB_READY}/${WEB_REPLICAS} Ready (attendu: ${WEB_REPLICAS}/${WEB_REPLICAS})"
fi

if [ "${WORKER_READY}" = "${WORKER_REPLICAS}" ] && [ "${WORKER_REPLICAS}" != "0" ]; then
    log_success "Deployment chatwoot-worker : ${WORKER_READY}/${WORKER_REPLICAS} Ready"
else
    log_error "Deployment chatwoot-worker : ${WORKER_READY}/${WORKER_REPLICAS} Ready (attendu: ${WORKER_REPLICAS}/${WORKER_REPLICAS})"
fi

# 3. Vérifier les Pods
log_info "Vérification des Pods..."
PODS_RUNNING=$(kubectl get pods -n chatwoot -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' | wc -w)
PODS_TOTAL=$(kubectl get pods -n chatwoot -o jsonpath='{.items[*].metadata.name}' | wc -w)

if [ "${PODS_RUNNING}" = "${PODS_TOTAL}" ] && [ "${PODS_TOTAL}" != "0" ]; then
    log_success "Pods : ${PODS_RUNNING}/${PODS_TOTAL} Running"
else
    log_error "Pods : ${PODS_RUNNING}/${PODS_TOTAL} Running (attendu: ${PODS_TOTAL}/${PODS_TOTAL})"
    kubectl get pods -n chatwoot
fi

# 4. Vérifier le Service
log_info "Vérification du Service..."
if kubectl get service chatwoot-web -n chatwoot > /dev/null 2>&1; then
    log_success "Service chatwoot-web existe"
    kubectl get service chatwoot-web -n chatwoot
else
    log_error "Service chatwoot-web non trouvé"
fi

# 5. Vérifier l'Ingress
log_info "Vérification de l'Ingress..."
INGRESS_HOST=$(kubectl get ingress chatwoot-ingress -n chatwoot -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
if [ "${INGRESS_HOST}" = "support.keybuzz.io" ]; then
    log_success "Ingress configuré pour support.keybuzz.io"
    kubectl get ingress chatwoot-ingress -n chatwoot
else
    log_error "Ingress non configuré correctement (host: ${INGRESS_HOST})"
fi

# 6. Test de connectivité interne
log_info "Test de connectivité interne..."
if kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- sh -c 'curl -sS -o /dev/null -w "%{http_code}" http://chatwoot-web.chatwoot.svc.cluster.local:3000' 2>&1 | grep -q "200\|302\|301"; then
    log_success "Service chatwoot-web accessible en interne"
else
    log_warning "Service chatwoot-web peut ne pas être encore prêt (normal si les pods viennent de démarrer)"
fi

echo ""
log_success "✅ Tests terminés"
echo ""

