#!/usr/bin/env bash
#
# Fix UFW pour Calico - Autorisation réseaux K8s (10.233.0.0/16)
# Basé sur la solution K3s qui fonctionnait (10.42.0.0/16)
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
echo "║    Fix UFW pour Calico - Autorisation réseaux K8s                 ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Solution basée sur K3s (10.42.0.0/16) → K8s Calico (10.233.0.0/16)"
echo ""

# Nœuds K8s
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

echo "═══════════════════════════════════════════════════════════════════"
echo "═══ Réactivation UFW et ajout règles Calico ═══"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

for node_info in "${K8S_NODES[@]}"; do
    IFS=':' read -r hostname ip <<< "$node_info"
    log_info "Configuration UFW sur $hostname ($ip)..."
    
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@"$ip" bash <<'EOF' || log_warning "Erreur sur $hostname"
set -u

# Réactiver UFW si désactivé
if ! ufw status | grep -q "Status: active"; then
    ufw --force enable >/dev/null 2>&1 || true
    echo "  ✓ UFW réactivé"
fi

# Fonction pour ajouter une règle UFW (idempotente)
add_ufw_rule() {
    local from="$1"
    local comment="$2"
    
    # Vérifier si la règle existe déjà
    if ! ufw status | grep -q "$from"; then
        ufw allow from "$from" comment "$comment" >/dev/null 2>&1
        echo "  ✓ Règle ajoutée : $from ($comment)"
    else
        echo "  ✓ Règle existe déjà : $from"
    fi
}

echo "  → Autorisation des réseaux K8s Calico..."

# Autoriser le réseau des pods Calico (10.233.0.0/16)
add_ufw_rule "10.233.0.0/16" "K8s Calico Pod Network"

# Autoriser le réseau Hetzner privé (déjà fait normalement, mais on s'assure)
add_ufw_rule "10.0.0.0/16" "Hetzner Private Network"

# Recharger UFW
ufw reload >/dev/null 2>&1
echo "  ✓ UFW rechargé"

# Vérifier
echo "  → Règles UFW K8s :"
ufw status | grep -E "10.233|10.0.0" | head -4 || echo "  (aucune règle trouvée)"
EOF
    
    if [ $? -eq 0 ]; then
        log_success "$hostname configuré"
    else
        log_warning "$hostname : erreurs"
    fi
    echo ""
done

echo "═══════════════════════════════════════════════════════════════════"
echo -e "${GREEN}[✓]${NC} Configuration UFW terminée"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Réseaux autorisés sur tous les nœuds K8s :"
echo "  ✓ 10.0.0.0/16  (Hetzner privé)"
echo "  ✓ 10.233.0.0/16 (K8s Calico pods)"
echo ""
echo "Prochaines étapes :"
echo "  1. Redémarrer Ingress NGINX :"
echo "     kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller"
echo "  2. Attendre 2-3 minutes"
echo "  3. Tester : curl -v https://support.keybuzz.io"
echo ""

