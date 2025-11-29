#!/usr/bin/env bash
#
# Fix Ingress timeout pour Chatwoot
# Le problème : NGINX Ingress timeout après 5s par défaut
# Solution : Augmenter les timeouts et ajouter proxy-connect-timeout
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║    Fix Ingress Timeout pour Chatwoot                             ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""

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

log_info "Mise à jour de l'Ingress avec des timeouts augmentés..."

kubectl annotate ingress chatwoot-ingress -n chatwoot \
    nginx.ingress.kubernetes.io/proxy-connect-timeout="60" \
    nginx.ingress.kubernetes.io/proxy-send-timeout="60" \
    nginx.ingress.kubernetes.io/proxy-read-timeout="60" \
    --overwrite

log_success "Annotations Ingress mises à jour"

log_info "Vérification de la configuration..."
kubectl get ingress chatwoot-ingress -n chatwoot -o yaml | grep -A 1 "proxy.*timeout"

log_info "Attente de la synchronisation NGINX (10s)..."
sleep 10

log_info "Test de connectivité..."
log_info "Vous pouvez maintenant tester : curl -v https://support.keybuzz.io"

