#!/usr/bin/env bash
#
# 00_check_prerequisites.sh - Vérification des prérequis pour l'installation KeyBuzz
#
# Ce script vérifie que tous les prérequis sont en place avant de commencer
# l'installation de l'infrastructure KeyBuzz.
#
# Usage:
#   ./00_check_prerequisites.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - servers.tsv correctement configuré

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# Fonctions utilitaires
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    PASSED_CHECKS=$((PASSED_CHECKS + 1))
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check() {
    local description=$1
    local command=$2
    
    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
    
    if eval "${command}" >/dev/null 2>&1; then
        log_success "${description}"
        return 0
    else
        log_error "${description}"
        return 1
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Vérification des Prérequis"
echo "=============================================================="
echo ""
echo "Répertoire d'installation : ${INSTALL_DIR}"
echo "Fichier d'inventaire      : ${TSV_FILE}"
echo ""

# 1. Vérifications système
echo "--------------------------------------------------------------"
echo "1. Vérifications Système"
echo "--------------------------------------------------------------"

check "OS Ubuntu 24.04" "lsb_release -r | grep -q '24.04'"
check "Utilisateur root" "[ \$(id -u) -eq 0 ]"
check "Docker installé" "command -v docker >/dev/null 2>&1"
check "Docker fonctionnel" "systemctl is-active --quiet docker"
check "Git installé" "command -v git >/dev/null 2>&1"
check "Curl installé" "command -v curl >/dev/null 2>&1"

echo ""

# 2. Vérifications fichiers
echo "--------------------------------------------------------------"
echo "2. Vérifications Fichiers"
echo "--------------------------------------------------------------"

check "Fichier servers.tsv existe" "[ -f \"${TSV_FILE}\" ]"
check "Répertoire scripts existe" "[ -d \"${SCRIPT_DIR}\" ]"
check "Script base_os.sh existe" "[ -f \"${SCRIPT_DIR}/02_base_os_and_security/base_os.sh\" ]"
check "Script apply_base_os_to_all.sh existe" "[ -f \"${SCRIPT_DIR}/02_base_os_and_security/apply_base_os_to_all.sh\" ]"
check "Script maître existe" "[ -f \"${SCRIPT_DIR}/00_master_install.sh\" ]"

echo ""

# 3. Vérifications servers.tsv
echo "--------------------------------------------------------------"
echo "3. Vérifications servers.tsv"
echo "--------------------------------------------------------------"

if [[ -f "${TSV_FILE}" ]]; then
    # Compter les serveurs prod
    PROD_COUNT=$(grep -c "^prod" "${TSV_FILE}" 2>/dev/null || echo "0")
    check "Serveurs prod trouvés (attendu: >0)" "[ ${PROD_COUNT} -gt 0 ]"
    
    # Vérifier les serveurs DB
    DB_COUNT=$(grep -c "db.*postgres" "${TSV_FILE}" 2>/dev/null || echo "0")
    check "Serveurs DB trouvés (attendu: 3)" "[ ${DB_COUNT} -eq 3 ]"
    
    # Vérifier les serveurs HAProxy
    HAPROXY_COUNT=$(grep -c "haproxy" "${TSV_FILE}" 2>/dev/null || echo "0")
    check "Serveurs HAProxy trouvés (attendu: 2)" "[ ${HAPROXY_COUNT} -eq 2 ]"
    
    log_info "Total serveurs prod : ${PROD_COUNT}"
    log_info "Serveurs DB : ${DB_COUNT}"
    log_info "Serveurs HAProxy : ${HAPROXY_COUNT}"
else
    log_error "Fichier servers.tsv introuvable"
fi

echo ""

# 4. Vérifications SSH
echo "--------------------------------------------------------------"
echo "4. Vérifications SSH"
echo "--------------------------------------------------------------"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

if [[ -n "${SSH_KEY_OPTS}" ]]; then
    log_info "Clé SSH détectée : ${SSH_KEY_OPTS}"
else
    log_warning "Aucune clé SSH détectée, utilisation de l'authentification par défaut"
fi

# Tester la connectivité vers les serveurs DB
if [[ -f "${TSV_FILE}" ]]; then
    echo "Test de connectivité vers les serveurs DB..."
    
    while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
        # Skip header
        if [[ "${ENV}" == "ENV" ]]; then
            continue
        fi
        
        # On ne traite que env=prod et ROLE=db
        if [[ "${ENV}" != "prod" ]] || [[ "${ROLE}" != "db" ]]; then
            continue
        fi
        
        if [[ -n "${IP_PRIVEE}" ]]; then
            if ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 \
                -o StrictHostKeyChecking=accept-new "root@${IP_PRIVEE}" "echo OK" >/dev/null 2>&1; then
                log_success "Connectivité SSH vers ${HOSTNAME} (${IP_PRIVEE})"
            else
                log_error "Impossible de se connecter à ${HOSTNAME} (${IP_PRIVEE})"
            fi
        fi
    done < "${TSV_FILE}"
fi

echo ""

# 5. Vérifications configuration
echo "--------------------------------------------------------------"
echo "5. Vérifications Configuration"
echo "--------------------------------------------------------------"

# Vérifier ADMIN_IP dans base_os.sh
if [[ -f "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" ]]; then
    ADMIN_IP=$(grep "^ADMIN_IP=" "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" | cut -d'"' -f2)
    if [[ -n "${ADMIN_IP}" ]]; then
        log_success "ADMIN_IP configuré : ${ADMIN_IP}"
    else
        log_error "ADMIN_IP non configuré dans base_os.sh"
    fi
fi

# Vérifier les permissions des scripts
SCRIPT_COUNT=$(find "${SCRIPT_DIR}" -type f -name "*.sh" | wc -l)
EXECUTABLE_COUNT=$(find "${SCRIPT_DIR}" -type f -name "*.sh" -executable | wc -l)

if [[ ${SCRIPT_COUNT} -eq ${EXECUTABLE_COUNT} ]]; then
    log_success "Tous les scripts sont exécutables (${SCRIPT_COUNT})"
else
    log_warning "${SCRIPT_COUNT} scripts trouvés, ${EXECUTABLE_COUNT} exécutables"
    log_info "Pour corriger : find ${SCRIPT_DIR} -type f -name '*.sh' -exec chmod +x {} \\;"
fi

echo ""

# Résumé final
echo "=============================================================="
echo " [KeyBuzz] Résumé de la Vérification"
echo "=============================================================="
echo ""
echo "Total vérifications : ${TOTAL_CHECKS}"
log_success "Vérifications réussies : ${PASSED_CHECKS}"
log_error "Vérifications échouées : ${FAILED_CHECKS}"
echo ""

if [[ ${FAILED_CHECKS} -eq 0 ]]; then
    echo "=============================================================="
    log_success "✅ TOUS LES PRÉREQUIS SONT VALIDÉS !"
    echo "Vous pouvez maintenant lancer l'installation."
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_error "⚠️  CERTAINS PRÉREQUIS NE SONT PAS VALIDÉS"
    echo "Veuillez corriger les erreurs avant de continuer."
    echo "=============================================================="
    exit 1
fi


