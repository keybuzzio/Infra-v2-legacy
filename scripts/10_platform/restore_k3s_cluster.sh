#!/usr/bin/env bash
#
# restore_k3s_cluster.sh - Restauration Temporaire du Cluster K3s
#
# Ce script restaure l'accès au cluster K3s pour permettre l'export des configurations
# avant migration vers Kubespray + Calico IPIP.
#
# Usage:
#   ./restore_k3s_cluster.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH aux masters K3s
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
echo " [KeyBuzz] Restauration Temporaire du Cluster K3s"
echo "=============================================================="
echo ""
log_warning "⚠️  Objectif : Restaurer l'accès au cluster pour exporter les configurations"
log_warning "⚠️  Le réseau overlay restera cassé (normal, temporaire)"
echo ""

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

# ============================================================
# ÉTAPE 1 : Vérifier l'état des Masters
# ============================================================
echo "=============================================================="
log_info "ÉTAPE 1 : Vérification de l'état des Masters"
echo "=============================================================="
echo ""

for i in "${!K3S_MASTER_IPS[@]}"; do
    MASTER_IP_CURRENT="${K3S_MASTER_IPS[$i]}"
    MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "Vérification de ${MASTER_HOSTNAME} (${MASTER_IP_CURRENT})..."
    
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP_CURRENT}" "systemctl is-active k3s" > /dev/null 2>&1; then
        log_success "  K3s est actif"
    else
        log_warning "  K3s n'est pas actif, redémarrage nécessaire"
    fi
done

# ============================================================
# ÉTAPE 2 : Réactiver Flannel
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 2 : Réactivation de Flannel"
echo "=============================================================="
echo ""

log_warning "Réactivation de Flannel (même si VXLAN ne fonctionnera pas)"
log_warning "Objectif : Restaurer l'accès au cluster pour export"

for i in "${!K3S_MASTER_IPS[@]}"; do
    MASTER_IP_CURRENT="${K3S_MASTER_IPS[$i]}"
    MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "Configuration de ${MASTER_HOSTNAME} (${MASTER_IP_CURRENT})..."
    
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP_CURRENT}" "cat > /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: vxlan
disable-network-policy: false
EOF
"
    
    log_success "  Configuration Flannel restaurée sur ${MASTER_HOSTNAME}"
done

# ============================================================
# ÉTAPE 3 : Redémarrer K3s
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 3 : Redémarrage de K3s"
echo "=============================================================="
echo ""

log_warning "Redémarrage de K3s sur tous les masters..."

for i in "${!K3S_MASTER_IPS[@]}"; do
    MASTER_IP_CURRENT="${K3S_MASTER_IPS[$i]}"
    MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[$i]}"
    
    log_info "Redémarrage de K3s sur ${MASTER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP_CURRENT}" "systemctl restart k3s" || log_warning "  Redémarrage peut avoir échoué, continuons..."
done

log_info "Attente de la stabilisation du cluster (90 secondes)..."
sleep 90

# ============================================================
# ÉTAPE 4 : Nettoyer les Interfaces Cilium
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 4 : Nettoyage des Interfaces Cilium"
echo "=============================================================="
echo ""

# Trouver tous les nœuds K3s
declare -a K3S_NODES=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_NODES+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

log_info "Nettoyage des interfaces Cilium sur ${#K3S_NODES[@]} nœuds..."

for node_ip in "${K3S_NODES[@]}"; do
    log_info "Nettoyage sur ${node_ip}..."
    ssh ${SSH_KEY_OPTS} "root@${node_ip}" "ip link delete cilium_vxlan 2>/dev/null || true; ip link delete cilium_host 2>/dev/null || true; echo OK" || log_warning "  Nettoyage peut avoir échoué"
done

log_success "Interfaces Cilium nettoyées"

# ============================================================
# ÉTAPE 5 : Vérifier l'Accès au Cluster
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 5 : Vérification de l'Accès au Cluster"
echo "=============================================================="
echo ""

MASTER_IP="${K3S_MASTER_IPS[0]}"
log_info "Utilisation du master: ${MASTER_IP} pour les commandes kubectl"

# Vérifier la connectivité
log_info "Vérification de la connectivité au cluster K3s..."
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

# Afficher l'état du cluster
log_info "État du cluster :"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes"
echo ""
log_info "Pods système :"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n kube-system | head -10"

# ============================================================
# Résumé Final
# ============================================================
echo ""
echo "=============================================================="
log_success "✅ Restauration Terminée"
echo "=============================================================="
echo ""
log_info "Résumé :"
log_info "  ✓ Flannel réactivé sur tous les masters"
log_info "  ✓ K3s redémarré"
log_info "  ✓ Interfaces Cilium nettoyées"
log_info "  ✓ Cluster accessible"
echo ""
log_warning "⚠️  Limitations :"
log_info "  - Réseau overlay cassé (normal, temporaire)"
log_info "  - Services ClusterIP non accessibles"
log_info "  - DNS non fonctionnel"
log_info "  - Pod-to-Pod non fonctionnel"
echo ""
log_info "📋 Prochaines Étapes :"
log_info "  1. Exporter les manifests : kubectl get all -A -o yaml > manifests.yaml"
log_info "  2. Exporter les ConfigMaps : kubectl get configmaps -A -o yaml > configmaps.yaml"
log_info "  3. Exporter les Secrets : kubectl get secrets -A -o yaml > secrets.yaml"
log_info "  4. Passer à Phase 2 : Installation Kubespray"
echo ""

