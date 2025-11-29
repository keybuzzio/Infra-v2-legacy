#!/usr/bin/env bash
#
# 00_prepare_install.sh - Préparation de l'environnement d'installation KeyBuzz
#
# Ce script prépare l'environnement après décompression de l'archive.
# Il doit être exécuté depuis /tmp/keybuzz-installer après décompression.
#
# Usage:
#   ./00_prepare_install.sh
#
# Prérequis:
#   - Archive décompressée dans /tmp/keybuzz-installer
#   - Exécuter en root

set -euo pipefail

SOURCE_DIR="/tmp/keybuzz-installer"
TARGET_DIR="/opt/keybuzz-installer"

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
echo " [KeyBuzz] Préparation de l'Installation"
echo "=============================================================="
echo ""

# Vérifier qu'on est root
if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Ce script doit être exécuté en root"
    exit 1
fi

# Vérifier que le répertoire source existe
if [[ ! -d "${SOURCE_DIR}" ]]; then
    log_error "Répertoire source introuvable : ${SOURCE_DIR}"
    log_info "Veuillez décompresser l'archive dans /tmp/keybuzz-installer"
    exit 1
fi

log_info "Répertoire source : ${SOURCE_DIR}"
log_info "Répertoire cible  : ${TARGET_DIR}"
echo ""

# Créer le répertoire cible
log_info "Création du répertoire cible..."
mkdir -p "${TARGET_DIR}"
log_success "Répertoire créé : ${TARGET_DIR}"

# Copier les fichiers
log_info "Copie des fichiers..."
cp -r "${SOURCE_DIR}"/* "${TARGET_DIR}/"
log_success "Fichiers copiés"

# Configurer les permissions
log_info "Configuration des permissions..."
find "${TARGET_DIR}/scripts" -type f -name "*.sh" -exec chmod +x {} \;
chown -R root:root "${TARGET_DIR}"
log_success "Permissions configurées"

# Vérifier la structure
log_info "Vérification de la structure..."
REQUIRED_FILES=(
    "servers.tsv"
    "scripts/00_master_install.sh"
    "scripts/00_check_prerequisites.sh"
    "scripts/02_base_os_and_security/base_os.sh"
    "scripts/02_base_os_and_security/apply_base_os_to_all.sh"
    "scripts/02_base_os_and_security/validate_module2.sh"
    "INSTALLATION_PROCESS.md"
    "INSTALLATION_CHECKPOINT.md"
    "INSTALL_FROM_ARCHIVE.md"
)

MISSING_FILES=0
for file in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "${TARGET_DIR}/${file}" ]]; then
        log_error "Fichier manquant : ${file}"
        MISSING_FILES=$((MISSING_FILES + 1))
    else
        log_success "Fichier présent : ${file}"
    fi
done

if [[ ${MISSING_FILES} -gt 0 ]]; then
    log_error "${MISSING_FILES} fichier(s) manquant(s)"
    exit 1
fi

echo ""

# Résumé
echo "=============================================================="
log_success "✅ Préparation terminée avec succès !"
echo "=============================================================="
echo ""
echo "Prochaines étapes :"
echo "  1. cd ${TARGET_DIR}"
echo "  2. ./scripts/00_check_prerequisites.sh"
echo "  3. Vérifier/corriger servers.tsv si nécessaire"
echo "  4. Vérifier ADMIN_IP dans scripts/02_base_os_and_security/base_os.sh"
echo "  5. ./scripts/00_master_install.sh"
echo ""
echo "Documentation :"
echo "  - Guide d'installation : ${TARGET_DIR}/INSTALL_FROM_ARCHIVE.md"
echo "  - Checkpoints : ${TARGET_DIR}/INSTALLATION_CHECKPOINT.md"
echo ""

