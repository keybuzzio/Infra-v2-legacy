#!/usr/bin/env bash
#
# finalize_module11.sh - Finalise le Module 11 Chatwoot
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
echo " [KeyBuzz] Module 11 - Finalisation"
echo "=============================================================="
echo ""

# 1. Nettoyer les pods en erreur
log_info "Étape 1/7 : Nettoyage..."
kubectl delete pods -n chatwoot -l app=chatwoot,component=web --grace-period=0 --force 2>/dev/null || true
kubectl delete job -n chatwoot chatwoot-migrations chatwoot-seed 2>/dev/null || true
sleep 5
log_success "Nettoyage terminé"
echo ""

# 2. Vérifier la configuration
log_info "Étape 2/7 : Vérification configuration..."
if ! kubectl get configmap chatwoot-config -n chatwoot > /dev/null 2>&1; then
    log_error "ConfigMap manquant. Exécutez 11_ct_01_prepare_config.sh"
    exit 1
fi
if ! kubectl get secret chatwoot-secrets -n chatwoot > /dev/null 2>&1; then
    log_error "Secret manquant. Exécutez 11_ct_01_prepare_config.sh"
    exit 1
fi
log_success "Configuration OK"
echo ""

# 3. Uniformiser l'image
log_info "Étape 3/7 : Uniformisation image..."
CHATWOOT_IMAGE="chatwoot/chatwoot:latest"
kubectl set image deployment/chatwoot-web -n chatwoot chatwoot-web="$CHATWOOT_IMAGE" || true
kubectl set image deployment/chatwoot-worker -n chatwoot chatwoot-worker="$CHATWOOT_IMAGE" || true
log_success "Image: $CHATWOOT_IMAGE"
echo ""

# 4. Exécuter les migrations
log_info "Étape 4/7 : Exécution des migrations..."
cd "$SCRIPT_DIR"
if [ -f "11_ct_04_run_migrations.sh" ]; then
    bash 11_ct_04_run_migrations.sh
    if [ $? -eq 0 ]; then
        log_success "Migrations terminées"
    else
        log_warning "Migrations échouées, vérifiez les logs"
    fi
else
    log_warning "Script de migrations non trouvé"
fi
echo ""

# 5. Exécuter db:seed
log_info "Étape 5/7 : Exécution db:seed..."
if [ -f "11_ct_04b_run_seed.sh" ]; then
    bash 11_ct_04b_run_seed.sh
    if [ $? -eq 0 ]; then
        log_success "Seed terminé"
    else
        log_warning "Seed échoué, vérifiez les logs"
    fi
else
    log_warning "Script de seed non trouvé"
fi
echo ""

# 6. Redémarrer les Deployments
log_info "Étape 6/7 : Redémarrage des Deployments..."
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
log_success "Redémarrage lancé"
echo ""

log_info "Attente 90 secondes pour le démarrage..."
sleep 90

# 7. Vérifier l'état final
log_info "Étape 7/7 : Vérification état final..."
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
else
    log_warning "⚠️ Certains pods ne sont pas encore Ready"
    log_info "Vérifiez avec: kubectl get pods -n chatwoot -w"
fi

# 8. Générer les rapports
log_info "Génération des rapports de validation..."
if [ -f "validate_module11.sh" ]; then
    bash validate_module11.sh || log_warning "Génération des rapports échouée"
else
    log_warning "Script de validation non trouvé"
fi

echo ""
log_success "✅ Finalisation terminée"
echo ""

