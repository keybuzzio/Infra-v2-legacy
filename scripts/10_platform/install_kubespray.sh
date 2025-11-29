#!/usr/bin/env bash
#
# install_kubespray.sh - Installation et Configuration de Kubespray
#
# Ce script installe Kubespray et prépare l'inventaire pour déployer
# Kubernetes complet avec Calico IPIP.
#
# Usage:
#   ./install_kubespray.sh
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Python 3 installé
#   - Accès SSH aux nœuds K3s
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBESPRay_DIR="/opt/kubespray"
KUBESPRay_VERSION="${1:-master}"

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
echo " [KeyBuzz] Installation de Kubespray"
echo "=============================================================="
echo ""

# ============================================================
# ÉTAPE 1 : Vérifier les Prérequis
# ============================================================
echo "=============================================================="
log_info "ÉTAPE 1 : Vérification des Prérequis"
echo "=============================================================="
echo ""

# Vérifier Python 3
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    log_success "Python 3 installé : ${PYTHON_VERSION}"
else
    log_error "Python 3 n'est pas installé"
    log_info "Installation de Python 3..."
    apt-get update && apt-get install -y python3 python3-pip
fi

# Vérifier pip3
if command -v pip3 &> /dev/null; then
    log_success "pip3 installé"
else
    log_error "pip3 n'est pas installé"
    log_info "Installation de pip3..."
    apt-get install -y python3-pip
fi

# Vérifier git
if command -v git &> /dev/null; then
    log_success "git installé"
else
    log_error "git n'est pas installé"
    log_info "Installation de git..."
    apt-get install -y git
fi

# ============================================================
# ÉTAPE 2 : Cloner Kubespray
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 2 : Clonage de Kubespray"
echo "=============================================================="
echo ""

if [[ -d "${KUBESPRay_DIR}" ]]; then
    log_warning "Kubespray existe déjà dans ${KUBESPRay_DIR}"
    read -p "Supprimer et réinstaller ? (yes/NO) : " CONFIRM
    if [[ "${CONFIRM}" == "yes" ]]; then
        log_info "Suppression de l'ancienne installation..."
        rm -rf "${KUBESPRay_DIR}"
    else
        log_info "Utilisation de l'installation existante"
    fi
fi

if [[ ! -d "${KUBESPRay_DIR}" ]]; then
    log_info "Clonage de Kubespray (version: ${KUBESPRay_VERSION})..."
    git clone --branch "${KUBESPRay_VERSION}" https://github.com/kubernetes-sigs/kubespray.git "${KUBESPRay_DIR}" || \
    git clone https://github.com/kubernetes-sigs/kubespray.git "${KUBESPRay_DIR}"
    log_success "Kubespray cloné"
else
    log_success "Kubespray déjà présent"
fi

# ============================================================
# ÉTAPE 3 : Installer les Dépendances
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 3 : Installation des Dépendances Python"
echo "=============================================================="
echo ""

cd "${KUBESPRay_DIR}"
log_info "Installation des dépendances depuis requirements.txt..."
pip3 install --upgrade pip
pip3 install -r requirements.txt

log_success "Dépendances installées"

# ============================================================
# ÉTAPE 4 : Créer l'Inventaire
# ============================================================
echo ""
echo "=============================================================="
log_info "ÉTAPE 4 : Création de l'Inventaire"
echo "=============================================================="
echo ""

INVENTORY_DIR="${KUBESPRay_DIR}/inventory/keybuzz"

if [[ -d "${INVENTORY_DIR}" ]]; then
    log_warning "L'inventaire existe déjà dans ${INVENTORY_DIR}"
    read -p "Supprimer et recréer ? (yes/NO) : " CONFIRM
    if [[ "${CONFIRM}" == "yes" ]]; then
        log_info "Suppression de l'ancien inventaire..."
        rm -rf "${INVENTORY_DIR}"
    else
        log_info "Utilisation de l'inventaire existant"
        log_success "Inventaire prêt"
        exit 0
    fi
fi

log_info "Création de l'inventaire à partir de l'exemple..."
cp -rfp "${KUBESPRay_DIR}/inventory/sample" "${INVENTORY_DIR}"

log_success "Inventaire créé dans ${INVENTORY_DIR}"

# ============================================================
# ÉTAPE 5 : Informations pour Configuration
# ============================================================
echo ""
echo "=============================================================="
log_success "✅ Installation de Kubespray Terminée"
echo "=============================================================="
echo ""
log_info "📋 Prochaines Étapes :"
log_info ""
log_info "1. Configurer l'inventaire :"
log_info "   cd ${INVENTORY_DIR}"
log_info "   Éditer hosts.yaml avec :"
log_info "     - 3 masters (10.0.0.100, 10.0.0.101, 10.0.0.102)"
log_info "     - 5 workers (10.0.0.110, 10.0.0.111, 10.0.0.112, 10.0.0.113, 10.0.0.114)"
log_info ""
log_info "2. Configurer Calico IPIP dans group_vars/k8s_cluster/k8s-cluster.yml :"
log_info "   calico_ipip_mode: Always"
log_info "   calico_vxlan_mode: Never"
log_info "   network_plugin: calico"
log_info ""
log_info "3. Lancer le déploiement :"
log_info "   cd ${KUBESPRay_DIR}"
log_info "   ansible-playbook -i inventory/keybuzz/hosts.yaml cluster.yml -b"
echo ""
log_warning "⚠️  Le fichier hosts.yaml doit être généré avec les bonnes IPs et configurations"
log_warning "⚠️  Demander la génération du fichier hosts.yaml complet si nécessaire"
echo ""

