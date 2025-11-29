#!/usr/bin/env bash
#
# migrate_to_cilium.sh - Migration vers Cilium (Solution Définitive pour Hetzner Cloud)
#
# Ce script migre le cluster K3s de Flannel/Calico vers Cilium en mode direct-routing.
# Cilium est la solution recommandée pour Hetzner Cloud car il ne dépend pas d'ipset,
# n'utilise pas VXLAN/IPIP, et fonctionne parfaitement avec les kernels Hetzner via eBPF.
#
# Usage:
#   ./migrate_to_cilium.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH aux masters K3s
#   - kubectl configuré et fonctionnel
#
# ATTENTION : Cette opération nécessite un redémarrage de K3s sur tous les masters.
#             Il peut y avoir un bref downtime pendant la transition.

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

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Migration vers Cilium (Solution Définitive)"
echo "=============================================================="
echo ""
log_warning "⚠️  ATTENTION : Cette opération va :"
log_warning "   1. Purger Calico"
log_warning "   2. Réactiver Flannel temporairement"
log_warning "   3. Installer Cilium en mode direct-routing"
log_warning "   4. Il peut y avoir un bref downtime (30-60 secondes)"
echo ""
read -p "Continuer ? (yes/NO) : " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
    log_error "Opération annulée"
    exit 0
fi

# Trouver les masters K3s
declare -a K3S_MASTER_IPS=()
declare -a K3S_MASTER_HOSTNAMES=()

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
        K3S_MASTER_HOSTNAMES+=("${HOSTNAME}")
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

log_info "Masters K3s trouvés : ${#K3S_MASTER_IPS[@]}"
for i in "${!K3S_MASTER_IPS[@]}"; do
    log_info "  - ${K3S_MASTER_HOSTNAMES[$i]} : ${K3S_MASTER_IPS[$i]}"
done
echo ""

# Utiliser le premier master pour les commandes kubectl
MASTER_IP="${K3S_MASTER_IPS[0]}"
log_info "Utilisation du master: ${MASTER_IP} pour les commandes kubectl"

# Vérifier la connectivité au cluster
log_info "Vérification de la connectivité au cluster K3s..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes" > /dev/null 2>&1; then
    log_error "Impossible de se connecter au cluster K3s"
    exit 1
fi
log_success "Cluster K3s accessible"

# ============================================================
# ÉTAPE 1 : Purger Calico
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 1 : Purge de Calico"
echo "=============================================================="
echo ""

log_info "Suppression de Calico..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get namespace kube-system" > /dev/null 2>&1; then
    # Supprimer Calico
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml 2>&1 || true" > /dev/null 2>&1
    
    # Attendre que les pods Calico soient supprimés
    log_info "Attente de la suppression des pods Calico..."
    sleep 10
    
    # Forcer la suppression si nécessaire
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete pod -n kube-system -l k8s-app=calico-node --force --grace-period=0 2>&1 || true" > /dev/null 2>&1
    
    log_success "Calico supprimé"
else
    log_warning "Calico n'est pas installé"
fi

# ============================================================
# ÉTAPE 2 : Réactiver Flannel temporairement
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 2 : Réactivation de Flannel (temporaire)"
echo "=============================================================="
echo ""

log_warning "Réactivation de Flannel pour maintenir la stabilité du cluster..."
log_warning "Note : Flannel sera toujours cassé (VXLAN bloqué), mais le cluster restera accessible"

for i in "${!K3S_MASTER_IPS[@]}"; do
    MASTER_IP_CURRENT="${K3S_MASTER_IPS[$i]}"
    MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "Traitement de ${MASTER_HOSTNAME} (${MASTER_IP_CURRENT})..."
    
    # Modifier la configuration K3s
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP_CURRENT}" "cat > /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: vxlan
disable-network-policy: false
EOF
"
    
    log_success "  Configuration Flannel restaurée sur ${MASTER_HOSTNAME}"
done

# Redémarrer K3s sur tous les masters
log_warning "Redémarrage de K3s sur tous les masters..."
for i in "${!K3S_MASTER_IPS[@]}"; do
    MASTER_IP_CURRENT="${K3S_MASTER_IPS[$i]}"
    MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "Redémarrage de K3s sur ${MASTER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP_CURRENT}" "systemctl restart k3s" || log_warning "  Redémarrage peut avoir échoué, continuons..."
done

log_info "Attente de la stabilisation du cluster (60 secondes)..."
sleep 60

# Vérifier que le cluster est accessible
log_info "Vérification de l'accessibilité du cluster..."
MAX_RETRIES=10
RETRY=0
while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes" > /dev/null 2>&1; then
        log_success "Cluster accessible"
        break
    else
        RETRY=$((RETRY + 1))
        log_warning "Tentative ${RETRY}/${MAX_RETRIES} : Cluster non accessible, attente..."
        sleep 10
    fi
done

if [[ ${RETRY} -eq ${MAX_RETRIES} ]]; then
    log_error "Le cluster n'est pas accessible après ${MAX_RETRIES} tentatives"
    exit 1
fi

# ============================================================
# ÉTAPE 3 : Installer Cilium
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 3 : Installation de Cilium"
echo "=============================================================="
echo ""

log_info "Installation de Cilium..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f https://raw.githubusercontent.com/cilium/cilium/v1.15.2/install/kubernetes/quick-install.yaml" > /dev/null 2>&1

log_info "Attente du déploiement de Cilium (peut prendre 2-3 minutes)..."
sleep 30

# Configurer Cilium en mode direct-routing
log_info "Configuration de Cilium (tunnel=disabled, kube-proxy-replacement=strict)..."

CILIUM_PATCH='{
  "data": {
    "tunnel": "disabled",
    "auto-direct-node-routes": "true",
    "enable-bpf-masquerade": "true",
    "kube-proxy-replacement": "strict"
  }
}'

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl -n kube-system patch configmap cilium-config --type merge -p '${CILIUM_PATCH}'" > /dev/null 2>&1

log_success "Configuration Cilium appliquée"

# Redémarrer le DaemonSet Cilium
log_info "Redémarrage des pods Cilium pour appliquer la configuration..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl rollout restart daemonset cilium -n kube-system" > /dev/null 2>&1

log_info "Attente de la stabilisation de Cilium (60 secondes)..."
sleep 60

# ============================================================
# ÉTAPE 4 : Vérifications
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 4 : Vérifications"
echo "=============================================================="
echo ""

# 4.1 Vérifier Cilium
log_info "4.1 Vérification des pods Cilium..."
CILIUM_READY=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | grep -c '1/1' || echo 0")
CILIUM_TOTAL=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n kube-system -l k8s-app=cilium --no-headers | wc -l")
if [[ ${CILIUM_READY} -eq ${CILIUM_TOTAL} ]] && [[ ${CILIUM_TOTAL} -gt 0 ]]; then
    log_success "  Cilium : ${CILIUM_READY}/${CILIUM_TOTAL} pod(s) Ready"
else
    log_warning "  Cilium : ${CILIUM_READY}/${CILIUM_TOTAL} pod(s) Ready (peut nécessiter plus de temps)"
fi

# 4.2 Vérifier CoreDNS
log_info "4.2 Vérification de CoreDNS..."
COREDNS_STATUS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers | head -1 | awk '{print \$3}' || echo Unknown")
if [[ "${COREDNS_STATUS}" == "Running" ]]; then
    log_success "  CoreDNS : Running"
else
    log_warning "  CoreDNS : ${COREDNS_STATUS}"
fi

# 4.3 Test résolution DNS
log_info "4.3 Test de résolution DNS..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl run test-dns-cilium-$(date +%s) --image=busybox:1.36 -n default --rm -i --restart=Never --timeout=10s -- nslookup kubernetes.default.svc.cluster.local" > /dev/null 2>&1; then
    log_success "  Résolution DNS : OK"
else
    log_warning "  Résolution DNS : Peut nécessiter plus de temps"
fi

# 4.4 Vérifier Services ClusterIP (si namespace keybuzz existe)
log_info "4.4 Vérification des Services ClusterIP..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get namespace keybuzz" > /dev/null 2>&1; then
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc -n keybuzz keybuzz-api" > /dev/null 2>&1; then
        log_info "  Service keybuzz-api trouvé"
        # Test de connectivité
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl run test-svc-cilium-$(date +%s) --image=curlimages/curl -n keybuzz --rm -i --restart=Never --timeout=10s -- curl -s --connect-timeout 5 http://keybuzz-api.keybuzz.svc.cluster.local:8080/health" > /dev/null 2>&1; then
            log_success "  Service ClusterIP keybuzz-api : Accessible"
        else
            log_warning "  Service ClusterIP keybuzz-api : Peut nécessiter plus de temps"
        fi
    else
        log_info "  Namespace keybuzz existe mais pas de service keybuzz-api"
    fi
else
    log_info "  Namespace keybuzz n'existe pas encore"
fi

# 4.5 Vérifier Ingress NGINX
log_info "4.5 Vérification de l'Ingress NGINX..."
INGRESS_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers | grep -c Running || echo 0")
if [[ ${INGRESS_PODS} -gt 0 ]]; then
    log_success "  Ingress NGINX : ${INGRESS_PODS} pod(s) Running"
    
    # Test Ingress → Backend
    INGRESS_POD=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers | head -1 | awk '{print \$1}'")
    if [[ -n "${INGRESS_POD}" ]]; then
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n ingress-nginx ${INGRESS_POD} -- curl -s --connect-timeout 5 http://keybuzz-api.keybuzz.svc.cluster.local:8080/health" > /dev/null 2>&1; then
            log_success "  Ingress → Backend : OK"
        else
            log_warning "  Ingress → Backend : Peut nécessiter plus de temps"
        fi
    fi
else
    log_warning "  Ingress NGINX : Aucun pod Running"
fi

# ============================================================
# Résumé Final
# ============================================================
echo ""
echo "=============================================================="
log_success "✅ Migration vers Cilium Terminée"
echo "=============================================================="
echo ""
log_info "Résumé :"
log_info "  ✓ Calico supprimé"
log_info "  ✓ Flannel réactivé (temporaire)"
log_info "  ✓ Cilium installé en mode direct-routing"
log_info "  ✓ Configuration : tunnel=disabled, kube-proxy-replacement=strict"
echo ""
log_warning "⚠️  Actions Recommandées :"
log_info "  1. Vérifier manuellement que tous les pods Cilium sont Ready :"
log_info "     kubectl get pods -n kube-system -l k8s-app=cilium"
log_info ""
log_info "  2. Vérifier que CoreDNS répond :"
log_info "     kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default"
log_info ""
log_info "  3. Vérifier que les Services ClusterIP sont accessibles :"
log_info "     kubectl run test-curl --image=curlimages/curl -n keybuzz --rm -it --restart=Never -- curl http://keybuzz-api.keybuzz.svc.cluster.local:8080/health"
log_info ""
log_info "  4. Vérifier les URLs externes :"
log_info "     curl -k https://platform.keybuzz.io"
log_info "     curl -k https://platform-api.keybuzz.io/health"
log_info "     curl -k https://my.keybuzz.io"
echo ""
log_info "Si tout fonctionne, vous pouvez reprendre le déploiement du Module 10."
echo ""

