#!/usr/bin/env bash
#
# fix_module11.sh - Corrige les problèmes du Module 11 et finalise l'installation
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
echo " [KeyBuzz] Module 11 - Correction et Finalisation"
echo "=============================================================="
echo ""

# 1. Diagnostic
log_info "Étape 1/8 : Diagnostic des problèmes..."
echo ""

log_info "État actuel des Deployments:"
kubectl get deployments -n chatwoot || true
echo ""

log_info "État actuel des Pods:"
kubectl get pods -n chatwoot || true
echo ""

log_info "Événements récents:"
kubectl get events -n chatwoot --sort-by='.lastTimestamp' | tail -10 || true
echo ""

# 2. Nettoyer les pods en erreur
log_info "Étape 2/8 : Nettoyage des pods en erreur..."
kubectl delete pods -n chatwoot -l app=chatwoot,component=web --grace-period=0 --force 2>/dev/null || true
kubectl delete job -n chatwoot chatwoot-migrations chatwoot-seed 2>/dev/null || true
sleep 5
log_success "Pods nettoyés"
echo ""

# 3. Vérifier ConfigMap et Secrets
log_info "Étape 3/8 : Vérification de la configuration..."
if ! kubectl get configmap chatwoot-config -n chatwoot > /dev/null 2>&1; then
    log_error "ConfigMap chatwoot-config manquant. Exécutez 11_ct_01_prepare_config.sh"
    exit 1
fi

if ! kubectl get secret chatwoot-secrets -n chatwoot > /dev/null 2>&1; then
    log_error "Secret chatwoot-secrets manquant. Exécutez 11_ct_01_prepare_config.sh"
    exit 1
fi

log_success "ConfigMap et Secret présents"
echo ""

# 4. Vérifier l'image Chatwoot
log_info "Étape 4/8 : Vérification de l'image Chatwoot..."
CHATWOOT_IMAGE="chatwoot/chatwoot:latest"
CURRENT_IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo "")

if [ -n "$CURRENT_IMAGE" ] && [ "$CURRENT_IMAGE" != "$CHATWOOT_IMAGE" ]; then
    log_warning "Image actuelle: $CURRENT_IMAGE, mise à jour vers: $CHATWOOT_IMAGE"
    kubectl set image deployment/chatwoot-web -n chatwoot chatwoot-web="$CHATWOOT_IMAGE"
    kubectl set image deployment/chatwoot-worker -n chatwoot chatwoot-worker="$CHATWOOT_IMAGE"
else
    log_success "Image correcte: $CHATWOOT_IMAGE"
fi
echo ""

# 5. Vérifier imagePullSecrets
log_info "Étape 5/8 : Vérification des imagePullSecrets..."
if kubectl get secret ghcr-secret -n chatwoot > /dev/null 2>&1; then
    log_info "Ajout de imagePullSecrets aux Deployments..."
    kubectl patch deployment chatwoot-web -n chatwoot -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}' || true
    kubectl patch deployment chatwoot-worker -n chatwoot -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}' || true
    log_success "imagePullSecrets configurés"
else
    log_warning "Secret ghcr-secret non trouvé (normal si image publique)"
fi
echo ""

# 6. Redémarrer les Deployments
log_info "Étape 6/8 : Redémarrage des Deployments..."
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
log_success "Deployments redémarrés"
echo ""

log_info "Attente du démarrage des pods (60 secondes)..."
sleep 60

log_info "État des pods après redémarrage:"
kubectl get pods -n chatwoot
echo ""

# 7. Vérifier les logs d'un pod web
log_info "Étape 7/8 : Vérification des logs..."
WEB_POD=$(kubectl get pods -n chatwoot -l app=chatwoot,component=web --no-headers 2>/dev/null | head -1 | awk '{print $1}' || echo "")
if [ -n "$WEB_POD" ]; then
    log_info "Logs du pod $WEB_POD (dernières 30 lignes):"
    kubectl logs "$WEB_POD" -n chatwoot --tail=30 2>&1 | head -30 || true
    echo ""
else
    log_warning "Aucun pod web trouvé"
fi

# 8. Vérifier l'état final
log_info "Étape 8/8 : Vérification de l'état final..."
echo ""

WEB_READY=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WEB_DESIRED=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")
WORKER_READY=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
WORKER_DESIRED=$(kubectl get deployment chatwoot-worker -n chatwoot -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "2")

echo "État des Deployments:"
echo "  chatwoot-web: $WEB_READY/$WEB_DESIRED"
echo "  chatwoot-worker: $WORKER_READY/$WORKER_DESIRED"
echo ""

if [ "$WEB_READY" = "$WEB_DESIRED" ] && [ "$WORKER_READY" = "$WORKER_DESIRED" ]; then
    log_success "✅ Tous les pods sont Ready"
else
    log_warning "⚠️ Certains pods ne sont pas encore Ready"
    log_info "Attendez quelques minutes puis vérifiez avec: kubectl get pods -n chatwoot -w"
fi

echo ""
log_success "✅ Correction terminée"
echo ""
log_info "Prochaines étapes:"
log_info "1. Vérifier que tous les pods sont Running: kubectl get pods -n chatwoot"
log_info "2. Relancer les migrations: cd $SCRIPT_DIR && ./11_ct_04_run_migrations.sh"
log_info "3. Exécuter db:seed: cd $SCRIPT_DIR && ./11_ct_04b_run_seed.sh"
log_info "4. Générer les rapports: cd $SCRIPT_DIR && ./validate_module11.sh"
echo ""

