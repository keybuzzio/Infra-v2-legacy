#!/usr/bin/env bash
#
# Diagnostic 502 Bad Gateway pour support.keybuzz.io
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║    Diagnostic 502 Bad Gateway - support.keybuzz.io               ║"
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
echo "═══ 1. État des Pods Chatwoot ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get pods -n chatwoot -o wide

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 2. Readiness/Liveness des Pods ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

for pod in $(kubectl get pods -n chatwoot -l app=chatwoot,component=web -o name); do
    pod_name=$(echo $pod | cut -d'/' -f2)
    ready=$(kubectl get pod $pod_name -n chatwoot -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    echo "  $pod_name : Ready=$ready"
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 3. Endpoints du Service ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get endpoints chatwoot-web -n chatwoot

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 4. Configuration Ingress ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get ingress chatwoot-ingress -n chatwoot -o yaml | grep -A 5 "annotations:"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 5. Test Port-Forward (direct vers pod) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Test port-forward vers chatwoot-web:3000..."
timeout 5 kubectl port-forward -n chatwoot service/chatwoot-web 3000:3000 > /dev/null 2>&1 &
PF_PID=$!
sleep 2

if curl -sS -m 3 http://localhost:3000 > /dev/null 2>&1; then
    log_success "Port-forward OK : Les pods répondent"
else
    log_error "Port-forward FAIL : Les pods ne répondent pas"
fi

kill $PF_PID 2>/dev/null || true

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 6. Logs NGINX Ingress (dernières requêtes) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=30 2>&1 | grep -E "support|chatwoot|502|500|error|upstream" | tail -10 || echo "Aucune erreur récente"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 7. Logs Pods Chatwoot (erreurs récentes) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl logs -n chatwoot --selector=app=chatwoot,component=web --tail=20 2>&1 | grep -E "Error|FATAL|Exception|Failed|500|502" | tail -10 || echo "Aucune erreur dans les logs"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 8. Recommandations ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Si vous voyez toujours un 502 :"
echo "  1. Vérifiez que tous les pods NGINX Ingress sont Running"
echo "  2. Attendez 30-60 secondes après le redémarrage des pods NGINX"
echo "  3. Testez à nouveau : curl -v https://support.keybuzz.io"
echo "  4. Vérifiez les logs NGINX en temps réel pendant une requête"
echo ""
log_info "Si le problème persiste :"
echo "  1. Redémarrez les pods Chatwoot : kubectl rollout restart deployment/chatwoot-web -n chatwoot"
echo "  2. Vérifiez la connectivité réseau entre les pods NGINX et Chatwoot"
echo "  3. Vérifiez les règles de firewall sur les nœuds Kubernetes"

