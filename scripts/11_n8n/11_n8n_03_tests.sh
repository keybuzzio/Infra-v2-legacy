#!/usr/bin/env bash
#
# 11_n8n_03_tests.sh - Tests de validation n8n
#
# Ce script effectue des tests de validation pour n8n :
# - Vérification des Deployments, Services, Pods
# - Tests de connectivité
# - Tests de base de données
# - Tests Redis queue
# - Tests Ingress
#
# Usage:
#   ./11_n8n_03_tests.sh [servers.tsv]
#
# Prérequis:
#   - Module 11 scripts 00-02 exécutés
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/n8n.env"

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

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    exit 1
fi

source "${CREDENTIALS_FILE}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Trouver le premier master K3s
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

# Compteurs de tests
TESTS_PASSED=0
TESTS_FAILED=0

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 11 - Tests de validation n8n"
echo "=============================================================="
echo ""

# Test 1: Vérification Deployment
log_info "Test 1: Vérification Deployment n8n..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment n8n -n n8n" > /dev/null 2>&1; then
    REPLICAS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment n8n -n n8n -o jsonpath='{.status.readyReplicas}'" 2>/dev/null || echo "0")
    DESIRED=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment n8n -n n8n -o jsonpath='{.spec.replicas}'" 2>/dev/null || echo "0")
    if [[ "${REPLICAS}" == "${DESIRED}" ]] && [[ "${REPLICAS}" -ge 1 ]]; then
        log_success "Deployment n8n: ${REPLICAS}/${DESIRED} réplicas prêtes"
        ((TESTS_PASSED++))
    else
        log_error "Deployment n8n: ${REPLICAS}/${DESIRED} réplicas prêtes"
        ((TESTS_FAILED++))
    fi
else
    log_error "Deployment n8n introuvable"
    ((TESTS_FAILED++))
fi

# Test 2: Vérification Service
log_info "Test 2: Vérification Service n8n..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc n8n -n n8n" > /dev/null 2>&1; then
    ENDPOINTS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get endpoints n8n -n n8n -o jsonpath='{.subsets[0].addresses[*].ip}'" 2>/dev/null || echo "")
    if [[ -n "${ENDPOINTS}" ]]; then
        log_success "Service n8n: Endpoints configurés"
        ((TESTS_PASSED++))
    else
        log_error "Service n8n: Aucun endpoint"
        ((TESTS_FAILED++))
    fi
else
    log_error "Service n8n introuvable"
    ((TESTS_FAILED++))
fi

# Test 3: Vérification Pods
log_info "Test 3: Vérification Pods n8n..."
PODS_RUNNING=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n n8n -l app=n8n -o jsonpath='{.items[?(@.status.phase==\"Running\")].metadata.name}'" 2>/dev/null | wc -w || echo "0")
if [[ "${PODS_RUNNING}" -ge 1 ]]; then
    log_success "Pods n8n: ${PODS_RUNNING} pods Running"
    ((TESTS_PASSED++))
else
    log_error "Pods n8n: Aucun pod Running"
    ((TESTS_FAILED++))
fi

# Test 4: Vérification HPA
log_info "Test 4: Vérification HPA n8n-hpa..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get hpa n8n-hpa -n n8n" > /dev/null 2>&1; then
    log_success "HPA n8n-hpa: Configuré"
    ((TESTS_PASSED++))
else
    log_error "HPA n8n-hpa introuvable"
    ((TESTS_FAILED++))
fi

# Test 5: Vérification Ingress
log_info "Test 5: Vérification Ingress n8n-ingress..."
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress n8n-ingress -n n8n" > /dev/null 2>&1; then
    INGRESS_HOST=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress n8n-ingress -n n8n -o jsonpath='{.spec.rules[0].host}'" 2>/dev/null || echo "")
    if [[ "${INGRESS_HOST}" == "n8n.keybuzz.io" ]]; then
        log_success "Ingress n8n-ingress: ${INGRESS_HOST} configuré"
        ((TESTS_PASSED++))
    else
        log_error "Ingress n8n-ingress: Host incorrect (${INGRESS_HOST})"
        ((TESTS_FAILED++))
    fi
else
    log_error "Ingress n8n-ingress introuvable"
    ((TESTS_FAILED++))
fi

# Test 6: Test de connectivité au service
log_info "Test 6: Test de connectivité au service n8n..."
POD_NAME=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pod -n n8n -l app=n8n -o jsonpath='{.items[0].metadata.name}'" 2>/dev/null || echo "")
if [[ -n "${POD_NAME}" ]]; then
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n n8n ${POD_NAME} -- wget -qO- http://localhost:5678/healthz 2>/dev/null" > /dev/null 2>&1; then
        log_success "Connectivité: Service n8n répond"
        ((TESTS_PASSED++))
    else
        log_warning "Connectivité: Service n8n ne répond pas encore (peut être normal au démarrage)"
        ((TESTS_FAILED++))
    fi
else
    log_error "Aucun pod n8n trouvé pour le test"
    ((TESTS_FAILED++))
fi

# Test 7: Test de connectivité à la base de données
log_info "Test 7: Test de connectivité à PostgreSQL..."
# Trouver un master PostgreSQL
declare -a PG_MASTER_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "postgres" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PG_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#PG_MASTER_IPS[@]} -ge 1 ]]; then
    PG_MASTER_IP="${PG_MASTER_IPS[0]}"
    if ssh ${SSH_KEY_OPTS} "root@${PG_MASTER_IP}" "PGPASSWORD='${N8N_DB_PASSWORD}' psql -h localhost -U ${N8N_DB_USER} -d ${N8N_DB_NAME} -c 'SELECT 1;' > /dev/null 2>&1" 2>/dev/null; then
        log_success "Base de données: Connexion PostgreSQL réussie"
        ((TESTS_PASSED++))
    else
        log_warning "Base de données: Connexion PostgreSQL échouée (peut être normal si base en cours d'initialisation)"
        ((TESTS_FAILED++))
    fi
else
    log_warning "Aucun master PostgreSQL trouvé pour le test"
    ((TESTS_FAILED++))
fi

# Test 8: Test de connectivité à Redis
log_info "Test 8: Test de connectivité à Redis..."
# Trouver un master Redis
declare -a REDIS_MASTER_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "redis" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        REDIS_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#REDIS_MASTER_IPS[@]} -ge 1 ]]; then
    REDIS_MASTER_IP="${REDIS_MASTER_IPS[0]}"
    if ssh ${SSH_KEY_OPTS} "root@${REDIS_MASTER_IP}" "docker exec redis-master redis-cli -a '${N8N_REDIS_PASSWORD}' PING 2>/dev/null | grep -q PONG" 2>/dev/null; then
        log_success "Redis: Connexion réussie"
        ((TESTS_PASSED++))
    else
        log_warning "Redis: Connexion échouée"
        ((TESTS_FAILED++))
    fi
else
    log_warning "Aucun master Redis trouvé pour le test"
    ((TESTS_FAILED++))
fi

# Résumé
echo ""
echo "=============================================================="
echo " Résumé des tests"
echo "=============================================================="
echo ""
log_info "Tests réussis: ${TESTS_PASSED}"
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    log_warning "Tests échoués: ${TESTS_FAILED}"
fi
echo ""

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    log_success "✅ Tous les tests sont passés !"
    echo ""
    log_info "n8n est prêt à être utilisé:"
    log_info "  - URL: https://n8n.keybuzz.io"
    log_info "  - Namespace: n8n"
    log_info "  - Réplicas: 3+ (HPA: min=3, max=20)"
    echo ""
    exit 0
else
    log_warning "⚠️  Certains tests ont échoué"
    log_warning "Vérifiez les logs des pods pour plus de détails:"
    log_info "  kubectl logs -n n8n -l app=n8n --tail=50"
    echo ""
    exit 1
fi

