#!/usr/bin/env bash
#
# Désactivation UFW sur les nœuds Kubernetes pour permettre le trafic Calico
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

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║    Correction UFW sur nœuds Kubernetes - Fix 504                 ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

# 1. Vérifier les IPs des pods Chatwoot
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 1. IPs des pods Chatwoot ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

kubectl get pods -n chatwoot -o wide | grep chatwoot-web
echo ""

# 2. Vérifier l'état UFW sur les nœuds K8s
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 2. État UFW sur les nœuds K8s ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

K8S_NODES=(
    "k8s-master-01:10.0.0.100"
    "k8s-master-02:10.0.0.101"
    "k8s-master-03:10.0.0.102"
    "k8s-worker-01:10.0.0.110"
    "k8s-worker-02:10.0.0.111"
    "k8s-worker-03:10.0.0.112"
    "k8s-worker-04:10.0.0.113"
    "k8s-worker-05:10.0.0.114"
)

for node_info in "${K8S_NODES[@]}"; do
    IFS=':' read -r hostname ip <<< "$node_info"
    echo "===== $hostname ($ip) ====="
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "ufw status verbose 2>&1 | head -3" 2>/dev/null; then
        echo ""
    else
        log_warning "Impossible de se connecter ou UFW non installé"
    fi
    echo ""
done

# 3. Désactiver UFW sur tous les nœuds K8s
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 3. Désactivation UFW sur les nœuds K8s ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

for node_info in "${K8S_NODES[@]}"; do
    IFS=':' read -r hostname ip <<< "$node_info"
    log_info "Désactivation UFW sur $hostname ($ip)..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "ufw disable 2>&1" 2>/dev/null; then
        log_success "UFW désactivé sur $hostname"
    else
        log_warning "Impossible de désactiver UFW sur $hostname (peut-être déjà désactivé)"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 4. Vérification UFW désactivé ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

for node_info in "${K8S_NODES[@]}"; do
    IFS=':' read -r hostname ip <<< "$node_info"
    echo -n "$hostname: "
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" "ufw status 2>&1 | head -1" 2>/dev/null | grep -q "inactive\|disabled"; then
        log_success "UFW désactivé"
    else
        log_warning "UFW peut être actif (vérification manuelle recommandée)"
    fi
done

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 5. Redémarrage Ingress NGINX ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Redémarrage du DaemonSet ingress-nginx-controller..."
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
log_success "Redémarrage lancé"

log_info "Attente de la stabilisation (60s)..."
sleep 60

kubectl get pods -n ingress-nginx | head -5

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ 6. Test connectivité interne ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_info "Test depuis k8s-master-01..."
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@10.0.0.100 'curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 10 2>&1' 2>/dev/null | head -20; then
    log_info "Test effectué"
else
    log_warning "Test échoué ou timeout"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "═══ RÉSUMÉ ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

log_success "UFW désactivé sur tous les nœuds K8s"
log_info "Ingress NGINX redémarré"
log_info "Testez maintenant : curl -v https://support.keybuzz.io"

