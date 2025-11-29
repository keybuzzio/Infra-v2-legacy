#!/usr/bin/env bash
#
# update_platform_images.sh - Met à jour les images Docker des Deployments Platform
#
# Usage:
#   ./update_platform_images.sh [API_IMAGE] [UI_IMAGE] [MY_IMAGE]
#
# Exemples:
#   ./update_platform_images.sh ghcr.io/keybuzz/platform-api:latest ghcr.io/keybuzz/platform-ui:latest ghcr.io/keybuzz/platform-my:latest
#   ./update_platform_images.sh registry.keybuzz.io/api:v1.0.0 registry.keybuzz.io/ui:v1.0.0 registry.keybuzz.io/my:v1.0.0
#
# Prérequis:
#   - Module 10 déployé
#   - kubeconfig configuré
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Images par défaut (exemples - à remplacer par les vraies)
PLATFORM_API_IMAGE="${1:-ghcr.io/keybuzz/platform-api:latest}"
PLATFORM_UI_IMAGE="${2:-ghcr.io/keybuzz/platform-ui:latest}"
PLATFORM_MY_IMAGE="${3:-ghcr.io/keybuzz/platform-my:latest}"

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

export KUBECONFIG=/root/.kube/config

echo "=============================================================="
echo " [KeyBuzz] Module 10 - Mise à jour des images Platform"
echo "=============================================================="
echo ""
log_info "Images à utiliser:"
log_info "  API: ${PLATFORM_API_IMAGE}"
log_info "  UI: ${PLATFORM_UI_IMAGE}"
log_info "  My: ${PLATFORM_MY_IMAGE}"
echo ""

# Confirmation
read -p "Continuer avec ces images ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Annulé"
    exit 0
fi

# 1. Mettre à jour l'API
log_info "Mise à jour du Deployment keybuzz-api..."
kubectl set image deployment/keybuzz-api -n keybuzz api="${PLATFORM_API_IMAGE}"
log_success "Deployment keybuzz-api mis à jour"

# 2. Mettre à jour l'UI
log_info "Mise à jour du Deployment keybuzz-ui..."
kubectl set image deployment/keybuzz-ui -n keybuzz ui="${PLATFORM_UI_IMAGE}"
log_success "Deployment keybuzz-ui mis à jour"

# 3. Mettre à jour My
log_info "Mise à jour du Deployment keybuzz-my-ui..."
kubectl set image deployment/keybuzz-my-ui -n keybuzz my-ui="${PLATFORM_MY_IMAGE}"
log_success "Deployment keybuzz-my-ui mis à jour"

echo ""
log_info "Attente du redéploiement (30 secondes)..."
sleep 30

echo ""
log_info "Vérification de l'état des pods..."
kubectl get pods -n keybuzz

echo ""
log_info "Vérification des Deployments..."
kubectl get deployments -n keybuzz

echo ""
log_success "✅ Mise à jour des images terminée"
log_info "Les pods vont redémarrer avec les nouvelles images"
log_info "Vérifiez l'état avec: kubectl get pods -n keybuzz -w"
echo ""

