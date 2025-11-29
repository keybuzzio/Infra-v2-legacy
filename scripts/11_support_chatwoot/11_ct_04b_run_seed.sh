#!/usr/bin/env bash
#
# 11_ct_04b_run_seed.sh - Exécute db:seed après les migrations
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

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

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Exécution db:seed Chatwoot"
echo "=============================================================="
echo ""

# Récupérer l'image
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
log_info "Image Chatwoot : ${IMAGE}"

# Supprimer l'ancienne Job si elle existe
kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true > /dev/null 2>&1
sleep 2

# Créer la Job pour exécuter db:seed
log_info "Création de la Job pour exécuter db:seed..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-seed
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: chatwoot-seed
    spec:
      restartPolicy: Never
      containers:
      - name: chatwoot-seed
        image: ${IMAGE}
        envFrom:
        - secretRef:
            name: chatwoot-secrets
        - configMapRef:
            name: chatwoot-config
        command: ["bundle"]
        args: ["exec", "rails", "db:seed"]
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

log_success "Job créée"

# Attendre que la Job se termine
log_info "Attente de la fin de la Job (timeout: 5 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s 2>/dev/null; then
    log_success "Job terminée avec succès"
else
    log_warning "La Job n'est pas encore terminée ou a échoué"
fi

# Afficher les logs
echo ""
log_info "Logs de la Job :"
echo "=============================================================="
kubectl logs -n chatwoot job/chatwoot-seed --tail=50 2>&1 || true
echo "=============================================================="
echo ""

# Vérifier le statut
JOB_STATUS=$(kubectl get job chatwoot-seed -n chatwoot -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "${JOB_STATUS}" = "Complete" ]; then
    log_success "✅ Seed exécuté avec succès"
    kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true > /dev/null 2>&1
else
    log_error "La Job n'est pas terminée (statut: ${JOB_STATUS})"
    exit 1
fi

echo ""
log_success "✅ Seed terminé"
echo ""


