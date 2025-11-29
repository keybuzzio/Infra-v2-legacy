#!/usr/bin/env bash
#
# Diagnostic 504 Gateway Timeout - Load Balancer Hetzner
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║    Diagnostic 504 Gateway Timeout - support.keybuzz.io          ║"
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
echo "═══ 1. Vérification des Pods Chatwoot ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get pods -n chatwoot

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 2. Vérification de l'Ingress ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get ingress -n chatwoot -o yaml | grep -A 10 "spec:"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 3. Test /healthz sur les nœuds Kubernetes ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

NODES=(
    "10.0.0.100:k8s-master-01"
    "10.0.0.101:k8s-master-02"
    "10.0.0.102:k8s-master-03"
    "10.0.0.110:k8s-worker-01"
    "10.0.0.111:k8s-worker-02"
    "10.0.0.112:k8s-worker-03"
    "10.0.0.113:k8s-worker-04"
    "10.0.0.114:k8s-worker-05"
)

for node_info in "${NODES[@]}"; do
    IFS=':' read -r ip name <<< "$node_info"
    echo -n "Testing $name ($ip:80/healthz) ... "
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=3 root@"$ip" "curl -sS -m 2 http://localhost/healthz" > /dev/null 2>&1; then
        log_success "OK"
    else
        log_error "FAIL"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 4. Test direct vers Chatwoot (depuis un pod) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Test depuis un pod curl..."
kubectl run test-curl-504 --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- \
    curl -sS -m 5 -H "Host: support.keybuzz.io" http://chatwoot-web.chatwoot.svc.cluster.local:3000 2>&1 | head -10

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 5. Logs NGINX Ingress (dernières requêtes) ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=20 | grep -i "support\|chatwoot\|504\|timeout" || echo "Aucune requête récente pour support.keybuzz.io"

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 6. Configuration requise Load Balancer Hetzner ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "IPs publiques des Load Balancers Hetzner :"
echo "  - LB 1 : 49.13.42.76"
echo "  - LB 2 : 138.199.132.240"
echo ""
log_info "Backends à configurer (IPs privées des nœuds Kubernetes) :"
echo ""
echo "  Service HTTP (Port 80) :"
for node_info in "${NODES[@]}"; do
    IFS=':' read -r ip name <<< "$node_info"
    echo "    - $ip:80 ($name)"
done
echo ""
echo "  Service HTTPS (Port 443) :"
for node_info in "${NODES[@]}"; do
    IFS=':' read -r ip name <<< "$node_info"
    echo "    - $ip:443 ($name)"
done
echo ""
log_info "Health Check :"
echo "  - Type : HTTP"
echo "  - Path : /healthz"
echo "  - Port : 80 (pour les deux services HTTP et HTTPS)"
echo "  - Interval : 10s"
echo "  - Timeout : 5s"
echo "  - Retries : 3"
echo ""
log_warning "IMPORTANT :"
echo "  - Les IPs 49.13.42.76 et 138.199.132.240 sont les IPs PUBLIQUES des LB"
echo "  - Les backends sont les IPs PRIVÉES des nœuds (10.0.0.100-102, 10.0.0.110-114)"
echo "  - Le DNS support.keybuzz.io doit pointer vers l'IP PUBLIQUE du LB"
echo "  - Le health check peut être HTTP sur le port 80 même pour le service HTTPS 443"

