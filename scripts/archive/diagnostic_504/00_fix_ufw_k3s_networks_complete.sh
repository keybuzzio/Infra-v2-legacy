#!/usr/bin/env bash
#
# 00_fix_ufw_k3s_networks_complete.sh - Correction complète UFW pour K3s
#
# Ce script corrige la configuration UFW sur tous les nœuds K3s pour permettre
# la communication entre pods et l'accès aux services ClusterIP.
#
# Basé sur l'ancien script 01_fix_ufw_k3s_networks.sh
#
# Usage:
#   ./00_fix_ufw_k3s_networks_complete.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH aux nœuds K3s

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

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

echo "=============================================================="
echo " [KeyBuzz] Correction UFW pour K3s - Réseaux Internes"
echo "=============================================================="
echo ""
echo "Fichier d'inventaire : ${TSV_FILE}"
echo ""

# Vérifier que servers.tsv existe
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable : ${TSV_FILE}"
    exit 1
fi

echo "Problème identifié :"
echo "  → Les pods K3s (10.42.0.0/16) ne peuvent pas communiquer"
echo "  → Les services ClusterIP (10.43.0.0/16) ne sont pas accessibles"
echo "  → UFW bloque les réseaux internes K3s"
echo ""
echo "Solution :"
echo "  → Autoriser 10.42.0.0/16 (pods) et 10.43.0.0/16 (services)"
echo "  → Autoriser les interfaces Flannel (flannel.1, cni0)"
echo "  → Autoriser les ports K3s (8472/udp, 10250/tcp)"
echo ""

read -p "Continuer ? (yes/NO) : " confirm
if [[ "${confirm}" != "yes" ]]; then
    echo "Annulé"
    exit 0
fi

echo ""
echo "=============================================================="
echo " Correction UFW sur les nœuds K3s"
echo "=============================================================="
echo ""

# Liste des nœuds K3s
K3S_NODES=(
    "k3s-master-01"
    "k3s-master-02"
    "k3s-master-03"
    "k3s-worker-01"
    "k3s-worker-02"
    "k3s-worker-03"
    "k3s-worker-04"
    "k3s-worker-05"
)

SUCCESS=0
FAIL=0

for node in "${K3S_NODES[@]}"; do
    # Récupérer l'IP privée du nœud (colonne 4 = IP_PRIVEE)
    # Essayer d'abord avec la colonne 4, puis colonne 3 si échec
    ip=$(awk -F'\t' -v h="$node" '$2==h {print $4}' "${TSV_FILE}" 2>/dev/null)
    if [[ -z "$ip" ]]; then
        ip=$(awk -F'\t' -v h="$node" '$2==h {print $3}' "${TSV_FILE}" 2>/dev/null)
    fi
    
    if [[ -z "$ip" ]]; then
        log_warning "$node : IP introuvable dans servers.tsv"
        ((FAIL++))
        continue
    fi
    
    log_info "Configuration $node ($ip)..."
    
    # Configurer UFW sur le nœud
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" bash <<'EOF'
set +u

# Fonction pour ajouter une règle UFW (idempotente)
add_ufw_rule() {
    local rule="$1"
    local comment="$2"
    
    # Vérifier si la règle existe déjà
    if ! ufw status numbered | grep -q "$comment"; then
        ufw allow $rule comment "$comment" >/dev/null 2>&1 || true
        echo "  ✓ Règle ajoutée : $comment"
    else
        echo "  ℹ️  Règle existe déjà : $comment"
    fi
}

# Autoriser les réseaux K3s
add_ufw_rule "from 10.42.0.0/16 to any" "K3s Pod Network (Flannel VXLAN)"
add_ufw_rule "from 10.43.0.0/16 to any" "K3s Service Network (ClusterIP)"

# Autoriser les interfaces Flannel
add_ufw_rule "in on flannel.1" "K3s Flannel interface"
add_ufw_rule "out on flannel.1" "K3s Flannel interface"
add_ufw_rule "in on cni0" "K3s CNI interface"
add_ufw_rule "out on cni0" "K3s CNI interface"

# Autoriser les ports K3s (si pas déjà fait)
add_ufw_rule "8472/udp" "K3s flannel VXLAN"
add_ufw_rule "10250/tcp" "K3s kubelet"

# Autoriser le réseau Hetzner privé (si pas déjà fait)
add_ufw_rule "from 10.0.0.0/16 to any" "Hetzner Private Network"

# Recharger UFW SANS reset (pour ne pas couper SSH)
ufw reload >/dev/null 2>&1 || true

echo "  ✓ UFW rechargé"

# Vérifier
echo "  → Règles UFW K3s :"
ufw status | grep -E "10.42|10.43|flannel|cni0|8472|10250" | head -10 || echo "  (aucune règle trouvée)"
EOF
    then
        log_success "$node corrigé"
        ((SUCCESS++))
    else
        log_error "$node : échec de la configuration"
        ((FAIL++))
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
log_success "Nœuds corrigés : $SUCCESS / ${#K3S_NODES[@]}"
if [[ $FAIL -gt 0 ]]; then
    log_error "Nœuds en échec : $FAIL / ${#K3S_NODES[@]}"
fi
echo ""

# Vérification sur un worker
WORKER_IP=$(awk -F'\t' '$2=="k3s-worker-01" {print $4}' "${TSV_FILE}" 2>/dev/null || echo "")

if [[ -n "$WORKER_IP" ]]; then
    echo "Vérification UFW sur k3s-worker-01 ($WORKER_IP):"
    ssh -o StrictHostKeyChecking=no root@"$WORKER_IP" "ufw status | grep -E '10.42|10.43|flannel|cni0' | head -10" || echo "Impossible de vérifier"
    echo ""
fi

if [[ $FAIL -eq 0 ]]; then
    echo "=============================================================="
    log_success "✅ UFW corrigé sur tous les nœuds K3s"
    echo "=============================================================="
    echo ""
    echo "Réseaux autorisés :"
    echo "  ✓ 10.0.0.0/16  (Hetzner privé)"
    echo "  ✓ 10.42.0.0/16 (K3s pods)"
    echo "  ✓ 10.43.0.0/16 (K3s services)"
    echo "  ✓ Interfaces Flannel (flannel.1, cni0)"
    echo "  ✓ Ports K3s (8472/udp, 10250/tcp)"
    echo ""
    echo "Prochaines étapes :"
    echo "  1. Tester la connectivité :"
    echo "     kubectl run test-curl --image=curlimages/curl:latest --rm -i --restart=Never -- curl -s http://10.43.38.57/"
    echo "  2. Redémarrer les pods si nécessaire :"
    echo "     kubectl rollout restart deployment -n keybuzz"
    echo ""
else
    echo "=============================================================="
    log_warning "⚠️  Certains nœuds ont échoué"
    echo "=============================================================="
    echo ""
    echo "Vérifiez l'accès SSH aux nœuds en échec."
    echo ""
fi

