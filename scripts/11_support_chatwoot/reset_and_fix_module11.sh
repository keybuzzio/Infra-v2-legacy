#!/usr/bin/env bash
#
# reset_and_fix_module11.sh - Réinitialise Module 11 avec Chatwoot v3.12.0
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export KUBECONFIG=/root/.kube/config

# Version stable de Chatwoot
CHATWOOT_VERSION="v3.12.0"
CHATWOOT_IMAGE="chatwoot/chatwoot:${CHATWOOT_VERSION}"

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
echo " [KeyBuzz] Module 11 - Réinitialisation avec Chatwoot ${CHATWOOT_VERSION}"
echo "=============================================================="
echo ""

# 1. Changer les images vers v3.12.0
log_info "Étape 1/6 : Mise à jour des images vers ${CHATWOOT_IMAGE}..."
kubectl set image deployment/chatwoot-web -n chatwoot chatwoot-web="${CHATWOOT_IMAGE}"
kubectl set image deployment/chatwoot-worker -n chatwoot chatwoot-worker="${CHATWOOT_IMAGE}"
log_success "Images mises à jour"
echo ""

# 2. Drop et recréer la DB chatwoot
log_info "Étape 2/6 : Réinitialisation de la base de données chatwoot..."

# Charger les credentials PostgreSQL
if [ ! -f "/opt/keybuzz-installer-v2/credentials/postgres.env" ]; then
    log_error "Fichier postgres.env non trouvé"
    exit 1
fi

source /opt/keybuzz-installer-v2/credentials/postgres.env

POSTGRES_HOST="${POSTGRES_HOST:-10.0.0.10}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_ADMIN_USER="${POSTGRES_SUPERUSER:-kb_admin}"
POSTGRES_ADMIN_PASSWORD="${POSTGRES_SUPERPASS:-}"

export PGPASSWORD="${POSTGRES_ADMIN_PASSWORD}"

log_info "Connexion à PostgreSQL sur ${POSTGRES_HOST}:${POSTGRES_PORT}..."

# Vérifier la connexion
if ! timeout 10 psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    log_error "Impossible de se connecter à PostgreSQL"
    exit 1
fi

# Drop la DB si elle existe
log_info "Suppression de la base de données chatwoot (si elle existe)..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = 'chatwoot' AND pid <> pg_backend_pid();

DROP DATABASE IF EXISTS chatwoot;
SQL

# Recréer la DB
log_info "Création de la base de données chatwoot..."
psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres <<SQL
CREATE DATABASE chatwoot;
GRANT ALL PRIVILEGES ON DATABASE chatwoot TO chatwoot;
SQL

log_success "Base de données chatwoot recréée"
echo ""

# 3. Supprimer les anciennes Jobs
log_info "Étape 3/6 : Nettoyage des anciennes Jobs..."
kubectl delete job -n chatwoot chatwoot-migrations chatwoot-seed --ignore-not-found=true > /dev/null 2>&1
sleep 3
log_success "Jobs supprimées"
echo ""

# 4. Relancer les migrations avec db:chatwoot_prepare
log_info "Étape 4/6 : Exécution des migrations avec db:chatwoot_prepare..."

# Récupérer l'image du Deployment
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')

# Créer la Job de migration
kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-migrations
  namespace: chatwoot
spec:
  backoffLimit: 2
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
          echo "Starting Chatwoot database preparation..."
          bundle exec rails db:chatwoot_prepare
          echo "Database preparation completed successfully"
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

log_success "Job de migration créée"
echo ""

log_info "Attente de la fin de la Job (timeout: 15 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=900s 2>/dev/null; then
    log_success "Migrations terminées avec succès"
else
    log_warning "La Job n'est pas encore terminée ou a échoué"
    log_info "Logs de la Job :"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50 2>&1 | tail -50
    echo ""
fi

# Afficher les logs
echo ""
log_info "Logs de la Job de migration :"
echo "=============================================================="
kubectl logs -n chatwoot job/chatwoot-migrations --tail=100 2>&1 || true
echo "=============================================================="
echo ""

# Vérifier le statut
JOB_STATUS=$(kubectl get job chatwoot-migrations -n chatwoot -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "${JOB_STATUS}" = "Complete" ]; then
    log_success "✅ Migrations exécutées avec succès"
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true > /dev/null 2>&1
else
    log_error "❌ La Job a échoué (statut: ${JOB_STATUS})"
    log_info "Vérifiez les logs avec: kubectl logs -n chatwoot job/chatwoot-migrations"
    exit 1
fi

echo ""

# 5. Redémarrer les Deployments
log_info "Étape 5/6 : Redémarrage des Deployments..."
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
log_success "Redémarrage lancé"
echo ""

log_info "Attente du démarrage des pods (90 secondes)..."
sleep 90

# 6. Vérifier l'état final
log_info "Étape 6/6 : Vérification de l'état final..."
echo ""

kubectl get deployments -n chatwoot
echo ""
kubectl get pods -n chatwoot
echo ""

WEB_READY=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WEB_DESIRED=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
WORKER_READY=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_DESIRED=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")

echo "Résumé:"
echo "  chatwoot-web: $WEB_READY/$WEB_DESIRED"
echo "  chatwoot-worker: $WORKER_READY/$WORKER_DESIRED"
echo ""

if [ "$WEB_READY" = "$WEB_DESIRED" ] && [ "$WORKER_READY" = "$WORKER_DESIRED" ]; then
    log_success "✅ Tous les pods sont Ready"
    echo ""
    log_info "🌐 Testez l'accès à: https://support.keybuzz.io"
    log_info "   Vous devriez voir la page de login Chatwoot"
    echo ""
    log_info "📋 Prochaines étapes:"
    log_info "   1. Vérifier https://support.keybuzz.io"
    log_info "   2. Si OK, générer les rapports: cd $SCRIPT_DIR && bash validate_module11.sh"
else
    log_warning "⚠️ Certains pods ne sont pas encore Ready"
    log_info "Vérifiez avec: kubectl get pods -n chatwoot -w"
    log_info "Logs: kubectl logs -n chatwoot deployment/chatwoot-web --tail=50"
fi

echo ""
log_success "✅ Réinitialisation terminée"
echo ""

