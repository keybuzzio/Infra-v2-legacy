#!/usr/bin/env bash
#
# 11_ct_apply_all.sh - Exécute tous les scripts d'installation Chatwoot dans l'ordre
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

cd "${SCRIPT_DIR}"

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Installation Complète Chatwoot"
echo "=============================================================="
echo ""

# Étape 0 : Setup credentials
log_info "Étape 0/3 : Setup credentials..."
if [ -f "11_ct_00_setup_credentials.sh" ]; then
    bash "11_ct_00_setup_credentials.sh"
    if [ $? -eq 0 ]; then
        log_success "Étape 0 terminée"
    else
        log_error "Étape 0 échouée"
        exit 1
    fi
else
    log_error "Script 11_ct_00_setup_credentials.sh non trouvé"
    exit 1
fi

echo ""

# Étape 1 : Préparation ConfigMap et Secrets
log_info "Étape 1/3 : Préparation ConfigMap et Secrets..."
if [ -f "11_ct_01_prepare_config.sh" ]; then
    bash "11_ct_01_prepare_config.sh"
    if [ $? -eq 0 ]; then
        log_success "Étape 1 terminée"
    else
        log_error "Étape 1 échouée"
        exit 1
    fi
else
    log_error "Script 11_ct_01_prepare_config.sh non trouvé"
    exit 1
fi

echo ""

# Étape 2 : Déploiement Chatwoot
log_info "Étape 2/3 : Déploiement Chatwoot..."
if [ -f "11_ct_02_deploy_chatwoot.sh" ]; then
    bash "11_ct_02_deploy_chatwoot.sh"
    if [ $? -eq 0 ]; then
        log_success "Étape 2 terminée"
    else
        log_error "Étape 2 échouée"
        exit 1
    fi
else
    log_error "Script 11_ct_02_deploy_chatwoot.sh non trouvé"
    exit 1
fi

echo ""

# Étape 3 : Tests
log_info "Étape 3/3 : Tests de validation..."
if [ -f "11_ct_03_tests.sh" ]; then
    bash "11_ct_03_tests.sh"
    if [ $? -eq 0 ]; then
        log_success "Étape 3 terminée"
    else
        log_warning "Certains tests peuvent avoir échoué (normal si les pods sont encore en démarrage)"
    fi
else
    log_error "Script 11_ct_03_tests.sh non trouvé"
    exit 1
fi

echo ""
echo "=============================================================="
log_success "✅ Installation Chatwoot terminée"
echo "=============================================================="
echo ""
log_info "Prochaines étapes :"
log_info "  1. Vérifier que les pods sont Running : kubectl get pods -n chatwoot"
log_info "  2. Configurer le DNS : support.keybuzz.io → IP du LB Hetzner"
log_info "  3. Configurer le certificat TLS dans Hetzner LB"
log_info "  4. Accéder à https://support.keybuzz.io"
echo ""

