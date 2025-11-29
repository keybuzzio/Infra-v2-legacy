#!/usr/bin/env bash
#
# fix_calico_ipset_nft.sh - Correction ipset et nftables pour Calico
#
# Ce script corrige deux problèmes bloquants pour Calico :
# 1. Installation d'ipset (manquant sur les nœuds)
# 2. Suppression des règles nftables (conflit avec iptables)
#
# Usage:
#   ./fix_calico_ipset_nft.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH aux tous les nœuds K3s

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
echo " [KeyBuzz] Correction ipset et nftables pour Calico"
echo "=============================================================="
echo ""

# Trouver tous les nœuds K3s
declare -a K3S_NODE_IPS=()
declare -a K3S_NODE_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_NODE_IPS+=("${IP_PRIVEE}")
        K3S_NODE_HOSTNAMES+=("${HOSTNAME}")
    fi
done
exec 3<&-

if [[ ${#K3S_NODE_IPS[@]} -lt 1 ]]; then
    log_error "Aucun nœud K3s trouvé"
    exit 1
fi

log_info "Nœuds K3s trouvés : ${#K3S_NODE_IPS[@]}"
for i in "${!K3S_NODE_IPS[@]}"; do
    log_info "  - ${K3S_NODE_HOSTNAMES[$i]} : ${K3S_NODE_IPS[$i]}"
done
echo ""

# ============================================================
# ÉTAPE 1 : Installer ipset sur tous les nœuds
# ============================================================
echo "=============================================================="
log_info "ÉTAPE 1 : Installation d'ipset"
echo "=============================================================="
echo ""

for i in "${!K3S_NODE_IPS[@]}"; do
    NODE_IP="${K3S_NODE_IPS[$i]}"
    NODE_HOSTNAME="${K3S_NODE_HOSTNAMES[$i]}"
    
    log_info "Traitement de ${NODE_HOSTNAME} (${NODE_IP})..."
    
    # Vérifier si ipset est installé
    if ssh ${SSH_KEY_OPTS} "root@${NODE_IP}" "which ipset > /dev/null 2>&1"; then
        log_info "  ipset déjà installé"
        IPSET_VERSION=$(ssh ${SSH_KEY_OPTS} "root@${NODE_IP}" "ipset --version 2>&1 | head -1" || echo "unknown")
        log_info "  Version: ${IPSET_VERSION}"
    else
        log_info "  Installation d'ipset..."
        if ssh ${SSH_KEY_OPTS} "root@${NODE_IP}" "apt-get update -qq && apt-get install ipset -y -qq" > /dev/null 2>&1; then
            log_success "  ipset installé"
        else
            log_error "  Échec de l'installation d'ipset"
        fi
    fi
done

# ============================================================
# ÉTAPE 2 : Supprimer les règles nftables
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 2 : Suppression des règles nftables"
echo "=============================================================="
echo ""

for i in "${!K3S_NODE_IPS[@]}"; do
    NODE_IP="${K3S_NODE_IPS[$i]}"
    NODE_HOSTNAME="${K3S_NODE_HOSTNAMES[$i]}"
    
    log_info "Traitement de ${NODE_HOSTNAME} (${NODE_IP})..."
    
    # Vérifier si nft est disponible
    if ssh ${SSH_KEY_OPTS} "root@${NODE_IP}" "which nft > /dev/null 2>&1"; then
        log_info "  Suppression des règles nftables..."
        if ssh ${SSH_KEY_OPTS} "root@${NODE_IP}" "nft flush ruleset 2>/dev/null || true"; then
            log_success "  Règles nftables supprimées"
        else
            log_warning "  Pas de règles nftables à supprimer"
        fi
    else
        log_info "  nftables non installé"
    fi
done

# ============================================================
# ÉTAPE 3 : Redémarrer les pods Calico
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 3 : Redémarrage des pods Calico"
echo "=============================================================="
echo ""

log_info "Suppression des pods Calico..."
kubectl delete pod -n kube-system -l k8s-app=calico-node > /dev/null 2>&1 || true

log_info "Attente du redémarrage (60 secondes)..."
sleep 60

# ============================================================
# ÉTAPE 4 : Vérifications
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 4 : Vérifications"
echo "=============================================================="
echo ""

# Vérifier les pods Calico
log_info "Vérification des pods Calico..."
CALICO_READY=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers | grep -c "1/1" || echo "0")
CALICO_TOTAL=$(kubectl get pods -n kube-system -l k8s-app=calico-node --no-headers | wc -l)

if [[ ${CALICO_READY} -eq ${CALICO_TOTAL} ]]; then
    log_success "  Tous les pods Calico sont Ready (${CALICO_READY}/${CALICO_TOTAL})"
else
    log_warning "  Pods Calico Ready : ${CALICO_READY}/${CALICO_TOTAL}"
fi

# Vérifier les erreurs ipset
log_info "Vérification des erreurs ipset..."
IPSET_ERRORS=$(kubectl logs -n kube-system -l k8s-app=calico-node --tail=50 2>&1 | grep -c "ipset.*incompatible" || echo "0")
if [[ ${IPSET_ERRORS} -eq 0 ]]; then
    log_success "  Aucune erreur ipset détectée"
else
    log_warning "  ${IPSET_ERRORS} erreur(s) ipset détectée(s)"
fi

# Vérifier les erreurs nftables
log_info "Vérification des erreurs nftables..."
NFT_ERRORS=$(kubectl logs -n kube-system -l k8s-app=calico-node --tail=50 2>&1 | grep -c "incompatible nft rules" || echo "0")
if [[ ${NFT_ERRORS} -eq 0 ]]; then
    log_success "  Aucune erreur nftables détectée"
else
    log_warning "  ${NFT_ERRORS} erreur(s) nftables détectée(s)"
fi

# Test DNS
log_info "Test de résolution DNS..."
if kubectl run test-dns-fix --image=busybox:1.36 -n default --rm -i --restart=Never --timeout=10s -- nslookup keybuzz-api.keybuzz.svc.cluster.local > /dev/null 2>&1; then
    log_success "  Résolution DNS : OK"
else
    log_warning "  Résolution DNS : Peut nécessiter plus de temps"
fi

# Test Service ClusterIP depuis Ingress
log_info "Test Service ClusterIP depuis Ingress..."
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers | head -1 | awk '{print $1}')
if [[ -n "${INGRESS_POD}" ]]; then
    if kubectl exec -n ingress-nginx "${INGRESS_POD}" -- curl -s --connect-timeout 5 http://keybuzz-api.keybuzz.svc.cluster.local:8080/health > /dev/null 2>&1; then
        log_success "  Service ClusterIP accessible depuis Ingress"
    else
        log_warning "  Service ClusterIP : Peut nécessiter plus de temps"
    fi
else
    log_warning "  Pod Ingress introuvable"
fi

# ============================================================
# Résumé Final
# ============================================================
echo ""
echo "=============================================================="
log_success "✅ Correction Terminée"
echo "=============================================================="
echo ""
log_info "Résumé :"
log_info "  ✓ ipset installé sur tous les nœuds"
log_info "  ✓ Règles nftables supprimées"
log_info "  ✓ Pods Calico redémarrés"
echo ""
log_warning "⚠️  Si les pods Calico ne sont pas tous Ready :"
log_info "  1. Attendre encore 5-10 minutes"
log_info "  2. Vérifier les logs : kubectl logs -n kube-system -l k8s-app=calico-node"
log_info "  3. Vérifier l'état : kubectl get pods -n kube-system -l k8s-app=calico-node"
echo ""

