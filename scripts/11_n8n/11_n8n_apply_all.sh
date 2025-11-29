#!/usr/bin/env bash
#
# 11_n8n_apply_all.sh - Script maître pour Module 11 (n8n)
#
# Ce script orchestre l'installation complète de n8n :
# 1. Configuration des credentials
# 2. Déploiement n8n
# 3. Configuration Ingress
# 4. Tests de validation
#
# Usage:
#   ./11_n8n_apply_all.sh [servers.tsv] [--yes]
#
# Options:
#   --yes : Mode non-interactif (pas de confirmation)
#
# Prérequis:
#   - Module 3 installé (PostgreSQL HA)
#   - Module 4 installé (Redis HA)
#   - Module 9 installé (K3s HA)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
NON_INTERACTIVE=false

# Gérer les arguments
TSV_FILE="${INSTALL_DIR}/servers.tsv"
for arg in "$@"; do
    if [[ "${arg}" == "--yes" ]]; then
        NON_INTERACTIVE=true
    elif [[ "${arg}" != "--yes" ]] && [[ -f "${arg}" ]]; then
        TSV_FILE="${arg}"
    fi
done

# Si TSV_FILE n'est pas un fichier, essayer le chemin par défaut
if [[ ! -f "${TSV_FILE}" ]]; then
    TSV_FILE="${INSTALL_DIR}/servers.tsv"
fi

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

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 11 - Installation complète n8n"
echo "=============================================================="
echo ""
echo "Date de démarrage: $(date)"
echo ""

# Vérifier les prérequis
log_info "Vérification des prérequis..."

if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Confirmation
if [[ "${NON_INTERACTIVE}" == "false" ]]; then
    echo ""
    log_warning "Ce script va installer n8n sur le cluster K3s"
    log_warning "Prérequis:"
    log_info "  - Module 3: PostgreSQL HA"
    log_info "  - Module 4: Redis HA"
    log_info "  - Module 9: K3s HA"
    echo ""
    read -p "Continuer ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Installation annulée"
        exit 0
    fi
fi

# Étape 1: Configuration des credentials
log_info "=============================================================="
log_info "Étape 1/4: Configuration des credentials"
log_info "=============================================================="
if ! "${SCRIPT_DIR}/11_n8n_00_setup_credentials.sh" "${TSV_FILE}"; then
    log_error "Échec de la configuration des credentials"
    exit 1
fi
echo ""

# Étape 2: Déploiement n8n
log_info "=============================================================="
log_info "Étape 2/4: Déploiement n8n"
log_info "=============================================================="
if ! "${SCRIPT_DIR}/11_n8n_01_deploy.sh" "${TSV_FILE}"; then
    log_error "Échec du déploiement n8n"
    exit 1
fi
echo ""

# Étape 3: Configuration Ingress
log_info "=============================================================="
log_info "Étape 3/4: Configuration Ingress"
log_info "=============================================================="
if ! "${SCRIPT_DIR}/11_n8n_02_configure_ingress.sh" "${TSV_FILE}"; then
    log_error "Échec de la configuration Ingress"
    exit 1
fi
echo ""

# Étape 4: Tests de validation
log_info "=============================================================="
log_info "Étape 4/4: Tests de validation"
log_info "=============================================================="
if ! "${SCRIPT_DIR}/11_n8n_03_tests.sh" "${TSV_FILE}"; then
    log_warning "Certains tests ont échoué"
    log_warning "Vérifiez les logs pour plus de détails"
    echo ""
fi

# Résumé final
echo ""
echo "=============================================================="
log_success "✅ Installation Module 11 (n8n) terminée"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Namespace: n8n"
log_info "  - Deployment: n8n (3 réplicas, HPA: min=3, max=20)"
log_info "  - Service: n8n (ClusterIP)"
log_info "  - Ingress: n8n.keybuzz.io"
echo ""
log_warning "⚠️  Actions requises:"
log_info "  1. Créer le DNS: n8n.keybuzz.io → IP LB Hetzner"
log_info "  2. Configurer les certificats TLS sur les LB Hetzner"
echo ""
log_info "Documentation:"
log_info "  - README.md: ${SCRIPT_DIR}/README.md"
log_info "  - Validation: ${SCRIPT_DIR}/MODULE11_VALIDATION.md (à créer après tests)"
echo ""

