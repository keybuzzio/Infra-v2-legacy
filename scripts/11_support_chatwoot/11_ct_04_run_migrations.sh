#!/usr/bin/env bash
#
# 11_ct_04_run_migrations.sh - Exécute les migrations Rails Chatwoot via une Job Kubernetes
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

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Exécution des migrations Chatwoot"
echo "=============================================================="
echo ""

# Vérifier que le Deployment existe
if ! kubectl get deployment chatwoot-web -n chatwoot > /dev/null 2>&1; then
    log_error "Deployment chatwoot-web non trouvé"
    exit 1
fi

# Récupérer l'image utilisée
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
log_info "Image Chatwoot : ${IMAGE}"

# Vérifier que ConfigMap et Secret existent
if ! kubectl get configmap chatwoot-config -n chatwoot > /dev/null 2>&1; then
    log_error "ConfigMap chatwoot-config non trouvé"
    exit 1
fi

if ! kubectl get secret chatwoot-secrets -n chatwoot > /dev/null 2>&1; then
    log_error "Secret chatwoot-secrets non trouvé"
    exit 1
fi

# Supprimer l'ancienne Job si elle existe
log_info "Nettoyage des anciennes Jobs..."
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true > /dev/null 2>&1
sleep 2

# Créer la Job pour exécuter les migrations
log_info "Création de la Job pour exécuter les migrations..."
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-migrations
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: chatwoot-migrations
    spec:
      restartPolicy: Never
      containers:
      - name: chatwoot-migrations
        image: ${IMAGE}
        envFrom:
        - secretRef:
            name: chatwoot-secrets
        - configMapRef:
            name: chatwoot-config
        command:
        - /bin/sh
        - -c
        - |
          set -e
          echo "Starting Chatwoot database migration..."
          bundle exec rails db:chatwoot_prepare
          echo "Database migration completed successfully"
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
log_info "Attente de la fin de la Job (timeout: 10 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s 2>/dev/null; then
    log_success "Job terminée avec succès"
else
    log_warning "La Job n'est pas encore terminée ou a échoué"
fi

# Afficher les logs
echo ""
log_info "Logs de la Job :"
echo "=============================================================="
kubectl logs -n chatwoot job/chatwoot-migrations --tail=100 2>&1 || true
echo "=============================================================="
echo ""

# Vérifier le statut de la Job
JOB_STATUS=$(kubectl get job chatwoot-migrations -n chatwoot -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "${JOB_STATUS}" = "Complete" ]; then
    log_success "✅ Migrations exécutées avec succès"
    
    # Supprimer la Job
    log_info "Suppression de la Job..."
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true > /dev/null 2>&1
    log_success "Job supprimée"
else
    log_error "La Job n'est pas terminée (statut: ${JOB_STATUS})"
    log_info "Vérifiez les logs avec: kubectl logs -n chatwoot job/chatwoot-migrations"
    exit 1
fi

echo ""
log_success "✅ Migrations terminées"
echo ""
