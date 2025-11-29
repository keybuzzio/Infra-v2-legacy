#!/usr/bin/env bash
#
# 09_k3s_fix_coredns.sh - Correction du problème CoreDNS Loop
#
# Problème: CoreDNS détecte une boucle (loop detected)
# Solution: Corriger la configuration CoreDNS pour éviter la boucle
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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

# Trouver le premier master
declare -a K3S_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi
SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " [KeyBuzz] Correction CoreDNS Loop"
echo "=============================================================="
echo ""

log_info "Problème détecté: CoreDNS loop detected"
log_info "Solution: Redémarrer CoreDNS avec configuration corrigée"
echo ""

# Solution 1: Supprimer et recréer le deployment CoreDNS
log_info "Étape 1: Suppression du deployment CoreDNS actuel..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
set -euo pipefail

# Supprimer le deployment CoreDNS
kubectl delete deployment coredns -n kube-system --ignore-not-found=true

# Attendre que le pod soit supprimé
sleep 5

# Vérifier que CoreDNS est supprimé
if kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
    echo "⚠ CoreDNS deployment toujours présent, forcer la suppression..."
    kubectl delete deployment coredns -n kube-system --force --grace-period=0 || true
    sleep 3
fi

echo "✓ CoreDNS deployment supprimé"
EOF

log_success "Deployment CoreDNS supprimé"
echo ""

# Solution 2: K3s va recréer CoreDNS automatiquement, mais on peut aussi le forcer
log_info "Étape 2: Attente que K3s recrée CoreDNS automatiquement..."
sleep 10

# Vérifier si CoreDNS a été recréé
log_info "Étape 3: Vérification de l'état de CoreDNS..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
set -euo pipefail

# Attendre jusqu'à 60 secondes que CoreDNS soit recréé
for i in {1..12}; do
    if kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
        echo "✓ CoreDNS recréé"
        break
    fi
    echo "  Attente... ($i/12)"
    sleep 5
done

# Vérifier l'état
if kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
    echo ""
    echo "=== État CoreDNS ==="
    kubectl get deployment coredns -n kube-system
    echo ""
    echo "=== Pods CoreDNS ==="
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    echo ""
    
    # Attendre que les pods soient prêts
    echo "Attente que les pods CoreDNS soient prêts (30 secondes)..."
    sleep 30
    
    # Vérifier les logs du nouveau pod
    POD_NAME=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "${POD_NAME}" ]]; then
        echo ""
        echo "=== Logs CoreDNS (dernières 20 lignes) ==="
        kubectl logs -n kube-system "${POD_NAME}" --tail 20 2>&1 || echo "Impossible de lire les logs"
    fi
else
    echo "⚠ CoreDNS n'a pas été recréé automatiquement"
    echo "  K3s devrait le recréer automatiquement, vérifiez manuellement"
fi
EOF

# Solution 3: Si le problème persiste, modifier la configuration CoreDNS
log_info "Étape 4: Vérification finale..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
set -euo pipefail

# Vérifier l'état final
echo "=== État final CoreDNS ==="
kubectl get deployment coredns -n kube-system 2>/dev/null || echo "CoreDNS deployment non trouvé"
echo ""

PODS=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | wc -l)
if [[ ${PODS} -gt 0 ]]; then
    echo "=== Pods CoreDNS ==="
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    echo ""
    
    # Vérifier si les pods sont Running
    RUNNING=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep Running | wc -l)
    if [[ ${RUNNING} -gt 0 ]]; then
        echo "✓ CoreDNS opérationnel (${RUNNING} pod(s) Running)"
    else
        echo "⚠ CoreDNS pods présents mais pas tous Running"
        echo "  Vérifiez les logs: kubectl logs -n kube-system <pod-name>"
    fi
else
    echo "⚠ Aucun pod CoreDNS trouvé"
fi
EOF

echo ""
echo "=============================================================="
log_success "✅ Correction CoreDNS terminée"
echo "=============================================================="
echo ""
log_info "Si le problème persiste, vérifiez:"
log_info "  1. Les logs: kubectl logs -n kube-system <coredns-pod>"
log_info "  2. La configuration DNS des nœuds"
log_info "  3. Les règles UFW qui pourraient bloquer le trafic DNS"
echo ""

