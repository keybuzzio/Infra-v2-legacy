#!/usr/bin/env bash
#
# validate_module11.sh - Validation complète du Module 11 Chatwoot
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

REPORTS_DIR="/opt/keybuzz-installer-v2/reports"
SCRIPT_DIR="/opt/keybuzz-installer-v2/scripts/11_support_chatwoot"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

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

# Compteurs
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

check_result() {
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    if [ $1 -eq 0 ]; then
        PASSED_CHECKS=$((PASSED_CHECKS + 1))
        log_success "$2"
        echo "✅ $2" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
        return 0
    else
        FAILED_CHECKS=$((FAILED_CHECKS + 1))
        log_error "$2"
        echo "❌ $2" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
        return 1
    fi
}

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Validation Complète Chatwoot"
echo "=============================================================="
echo ""

mkdir -p "${REPORTS_DIR}"

# Initialiser le rapport
cat > "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md" <<EOF
# 📋 Rapport de Validation - Module 11 : Support KeyBuzz (Chatwoot)

**Date** : $(date)
**Environnement** : Production
**Namespace** : chatwoot

---

## ✅ Checklist de Validation

EOF

# 1. Namespace
log_info "1. Vérification du namespace..."
if kubectl get namespace chatwoot > /dev/null 2>&1; then
    check_result 0 "Namespace chatwoot existe"
    kubectl get namespace chatwoot -o yaml >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md" 2>&1 || true
else
    check_result 1 "Namespace chatwoot non trouvé"
fi

# 2. Deployments
log_info "2. Vérification des Deployments..."
WEB_READY=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WEB_REPLICAS=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
WORKER_READY=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_REPLICAS=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")

if [ "${WEB_READY}" = "${WEB_REPLICAS}" ] && [ "${WEB_REPLICAS}" != "0" ]; then
    check_result 0 "Deployment chatwoot-web : ${WEB_READY}/${WEB_REPLICAS} Ready"
else
    check_result 1 "Deployment chatwoot-web : ${WEB_READY}/${WEB_REPLICAS} Ready (attendu: ${WEB_REPLICAS}/${WEB_REPLICAS})"
fi

if [ "${WORKER_READY}" = "${WORKER_REPLICAS}" ] && [ "${WORKER_REPLICAS}" != "0" ]; then
    check_result 0 "Deployment chatwoot-worker : ${WORKER_READY}/${WORKER_REPLICAS} Ready"
else
    check_result 1 "Deployment chatwoot-worker : ${WORKER_READY}/${WORKER_REPLICAS} Ready (attendu: ${WORKER_REPLICAS}/${WORKER_REPLICAS})"
fi

# 3. Pods
log_info "3. Vérification des Pods..."
PODS_RUNNING=$(kubectl get pods -n chatwoot -o jsonpath='{.items[?(@.status.phase=="Running")].metadata.name}' 2>/dev/null | wc -w)
PODS_TOTAL=$(kubectl get pods -n chatwoot --no-headers 2>/dev/null | wc -l)

if [ "${PODS_RUNNING}" = "${PODS_TOTAL}" ] && [ "${PODS_TOTAL}" != "0" ]; then
    check_result 0 "Pods : ${PODS_RUNNING}/${PODS_TOTAL} Running"
else
    check_result 1 "Pods : ${PODS_RUNNING}/${PODS_TOTAL} Running (attendu: ${PODS_TOTAL}/${PODS_TOTAL})"
    echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo "### État des Pods" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    kubectl get pods -n chatwoot >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md" 2>&1 || true
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
fi

# 4. Service
log_info "4. Vérification du Service..."
if kubectl get service chatwoot-web -n chatwoot > /dev/null 2>&1; then
    check_result 0 "Service chatwoot-web existe"
    echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo "### Service chatwoot-web" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    kubectl get service chatwoot-web -n chatwoot >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md" 2>&1 || true
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
else
    check_result 1 "Service chatwoot-web non trouvé"
fi

# 5. Ingress
log_info "5. Vérification de l'Ingress..."
INGRESS_HOST=$(kubectl get ingress chatwoot-ingress -n chatwoot -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
if [ "${INGRESS_HOST}" = "support.keybuzz.io" ]; then
    check_result 0 "Ingress configuré pour support.keybuzz.io"
    echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo "### Ingress chatwoot-ingress" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    kubectl get ingress chatwoot-ingress -n chatwoot >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md" 2>&1 || true
    echo '```' >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
else
    check_result 1 "Ingress non configuré correctement (host: ${INGRESS_HOST})"
fi

# 6. ConfigMap et Secret
log_info "6. Vérification ConfigMap et Secret..."
if kubectl get configmap chatwoot-config -n chatwoot > /dev/null 2>&1; then
    check_result 0 "ConfigMap chatwoot-config existe"
else
    check_result 1 "ConfigMap chatwoot-config non trouvé"
fi

if kubectl get secret chatwoot-secrets -n chatwoot > /dev/null 2>&1; then
    check_result 0 "Secret chatwoot-secrets existe"
else
    check_result 1 "Secret chatwoot-secrets non trouvé"
fi

# 7. Test de connectivité interne
log_info "7. Test de connectivité interne..."
HTTP_CODE=$(kubectl run curl-test-${TIMESTAMP} --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- sh -c 'curl -sS -o /dev/null -w "%{http_code}" http://chatwoot-web.chatwoot.svc.cluster.local:3000' 2>&1 | tail -1 || echo "000")
if echo "${HTTP_CODE}" | grep -qE "200|302|301|401"; then
    check_result 0 "Service chatwoot-web accessible en interne (HTTP ${HTTP_CODE})"
else
    check_result 1 "Service chatwoot-web non accessible (HTTP ${HTTP_CODE})"
fi

# 8. Base de données
log_info "8. Vérification base de données..."
source /opt/keybuzz-installer-v2/credentials/postgres.env 2>/dev/null || true
source /opt/keybuzz-installer-v2/credentials/chatwoot.env 2>/dev/null || true
export PGPASSWORD="${POSTGRES_SUPERPASS:-}"

if psql -h 10.0.0.10 -p 5432 -U kb_admin -d chatwoot -c "SELECT 1;" > /dev/null 2>&1; then
    check_result 0 "Base de données chatwoot accessible"
    TABLE_COUNT=$(psql -h 10.0.0.10 -p 5432 -U kb_admin -d chatwoot -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")
    echo "   Tables créées : ${TABLE_COUNT}" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
else
    check_result 1 "Base de données chatwoot non accessible"
fi

# Résumé final
echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "---" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "## 📊 Résumé" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "- **Total vérifications** : ${TOTAL_CHECKS}" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "- **✅ Réussies** : ${PASSED_CHECKS}" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "- **❌ Échouées** : ${FAILED_CHECKS}" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"

if [ ${FAILED_CHECKS} -eq 0 ]; then
    echo "## ✅ Statut : Module 11 validé à 100%" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    log_success "✅ Module 11 validé à 100%"
    EXIT_CODE=0
else
    echo "## ⚠️ Statut : Module 11 partiellement validé (${FAILED_CHECKS} échec(s))" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    echo "" >> "${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
    log_warning "⚠️ Module 11 partiellement validé (${FAILED_CHECKS} échec(s))"
    EXIT_CODE=1
fi

echo ""
echo "=============================================================="
echo "Résumé :"
echo "  Total : ${TOTAL_CHECKS}"
echo "  ✅ Réussies : ${PASSED_CHECKS}"
echo "  ❌ Échouées : ${FAILED_CHECKS}"
echo "=============================================================="
echo ""
echo "Rapport généré : ${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo ""

exit ${EXIT_CODE}

