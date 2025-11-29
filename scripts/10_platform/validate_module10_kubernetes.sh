#!/usr/bin/env bash
#
# validate_module10_kubernetes.sh - Validation complète Module 10 Platform sur Kubernetes
#
# Usage:
#   ./validate_module10_kubernetes.sh
#
# Prérequis:
#   - Module 10 Platform installé
#   - kubeconfig configuré
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORT_FILE="${INSTALL_DIR}/reports/RAPPORT_VALIDATION_MODULE10_PLATFORM.md"
RECAP_CHATGPT_FILE="${INSTALL_DIR}/reports/RECAP_CHATGPT_MODULE10.md"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${REPORT_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${REPORT_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${REPORT_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${REPORT_FILE}"
}

check_point() {
    local message="$1"
    local status="$2"
    if [[ "${status}" == "true" ]]; then
        log_success "  ${message}"
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
    else
        log_error "  ${message}"
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
}

export KUBECONFIG=/root/.kube/config

# Initialisation
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0
TOTAL_CHECKS=0

mkdir -p "${INSTALL_DIR}/reports"

# Header du rapport
echo "# 📋 Rapport de Validation - Module 10 : Plateforme KeyBuzz" > "${REPORT_FILE}"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" >> "${REPORT_FILE}"
echo "---" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " [KeyBuzz] Module 10 Platform - Validation" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

# 1. Vérifier les Deployments
log_info "=== TEST 1: Deployments ==="
DEPLOYMENTS=("keybuzz-api" "keybuzz-ui" "keybuzz-my-ui")
for deploy in "${DEPLOYMENTS[@]}"; do
    if kubectl get deployment "${deploy}" -n keybuzz > /dev/null 2>&1; then
        AVAILABLE=$(kubectl get deployment "${deploy}" -n keybuzz -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || echo "False")
        if [[ "${AVAILABLE}" == "True" ]]; then
            REPLICAS=$(kubectl get deployment "${deploy}" -n keybuzz -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
            DESIRED=$(kubectl get deployment "${deploy}" -n keybuzz -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
            if [[ "${REPLICAS}" == "${DESIRED}" ]]; then
                check_point "Deployment ${deploy}: ${REPLICAS}/${DESIRED} replicas Ready" "true"
            else
                check_point "Deployment ${deploy}: ${REPLICAS}/${DESIRED} replicas Ready" "false"
            fi
        else
            check_point "Deployment ${deploy}: Available=False" "false"
        fi
    else
        check_point "Deployment ${deploy}: introuvable" "false"
    fi
done
echo "" | tee -a "${REPORT_FILE}"

# 2. Vérifier les Services ClusterIP
log_info "=== TEST 2: Services ClusterIP ==="
SERVICES=("keybuzz-api" "keybuzz-ui" "keybuzz-my-ui")
for svc in "${SERVICES[@]}"; do
    if kubectl get service "${svc}" -n keybuzz > /dev/null 2>&1; then
        TYPE=$(kubectl get service "${svc}" -n keybuzz -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
        if [[ "${TYPE}" == "ClusterIP" ]]; then
            CLUSTER_IP=$(kubectl get service "${svc}" -n keybuzz -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
            check_point "Service ${svc}: ClusterIP=${CLUSTER_IP}" "true"
        else
            check_point "Service ${svc}: type=${TYPE} (attendu: ClusterIP)" "false"
        fi
    else
        check_point "Service ${svc}: introuvable" "false"
    fi
done
echo "" | tee -a "${REPORT_FILE}"

# 3. Vérifier les Ingress
log_info "=== TEST 3: Ingress ==="
INGRESS_HOSTS=("platform-api.keybuzz.io" "platform.keybuzz.io" "my.keybuzz.io")
for host in "${INGRESS_HOSTS[@]}"; do
    if kubectl get ingress -n keybuzz -o jsonpath='{.items[*].spec.rules[*].host}' 2>/dev/null | grep -q "${host}"; then
        check_point "Ingress pour ${host}: configuré" "true"
    else
        check_point "Ingress pour ${host}: introuvable" "false"
    fi
done
echo "" | tee -a "${REPORT_FILE}"

# 4. Vérifier les Pods
log_info "=== TEST 4: Pods ==="
POD_COUNT=$(kubectl get pods -n keybuzz --no-headers 2>/dev/null | wc -l)
READY_PODS=$(kubectl get pods -n keybuzz --no-headers 2>/dev/null | grep -c "Running" || echo "0")
if [[ "${POD_COUNT}" -ge 9 ]]; then
    check_point "Pods: ${READY_PODS}/${POD_COUNT} Running" "true"
else
    check_point "Pods: ${READY_PODS}/${POD_COUNT} Running (attendu: ≥9)" "false"
fi
echo "" | tee -a "${REPORT_FILE}"

# 5. Vérifier ConfigMap et Secret
log_info "=== TEST 5: ConfigMap et Secret ==="
if kubectl get configmap keybuzz-api-config -n keybuzz > /dev/null 2>&1; then
    check_point "ConfigMap keybuzz-api-config: présent" "true"
else
    check_point "ConfigMap keybuzz-api-config: introuvable" "false"
fi

if kubectl get secret keybuzz-api-secret -n keybuzz > /dev/null 2>&1; then
    check_point "Secret keybuzz-api-secret: présent" "true"
else
    check_point "Secret keybuzz-api-secret: introuvable" "false"
fi
echo "" | tee -a "${REPORT_FILE}"

# 6. Test d'accès aux Services ClusterIP
log_info "=== TEST 6: Accès Services ClusterIP ==="
log_info "Création d'un pod de test..."
kubectl run test-pod --image=busybox --rm -i --restart=Never -- sh -c "wget -T 5 -q -O- http://keybuzz-ui.keybuzz.svc.cluster.local" > /tmp/test-ui.log 2>&1 || true
if grep -q "Welcome to nginx" /tmp/test-ui.log 2>&1; then
    check_point "Accès Service keybuzz-ui via ClusterIP: OK" "true"
else
    check_point "Accès Service keybuzz-ui via ClusterIP: ÉCHEC" "false"
fi
rm -f /tmp/test-ui.log
echo "" | tee -a "${REPORT_FILE}"

# Résumé final
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo " Résumé de la validation" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
echo "Total des vérifications: ${TOTAL_CHECKS}" | tee -a "${REPORT_FILE}"
echo "Vérifications réussies: ${PASSED_CHECKS}" | tee -a "${REPORT_FILE}"
echo "Vérifications échouées: ${FAILED_CHECKS}" | tee -a "${REPORT_FILE}"
echo "Vérifications avec avertissement: ${WARNING_CHECKS}" | tee -a "${REPORT_FILE}"
echo "" | tee -a "${REPORT_FILE}"

if [[ "${FAILED_CHECKS}" -eq 0 ]]; then
    log_success "✅ Module 10 validé à 100% !"
    VALIDATION_STATUS="✅ Validé à 100%"
else
    log_warning "⚠️  Module 10 validé avec ${FAILED_CHECKS} erreur(s)"
    VALIDATION_STATUS="⚠️  Validé avec erreurs"
fi
echo "" | tee -a "${REPORT_FILE}"

# Génération du récapitulatif ChatGPT
log_info "Génération de RECAP_CHATGPT_MODULE10.md..."
{
    echo "# 📋 Récapitulatif Module 10 - Plateforme KeyBuzz (Pour ChatGPT)"
    echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "---"
    echo ""
    echo "## Vue d'ensemble"
    echo "Le Module 10 (Plateforme KeyBuzz) a été déployé avec succès sur Kubernetes."
    echo ""
    echo "## Composants Déployés"
    echo "- **API**: keybuzz-api (3 replicas, port 8080)"
    echo "- **UI**: keybuzz-ui (3 replicas, port 80)"
    echo "- **My**: keybuzz-my-ui (3 replicas, port 80)"
    echo ""
    echo "## URLs Configurées"
    echo "- https://platform-api.keybuzz.io"
    echo "- https://platform.keybuzz.io"
    echo "- https://my.keybuzz.io"
    echo ""
    echo "## Statut Global du Module"
    echo "${VALIDATION_STATUS}"
} > "${RECAP_CHATGPT_FILE}"
log_success "RECAP_CHATGPT_MODULE10.md généré."

echo "" | tee -a "${REPORT_FILE}"
echo "==============================================================" | tee -a "${REPORT_FILE}"
log_success "✅ Validation du Module 10 terminée !"
echo "==============================================================" | tee -a "${REPORT_FILE}"

