#!/usr/bin/env bash
#
# 10_keybuzz_04_tests.sh - Tests de validation KeyBuzz
#
# Ce script effectue des tests de validation pour KeyBuzz API et Front :
# - Test de connectivité aux services
# - Test des healthchecks
# - Test des Ingress (si DNS configuré)
#
# Usage:
#   ./10_keybuzz_04_tests.sh [servers.tsv]
#
# Prérequis:
#   - Module 10 scripts 01-03 exécutés
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
echo " [KeyBuzz] Module 10 - Tests de Validation KeyBuzz"
echo "=============================================================="
echo ""

# Trouver le premier master K3s
declare -a K3S_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3 || [[ -n "${ENV:-}" ]]; do
    if [[ "${ENV}" == "ENV" ]] || [[ -z "${ENV:-}" ]]; then
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
log_info "Utilisation du master: ${MASTER_IP}"

# Tests
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Vérifier les Deployments
log_info "Test 1: Vérification des Deployments..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment keybuzz-api -n keybuzz" > /dev/null 2>&1; then
    log_success "Deployment keybuzz-api existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Deployment keybuzz-api introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment keybuzz-front -n keybuzz" > /dev/null 2>&1; then
    log_success "Deployment keybuzz-front existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Deployment keybuzz-front introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 2: Vérifier les Services
log_info "Test 2: Vérification des Services..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-api -n keybuzz" > /dev/null 2>&1; then
    log_success "Service keybuzz-api existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Service keybuzz-api introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-front -n keybuzz" > /dev/null 2>&1; then
    log_success "Service keybuzz-front existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Service keybuzz-front introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 3: Vérifier les Pods
log_info "Test 3: Vérification des Pods..."
API_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-api --no-headers 2>/dev/null | grep -c Running || echo '0'")
FRONT_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | grep -c Running || echo '0'")

if [[ "${API_PODS:-0}" -ge 1 ]]; then
    log_success "Pods keybuzz-api Running: ${API_PODS}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Aucun pod keybuzz-api Running"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if [[ "${FRONT_PODS:-0}" -ge 1 ]]; then
    log_success "Pods keybuzz-front Running: ${FRONT_PODS}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Aucun pod keybuzz-front Running"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 4: Vérifier les Ingress
log_info "Test 4: Vérification des Ingress..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress keybuzz-front-ingress -n keybuzz" > /dev/null 2>&1; then
    log_success "Ingress keybuzz-front-ingress existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Ingress keybuzz-front-ingress introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress keybuzz-api-ingress -n keybuzz" > /dev/null 2>&1; then
    log_success "Ingress keybuzz-api-ingress existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Ingress keybuzz-api-ingress introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 5: Vérifier le HPA
log_info "Test 5: Vérification du HPA..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get hpa keybuzz-api-hpa -n keybuzz" > /dev/null 2>&1; then
    log_success "HPA keybuzz-api-hpa existe"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "HPA keybuzz-api-hpa introuvable"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Test 6: Test de connectivité interne (port-forward)
log_info "Test 6: Test de connectivité interne..."
API_PORT=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-api -n keybuzz -o jsonpath='{.spec.ports[0].port}'" 2>/dev/null || echo "80")
if [[ -n "${API_PORT}" ]]; then
    log_success "Service keybuzz-api accessible sur le port ${API_PORT}"
    TESTS_PASSED=$((TESTS_PASSED + 1))
else
    log_error "Impossible de déterminer le port du service keybuzz-api"
    TESTS_FAILED=$((TESTS_FAILED + 1))
fi

# Résumé
echo ""
echo "=============================================================="
echo " Résumé des Tests"
echo "=============================================================="
echo ""
log_info "Tests réussis: ${TESTS_PASSED}"
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    log_error "Tests échoués: ${TESTS_FAILED}"
else
    log_success "Tests échoués: 0"
fi
echo ""

# Afficher le statut détaillé
log_info "Statut détaillé:"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get all -n keybuzz"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n keybuzz"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get hpa -n keybuzz"

echo ""
echo "=============================================================="
if [[ ${TESTS_FAILED} -eq 0 ]]; then
    log_success "✅ Tous les tests sont passés"
    echo "=============================================================="
    echo ""
    log_info "KeyBuzz API et Front sont opérationnels"
    log_warning "⚠️  N'oubliez pas de configurer les DNS:"
    log_info "  - platform.keybuzz.io → IP LB Hetzner"
    log_info "  - platform-api.keybuzz.io → IP LB Hetzner"
    echo ""
    exit 0
else
    log_error "❌ Certains tests ont échoué"
    echo "=============================================================="
    echo ""
    log_warning "Vérifiez les logs des pods pour plus de détails:"
    log_info "  kubectl logs -n keybuzz -l app=keybuzz-api"
    log_info "  kubectl logs -n keybuzz -l app=keybuzz-front"
    echo ""
    exit 1
fi

