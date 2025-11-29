#!/usr/bin/env bash
#
# 09_k3s_test_healthcheck.sh - Test des healthchecks Ingress pour LB Hetzner
#
# Ce script simule exactement ce que fait le Load Balancer Hetzner :
# - Test HTTP GET sur /healthz depuis tous les nœuds
# - Vérifie que tous les nœuds répondent correctement
# - Aide à diagnostiquer les problèmes de healthcheck
#
# Usage:
#   ./09_k3s_test_healthcheck.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé
#   - Ingress NGINX opérationnel
#   - Exécuter depuis install-01

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
echo " [KeyBuzz] Module 9 - Test Healthcheck Ingress"
echo "=============================================================="
echo ""
log_info "Ce script simule les healthchecks du LB Hetzner"
log_info "Test: HTTP GET http://<node>:31695/healthz"
echo ""

# Collecter tous les nœuds K3s
declare -a K3S_NODES=()
declare -a K3S_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_NODES+=("${HOSTNAME}")
        K3S_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#K3S_IPS[@]} -lt 1 ]]; then
    log_error "Aucun nœud K3s trouvé"
    exit 1
fi

log_success "${#K3S_IPS[@]} nœuds K3s détectés"
echo ""

# Récupérer le NodePort depuis le cluster
log_info "Récupération du NodePort Ingress..."
MASTER_IP="${K3S_IPS[0]}"
NODEPORT=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.spec.ports[0].nodePort}'" 2>/dev/null || echo "31695")

if [[ -z "${NODEPORT}" ]]; then
    log_warning "Impossible de récupérer le NodePort, utilisation de 31695 par défaut"
    NODEPORT="31695"
fi

log_info "NodePort détecté: ${NODEPORT}"
echo ""

# Compteurs
HEALTHY=0
UNHEALTHY=0
declare -a UNHEALTHY_NODES=()

# Tester chaque nœud
log_info "=============================================================="
log_info "Test Healthcheck sur chaque nœud"
log_info "=============================================================="
echo ""

for i in "${!K3S_NODES[@]}"; do
    hostname="${K3S_NODES[$i]}"
    ip="${K3S_IPS[$i]}"
    
    echo "Test: ${hostname} (${ip}:${NODEPORT})"
    
    # Test depuis le nœud lui-même (simule le LB Hetzner)
    RESULT=$(ssh ${SSH_KEY_OPTS} "root@${ip}" "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:${NODEPORT}/healthz 2>/dev/null || echo '000'" || echo "000")
    
    if [[ "${RESULT}" == "200" ]]; then
        log_success "${hostname}: Healthy (HTTP ${RESULT})"
        HEALTHY=$((HEALTHY + 1))
    else
        log_error "${hostname}: Unhealthy (HTTP ${RESULT})"
        UNHEALTHY_NODES+=("${hostname} (${ip})")
        UNHEALTHY=$((UNHEALTHY + 1))
    fi
    
    echo ""
done

# Résumé
echo "=============================================================="
echo " Résumé des Tests"
echo "=============================================================="
echo ""
log_info "Nœuds testés: ${#K3S_IPS[@]}"
log_success "Healthy: ${HEALTHY}"
if [[ ${UNHEALTHY} -gt 0 ]]; then
    log_error "Unhealthy: ${UNHEALTHY}"
    echo ""
    log_warning "Nœuds Unhealthy:"
    for node in "${UNHEALTHY_NODES[@]}"; do
        echo "  - ${node}"
    done
else
    log_success "Unhealthy: 0"
fi
echo ""

# Diagnostic si problèmes
if [[ ${UNHEALTHY} -gt 0 ]]; then
    echo "=============================================================="
    log_warning "Diagnostic des problèmes"
    echo "=============================================================="
    echo ""
    
    log_info "Vérifications à effectuer:"
    echo ""
    echo "1. Vérifier les pods Ingress:"
    echo "   kubectl get pods -n ingress-nginx"
    echo ""
    echo "2. Vérifier les logs Ingress sur un nœud unhealthy:"
    echo "   kubectl logs -n ingress-nginx -l app=ingress-nginx --tail=50"
    echo ""
    echo "3. Vérifier UFW sur les nœuds unhealthy:"
    echo "   ssh root@<ip> 'ufw status | grep ${NODEPORT}'"
    echo ""
    echo "4. Tester manuellement:"
    echo "   ssh root@<ip> 'curl -v http://localhost:${NODEPORT}/healthz'"
    echo ""
    
    # Test depuis un nœud healthy vers un unhealthy
    if [[ ${HEALTHY} -gt 0 ]] && [[ ${UNHEALTHY} -gt 0 ]]; then
        HEALTHY_IP="${K3S_IPS[0]}"
        UNHEALTHY_NODE="${UNHEALTHY_NODES[0]}"
        UNHEALTHY_IP=$(echo "${UNHEALTHY_NODE}" | grep -oP '\([0-9.]+\)' | tr -d '()')
        
        if [[ -n "${UNHEALTHY_IP}" ]]; then
            log_info "Test de connectivité réseau depuis un nœud healthy..."
            echo "Test: ${HEALTHY_IP} → ${UNHEALTHY_IP}:${NODEPORT}"
            
            NETWORK_TEST=$(ssh ${SSH_KEY_OPTS} "root@${HEALTHY_IP}" "nc -zv -w 3 ${UNHEALTHY_IP} ${NODEPORT} 2>&1" || echo "FAIL")
            
            if echo "${NETWORK_TEST}" | grep -q "succeeded"; then
                log_success "Connectivité réseau OK"
            else
                log_error "Problème de connectivité réseau"
                log_warning "Vérifier UFW et les règles de pare-feu"
            fi
            echo ""
        fi
    fi
fi

# Configuration Hetzner Console
echo "=============================================================="
log_info "Configuration Hetzner Console"
echo "=============================================================="
echo ""
echo "Pour le service HTTPS (443) dans Hetzner Console:"
echo ""
echo "  Health Check:"
echo "    - Protocol: HTTP (⚠️ PAS HTTPS)"
echo "    - Port: ${NODEPORT}"
echo "    - Path: /healthz"
echo "    - Interval: 10-15 secondes"
echo "    - Timeout: 5-10 secondes"
echo "    - Retries: 3"
echo "    - Status codes: 200"
echo ""
echo "  Destination Port: ${NODEPORT} (même que HTTP)"
echo ""
echo "  Targets: Tous les ${#K3S_IPS[@]} nœuds sur le port ${NODEPORT}"
echo ""

# Résultat final
echo "=============================================================="
if [[ ${UNHEALTHY} -eq 0 ]]; then
    log_success "✅ Tous les healthchecks sont OK"
    echo "=============================================================="
    echo ""
    log_info "Le LB Hetzner devrait marquer tous les targets comme 'Healthy'"
    log_info "après configuration du healthcheck HTTPS en HTTP"
    echo ""
    exit 0
else
    log_error "❌ Certains healthchecks échouent"
    echo "=============================================================="
    echo ""
    log_warning "Corriger les problèmes avant de configurer le LB Hetzner"
    echo ""
    exit 1
fi

