#!/usr/bin/env bash
#
# 09_k3s_apply_all.sh - Script master pour l'installation complète du Module 9
#
# Ce script orchestre l'installation complète de K3s HA Core :
#   1. Préparation des nœuds K3s
#   2. Installation control-plane HA
#   3. Join des workers
#   4. Bootstrap addons
#   5. Ingress NGINX DaemonSet
#   6. Préparation applications (namespaces + ConfigMap)
#   7. Installation monitoring
#   8. Préparation Vault (namespace)
#   9. Validation finale
#
# Usage:
#   ./09_k3s_apply_all.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 2 appliqué sur tous les nœuds K3s
#   - Modules 3-8 installés (services backend)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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
echo " [KeyBuzz] Module 9 - Installation Complète K3s HA Core"
echo "=============================================================="
echo ""
echo "Ce script va installer :"
echo "  1. Préparation des nœuds K3s"
echo "  2. Installation control-plane HA (3 masters)"
echo "  3. Join des workers"
echo "  4. Bootstrap addons (CoreDNS, metrics-server, StorageClass)"
echo "  5. Ingress NGINX DaemonSet (CRITIQUE)"
echo "  6. Préparation applications (namespaces + ConfigMap)"
echo "  7. Installation monitoring (Prometheus Stack)"
echo "  8. Préparation Vault (namespace)"
echo "  9. Validation finale"
echo ""
log_warning "NOTE: Les applications (KeyBuzz API, Chatwoot, n8n, etc.)"
log_warning "      seront déployées dans des modules séparés (10-15)"
echo ""

# Confirmation
if [[ "${AUTO_YES}" != "--yes" ]]; then
    # Gérer le mode non-interactif
    NON_INTERACTIVE=false
    for arg in "$@"; do
        if [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
            NON_INTERACTIVE=true
            break
        fi
    done
    
    if [[ "${NON_INTERACTIVE}" == "false" ]]; then
        read -p "Continuer ? (o/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
            log_info "Installation annulée"
            exit 0
        fi
    else
        log_info "Mode non-interactif activé, continuation automatique..."
    fi
fi

# Étape 1: Préparation
log_info "============================================================="
log_info "Étape 1/9 : Préparation des nœuds K3s"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_01_prepare.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de la préparation des nœuds"
    exit 1
fi
log_success "Nœuds préparés"
echo ""

# Étape 2: Control-plane
log_info "============================================================="
log_info "Étape 2/9 : Installation control-plane HA"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_02_install_control_plane.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de l'installation du control-plane"
    exit 1
fi
log_success "Control-plane HA installé"
echo ""

# Attendre la stabilisation
log_info "Attente de la stabilisation du control-plane (20 secondes)..."
sleep 20

# Étape 3: Join workers
log_info "============================================================="
log_info "Étape 3/9 : Join des workers"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_03_join_workers.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Échec du join des workers (peut être normal si aucun worker)"
    log_warning "Vérifiez servers.tsv pour les workers"
fi
log_success "Workers joints (si présents)"
echo ""

# Attendre la stabilisation
log_info "Attente de la stabilisation (15 secondes)..."
sleep 15

# Étape 4: Bootstrap addons
log_info "============================================================="
log_info "Étape 4/9 : Bootstrap addons"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_04_bootstrap_addons.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Certains addons ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
log_success "Addons bootstrap configurés"
echo ""

# Étape 5: Ingress DaemonSet
log_info "============================================================="
log_info "Étape 5/9 : Ingress NGINX DaemonSet (CRITIQUE)"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_05_ingress_daemonset.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_error "Échec de l'installation Ingress DaemonSet"
    exit 1
fi
log_success "Ingress NGINX DaemonSet installé"
echo ""

# Étape 6: Préparation applications
log_info "============================================================="
log_info "Étape 6/9 : Préparation applications"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_06_deploy_core_apps.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Échec de la préparation des applications"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
log_success "Environnement préparé pour applications"
echo ""

# Étape 7: Monitoring
log_info "============================================================="
log_info "Étape 7/9 : Installation monitoring"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_07_install_monitoring.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Installation monitoring échouée ou en cours"
    log_warning "Vérifiez manuellement: kubectl get pods -n monitoring"
fi
log_success "Monitoring installé (ou en cours)"
echo ""

# Étape 8: Préparation Vault
log_info "============================================================="
log_info "Étape 8/9 : Préparation Vault"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_08_install_vault_agent.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Échec de la préparation Vault"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
log_success "Environnement Vault préparé"
echo ""

# Étape 9: Validation
log_info "============================================================="
log_info "Étape 9/9 : Validation finale"
log_info "============================================================="
"${SCRIPT_DIR}/09_k3s_09_final_validation.sh" "${TSV_FILE}"
if [ $? -ne 0 ]; then
    log_warning "Certains tests de validation ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
fi
echo ""

# Résumé final
echo "=============================================================="
log_success "✅ Installation du Module 9 (K3s HA Core) terminée !"
echo "=============================================================="
echo ""
log_info "K3s HA Core est maintenant opérationnel."
log_info ""
log_info "Composants installés:"
log_info "  - Control-plane HA: 3 masters"
log_info "  - Workers: Joints au cluster"
log_info "  - Addons: CoreDNS, metrics-server, StorageClass"
log_info "  - Ingress: NGINX DaemonSet (hostNetwork=true)"
log_info "  - Namespaces: keybuzz, chatwoot, n8n, analytics, ai, vault, monitoring"
log_info "  - ConfigMap: keybuzz-backend-services (endpoints services)"
log_info "  - Monitoring: Prometheus Stack (si installé)"
echo ""
log_warning "PROCHAINES ÉTAPES - Applications (modules séparés):"
log_warning "  - Module 10: KeyBuzz API & Front"
log_warning "  - Module 11: Chatwoot"
log_warning "  - Module 12: n8n"
log_warning "  - Module 13: Superset"
log_warning "  - Module 14: Vault Agent"
log_warning "  - Module 15: LiteLLM & Services IA"
echo ""
log_info "Pour vérifier le cluster:"
log_info "  kubectl get nodes"
log_info "  kubectl get pods -A"
log_info "  kubectl get daemonset -n ingress-nginx"
echo ""

