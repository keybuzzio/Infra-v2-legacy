#!/usr/bin/env bash
#
# Diagnostic complet du 504 Gateway Timeout
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║    Diagnostic 504 Gateway Timeout - support.keybuzz.io           ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

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
    echo -e "${YELLOW}[⚠]${NC} $1"
}

echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 1. Vérification Service chatwoot-web ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

SVC_PORT=$(kubectl get svc chatwoot-web -n chatwoot -o jsonpath='{.spec.ports[0].port}')
SVC_TARGETPORT=$(kubectl get svc chatwoot-web -n chatwoot -o jsonpath='{.spec.ports[0].targetPort}')

log_info "Service port: ${SVC_PORT}"
log_info "Service targetPort: ${SVC_TARGETPORT}"

if [ "${SVC_PORT}" = "3000" ] && [ "${SVC_TARGETPORT}" = "3000" ]; then
    log_success "Service correctement configuré (3000 → 3000)"
else
    log_error "Service mal configuré ! Attendu: 3000 → 3000, Actuel: ${SVC_PORT} → ${SVC_TARGETPORT}"
    echo "Correction nécessaire..."
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 2. Vérification pods web (port 3000) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

POD=$(kubectl get pods -n chatwoot -l app=chatwoot,component=web -o jsonpath='{.items[0].metadata.name}')
log_info "Pod testé: ${POD}"

echo ""
log_info "Vérification port 3000..."
if kubectl exec -n chatwoot "${POD}" -- sh -c 'netstat -tlnp 2>/dev/null | grep 3000 || ss -tlnp 2>/dev/null | grep 3000' 2>/dev/null; then
    log_success "Port 3000 écouté"
else
    log_warning "Port 3000 non détecté avec netstat/ss (peut être normal si process non listé)"
fi

echo ""
log_info "Test depuis le pod lui-même..."
if kubectl exec -n chatwoot "${POD}" -- sh -c 'curl -sS -m 5 http://127.0.0.1:3000 2>&1 | head -3' 2>/dev/null | grep -q "html\|Chatwoot"; then
    log_success "Pod répond sur 3000"
else
    log_error "Pod ne répond pas sur 3000"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 3. Test Service en interne ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Test depuis un pod curl..."
kubectl run -n chatwoot curl-test-504 --image=curlimages/curl --rm -i --restart=Never -- \
    sh -c "curl -v -m 5 http://chatwoot-web.chatwoot.svc.cluster.local:3000 2>&1" | head -40

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 4. Vérification Ingress ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

INGRESS_PORT=$(kubectl get ingress chatwoot-ingress -n chatwoot -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
INGRESS_SVC=$(kubectl get ingress chatwoot-ingress -n chatwoot -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')

log_info "Ingress service: ${INGRESS_SVC}"
log_info "Ingress port: ${INGRESS_PORT}"

if [ "${INGRESS_PORT}" = "3000" ] && [ "${INGRESS_SVC}" = "chatwoot-web" ]; then
    log_success "Ingress correctement configuré (chatwoot-web:3000)"
else
    log_error "Ingress mal configuré ! Attendu: chatwoot-web:3000, Actuel: ${INGRESS_SVC}:${INGRESS_PORT}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 5. Test Ingress depuis un nœud ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Test depuis k8s-master-01..."
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@10.0.0.100 'curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 5 2>&1' | head -30; then
    log_info "Test Ingress effectué"
else
    log_warning "Test Ingress échoué ou timeout"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 6. Logs NGINX Ingress ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Dernières requêtes avec support/504/timeout..."
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --tail=100 2>&1 | \
    grep -i "support\|504\|timeout\|chatwoot" | tail -20 || echo "Aucune erreur récente"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ RÉSUMÉ ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "Service: ${SVC_PORT} → ${SVC_TARGETPORT}"
echo "Ingress: ${INGRESS_SVC}:${INGRESS_PORT}"
echo "Pods: $(kubectl get pods -n chatwoot -l app=chatwoot,component=web --no-headers | wc -l) Running"

