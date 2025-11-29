#!/bin/bash
#
# execute_finalisation.sh - Exécute toutes les étapes de finalisation Module 11
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config
SCRIPT_DIR="/opt/keybuzz-installer-v2/scripts/11_support_chatwoot"
cd "$SCRIPT_DIR"

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
echo " [KeyBuzz] Module 11 - Finalisation Complète"
echo "=============================================================="
echo ""

# Étape 1 : Migrations
echo "=== ÉTAPE 1/4 : EXÉCUTION DES MIGRATIONS ==="
log_info "Suppression de l'ancienne Job..."
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 3

IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
log_info "Image: $IMAGE"

log_info "Création de la Job de migrations..."
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
        command: ["bundle", "exec", "rails", "db:migrate"]
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

log_info "Attente de la fin de la Job (timeout: 10 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s 2>/dev/null; then
    log_success "Migrations terminées avec succès"
    echo ""
    log_info "Logs de la Job :"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=30
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
else
    log_error "La Job de migrations a échoué ou timeout"
    echo ""
    log_info "Logs de la Job :"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50
    exit 1
fi

echo ""
echo "=== ÉTAPE 2/4 : EXÉCUTION DB:SEED ==="
log_info "Suppression de l'ancienne Job..."
kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true
sleep 2

log_info "Création de la Job de seed..."
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
        command: ["bundle", "exec", "rails", "db:seed"]
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

log_info "Attente de la fin de la Job (timeout: 5 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s 2>/dev/null; then
    log_success "Seed terminé avec succès"
    echo ""
    log_info "Logs de la Job :"
    kubectl logs -n chatwoot job/chatwoot-seed --tail=30
    kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true
else
    log_error "La Job de seed a échoué ou timeout"
    echo ""
    log_info "Logs de la Job :"
    kubectl logs -n chatwoot job/chatwoot-seed --tail=50
    # On continue quand même, le seed peut échouer si déjà exécuté
fi

echo ""
echo "=== ÉTAPE 3/4 : REDÉMARRAGE DES PODS ==="
log_info "Redémarrage des Deployments..."
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot

log_info "Attente du démarrage des pods (90 secondes)..."
sleep 90

log_info "État des pods:"
kubectl get pods -n chatwoot

log_info "État des Deployments:"
kubectl get deployments -n chatwoot

echo ""
echo "=== ÉTAPE 4/4 : VALIDATION ET RAPPORTS ==="
log_info "Exécution de la validation..."
if bash validate_module11.sh; then
    log_success "Validation terminée"
else
    log_error "Validation avec erreurs (voir le rapport)"
fi

log_info "Génération des rapports..."
bash generate_reports.sh

echo ""
log_success "✅ Module 11 finalisé !"
echo ""
log_info "Rapports générés dans /opt/keybuzz-installer-v2/reports/"
echo ""

