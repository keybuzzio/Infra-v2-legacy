#!/usr/bin/env bash
#
# validate_module10_platform.sh - Validation complète Module 10 Platform
#
# Ce script valide le déploiement complet du Module 10 Platform KeyBuzz.
#
# Usage:
#   ./validate_module10_platform.sh [servers.tsv]
#
# Prérequis:
#   - Module 10 Platform installé
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 10 Platform - Validation"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo ""

ERRORS=0
WARNINGS=0

# 1. Vérifier les Deployments
log_info "1. Vérification des Deployments..."
echo ""

DEPLOYMENTS=("keybuzz-api" "keybuzz-ui" "keybuzz-my-ui")
for deploy in "${DEPLOYMENTS[@]}"; do
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment ${deploy} -n keybuzz" > /dev/null 2>&1; then
        AVAILABLE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment ${deploy} -n keybuzz -o jsonpath='{.status.conditions[?(@.type==\"Available\")].status}'" 2>/dev/null || echo "False")
        if [[ "${AVAILABLE}" == "True" ]]; then
            REPLICAS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment ${deploy} -n keybuzz -o jsonpath='{.status.readyReplicas}'" 2>/dev/null || echo "0")
            DESIRED=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment ${deploy} -n keybuzz -o jsonpath='{.spec.replicas}'" 2>/dev/null || echo "0")
            if [[ "${REPLICAS}" == "${DESIRED}" ]] && [[ "${REPLICAS}" -ge 3 ]]; then
                log_success "  ${deploy}: Available=True, Replicas=${REPLICAS}/${DESIRED}"
            else
                log_warning "  ${deploy}: Available=True mais Replicas=${REPLICAS}/${DESIRED} (< 3)"
                ((WARNINGS++))
            fi
        else
            log_error "  ${deploy}: Available=False"
            ((ERRORS++))
        fi
    else
        log_error "  ${deploy}: Deployment introuvable"
        ((ERRORS++))
    fi
done

echo ""

# 2. Vérifier les Services
log_info "2. Vérification des Services ClusterIP..."
echo ""

SERVICES=("keybuzz-api" "keybuzz-ui" "keybuzz-my-ui")
for svc in "${SERVICES[@]}"; do
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc ${svc} -n keybuzz" > /dev/null 2>&1; then
        TYPE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc ${svc} -n keybuzz -o jsonpath='{.spec.type}'" 2>/dev/null || echo "Unknown")
        if [[ "${TYPE}" == "ClusterIP" ]]; then
            ENDPOINTS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get endpoints ${svc} -n keybuzz -o jsonpath='{.subsets[0].addresses[*].ip}'" 2>/dev/null || echo "")
            if [[ -n "${ENDPOINTS}" ]]; then
                log_success "  ${svc}: type=ClusterIP, endpoints présents"
            else
                log_warning "  ${svc}: type=ClusterIP mais aucun endpoint"
                ((WARNINGS++))
            fi
        else
            log_error "  ${svc}: type=${TYPE} (attendu: ClusterIP)"
            ((ERRORS++))
        fi
    else
        log_error "  ${svc}: Service introuvable"
        ((ERRORS++))
    fi
done

echo ""

# 3. Vérifier les Ingress
log_info "3. Vérification des Ingress..."
echo ""

declare -A INGRESS_MAP=(
    ["platform-api.keybuzz.io"]="platform-api-ingress"
    ["platform.keybuzz.io"]="platform-ui-ingress"
    ["my.keybuzz.io"]="platform-my-ingress"
)

for host in "${!INGRESS_MAP[@]}"; do
    INGRESS_NAME="${INGRESS_MAP[$host]}"
    if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress ${INGRESS_NAME} -n keybuzz" > /dev/null 2>&1; then
        INGRESS_HOST=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress ${INGRESS_NAME} -n keybuzz -o jsonpath='{.spec.rules[0].host}'" 2>/dev/null || echo "")
        if [[ "${INGRESS_HOST}" == "${host}" ]]; then
            log_success "  ${host}: Ingress présent et configuré"
        else
            log_warning "  ${host}: Ingress présent mais host=${INGRESS_HOST}"
            ((WARNINGS++))
        fi
    else
        log_error "  ${host}: Ingress introuvable"
        ((ERRORS++))
    fi
done

echo ""

# 4. Tests de connectivité depuis un pod test
log_info "4. Tests de connectivité depuis un pod test..."
echo ""

# Créer un pod de test temporaire
TEST_POD_YAML=$(cat <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: platform-test-pod
  namespace: keybuzz
spec:
  containers:
  - name: curl
    image: curlimages/curl:latest
    command: ["sleep", "3600"]
  restartPolicy: Never
EOF
)

echo "${TEST_POD_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1

# Attendre que le pod soit prêt
log_info "  Attente du pod de test..."
sleep 10

# Test platform.keybuzz.io
log_info "  Test: curl -k https://platform.keybuzz.io"
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://platform.keybuzz.io" 2>/dev/null | grep -q "200"; then
    log_success "    platform.keybuzz.io: HTTP 200"
else
    HTTP_CODE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://platform.keybuzz.io" 2>/dev/null || echo "000")
    log_error "    platform.keybuzz.io: HTTP ${HTTP_CODE}"
    ((ERRORS++))
fi

# Test platform-api.keybuzz.io/health
log_info "  Test: curl -k https://platform-api.keybuzz.io/health"
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://platform-api.keybuzz.io/health" 2>/dev/null | grep -q "200"; then
    log_success "    platform-api.keybuzz.io/health: HTTP 200"
else
    HTTP_CODE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://platform-api.keybuzz.io/health" 2>/dev/null || echo "000")
    log_warning "    platform-api.keybuzz.io/health: HTTP ${HTTP_CODE} (peut être normal si /health n'existe pas encore)"
    ((WARNINGS++))
fi

# Test my.keybuzz.io
log_info "  Test: curl -k https://my.keybuzz.io"
if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://my.keybuzz.io" 2>/dev/null | grep -q "200"; then
    log_success "    my.keybuzz.io: HTTP 200"
else
    HTTP_CODE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz platform-test-pod -- curl -k -s -o /dev/null -w '%{http_code}' https://my.keybuzz.io" 2>/dev/null || echo "000")
    log_error "    my.keybuzz.io: HTTP ${HTTP_CODE}"
    ((ERRORS++))
fi

# Nettoyer le pod de test
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete pod platform-test-pod -n keybuzz" > /dev/null 2>&1 || true

echo ""

# Résumé
echo "=============================================================="
echo " Résumé de la Validation"
echo "=============================================================="
echo ""

if [[ ${ERRORS} -eq 0 ]] && [[ ${WARNINGS} -eq 0 ]]; then
    log_success "✅ Module 10 Platform validé à 100%"
    echo ""
    exit 0
elif [[ ${ERRORS} -eq 0 ]]; then
    log_warning "⚠️  Module 10 Platform validé avec ${WARNINGS} avertissement(s)"
    echo ""
    exit 0
else
    log_error "❌ Module 10 Platform a ${ERRORS} erreur(s) et ${WARNINGS} avertissement(s)"
    echo ""
    exit 1
fi

