#!/usr/bin/env bash
#
# create_ghcr_secret.sh - Crée un Secret Kubernetes pour accéder à GHCR
#
# Usage:
#   ./create_ghcr_secret.sh [GITHUB_TOKEN]
#
# Prérequis:
#   - Token GitHub avec permissions: read:packages
#   - kubeconfig configuré
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Token GitHub (peut être passé en argument ou via variable d'environnement)
GITHUB_TOKEN="${1:-${GITHUB_TOKEN:-}}"

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
echo " [KeyBuzz] Création du Secret GHCR pour Kubernetes"
echo "=============================================================="
echo ""

# Vérifier si le token est fourni
if [ -z "$GITHUB_TOKEN" ]; then
    log_error "Token GitHub non fourni"
    echo ""
    log_info "Usage:"
    echo "  ./create_ghcr_secret.sh <GITHUB_TOKEN>"
    echo ""
    log_info "Ou définir la variable d'environnement:"
    echo "  export GITHUB_TOKEN=ghp_xxxxx"
    echo "  ./create_ghcr_secret.sh"
    echo ""
    log_info "Pour créer un token GitHub:"
    echo "  1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)"
    echo "  2. Generate new token (classic)"
    echo "  3. Permissions: read:packages"
    echo "  4. Copier le token (ghp_xxxxx)"
    exit 1
fi

# Vérifier le format du token
if [[ ! "$GITHUB_TOKEN" =~ ^ghp_ ]]; then
    log_warning "Le token ne commence pas par 'ghp_'. Vérifiez qu'il s'agit bien d'un Personal Access Token."
    read -p "Continuer quand même ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Annulé"
        exit 0
    fi
fi

log_info "Création du Secret Kubernetes pour GHCR..."

# Créer le Secret Docker Registry
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=keybuzz \
  --docker-password="${GITHUB_TOKEN}" \
  --docker-email=keybuzz@keybuzz.io \
  --namespace=keybuzz \
  --dry-run=client -o yaml | kubectl apply -f -

log_success "Secret 'ghcr-secret' créé dans le namespace 'keybuzz'"

# Ajouter le Secret aux ServiceAccounts des Deployments
log_info "Ajout du Secret aux ServiceAccounts..."

# ServiceAccount pour keybuzz-api
kubectl patch serviceaccount default -n keybuzz -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}' || \
kubectl patch serviceaccount keybuzz-api -n keybuzz -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}' 2>/dev/null || true

# ServiceAccount pour keybuzz-ui
kubectl patch serviceaccount keybuzz-ui -n keybuzz -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}' 2>/dev/null || true

# ServiceAccount pour keybuzz-my-ui
kubectl patch serviceaccount keybuzz-my-ui -n keybuzz -p '{"imagePullSecrets":[{"name":"ghcr-secret"}]}' 2>/dev/null || true

log_success "ServiceAccounts mis à jour"

# Alternative : Ajouter imagePullSecrets directement aux Deployments
log_info "Ajout de imagePullSecrets aux Deployments..."

kubectl patch deployment keybuzz-api -n keybuzz -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}'
kubectl patch deployment keybuzz-ui -n keybuzz -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}'
kubectl patch deployment keybuzz-my-ui -n keybuzz -p '{"spec":{"template":{"spec":{"imagePullSecrets":[{"name":"ghcr-secret"}]}}}}'

log_success "Deployments mis à jour avec imagePullSecrets"

# Supprimer les pods en erreur pour forcer le redémarrage
log_info "Suppression des pods en erreur pour forcer le redémarrage..."
kubectl delete pod -n keybuzz -l app=keybuzz-api --field-selector=status.phase!=Running 2>/dev/null || true
kubectl delete pod -n keybuzz -l app=keybuzz-ui --field-selector=status.phase!=Running 2>/dev/null || true
kubectl delete pod -n keybuzz -l app=keybuzz-my-ui --field-selector=status.phase!=Running 2>/dev/null || true

# Attendre un peu pour que les nouveaux pods démarrent
log_info "Attente de 10 secondes pour le démarrage des nouveaux pods..."
sleep 10

echo ""
log_success "✅ Configuration terminée"
log_info "Les pods vont maintenant pouvoir pull les images depuis GHCR"
log_info "Vérifiez l'état avec: kubectl get pods -n keybuzz -w"
echo ""
log_info "État actuel des pods:"
kubectl get pods -n keybuzz
echo ""

