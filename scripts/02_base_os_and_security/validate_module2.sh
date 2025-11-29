#!/usr/bin/env bash
#
# validate_module2.sh - Validation complète du Module 2 sur tous les serveurs
#
# Ce script vérifie que tous les points du Module 2 ont été correctement
# appliqués sur chaque serveur de l'infrastructure.
#
# Usage:
#   ./validate_module2.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH root vers tous les serveurs
#   - servers.tsv correctement configuré

set -uo pipefail

TSV_FILE="${1:-../../servers.tsv}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_FILE="${SCRIPT_DIR}/module2_validation_report_$(date +%Y%m%d_%H%M%S).txt"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Compteurs globaux
TOTAL_SERVERS=0
PASSED_SERVERS=0
FAILED_SERVERS=0
SKIPPED_SERVERS=0

# Fonctions utilitaires
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

# Fonction pour vérifier un point sur un serveur (utilisée pour les checks simples)
check_point() {
    local server_ip=$1
    local check_name=$2
    local check_command=$3
    local ssh_cmd_local="ssh"
    
    if [[ -n "${SSH_KEY_OPTS:-}" ]]; then
        ssh_cmd_local="ssh ${SSH_KEY_OPTS}"
    fi
    
    if ${ssh_cmd_local} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${server_ip}" "${check_command}" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Fonction pour valider un serveur
validate_server() {
    local hostname=$1
    local ip=$2
    local role=$3
    local subrole=$4
    
    TOTAL_SERVERS=$((TOTAL_SERVERS + 1))
    
    echo "--------------------------------------------------------------"
    echo "▶ Validation : ${hostname} (${ip})"
    echo "   Rôle: ${role} / ${subrole}"
    echo "--------------------------------------------------------------"
    
    local failed_checks=0
    local total_checks=0
    local ssh_cmd="ssh"
    
    # Utiliser la clé SSH si disponible
    if [[ -n "${SSH_KEY_OPTS:-}" ]]; then
        ssh_cmd="ssh ${SSH_KEY_OPTS}"
    fi
    
    # Test de connectivité SSH
    if ! ${ssh_cmd} -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new "root@${ip}" "echo 'OK'" >/dev/null 2>&1; then
        log_error "Impossible de se connecter à ${hostname}"
        FAILED_SERVERS=$((FAILED_SERVERS + 1))
        echo "SKIP" >> "${REPORT_FILE}"
        SKIPPED_SERVERS=$((SKIPPED_SERVERS + 1))
        echo ""
        return 1
    fi
    
    # 1. Vérifier Ubuntu 24.04
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "lsb_release -r | grep -q '24.04'" >/dev/null 2>&1; then
        log_success "OS Ubuntu 24.04"
    else
        log_error "OS version incorrecte"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 2. Vérifier Docker installé
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "command -v docker >/dev/null 2>&1 && docker --version" >/dev/null 2>&1; then
        log_success "Docker installé"
    else
        log_error "Docker non installé"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 3. Vérifier Docker fonctionnel
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "systemctl is-active --quiet docker" >/dev/null 2>&1; then
        log_success "Docker actif"
    else
        log_error "Docker non actif"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 4. Vérifier swap désactivé
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "! swapon --summary | grep -q ." >/dev/null 2>&1; then
        log_success "Swap désactivé"
    else
        log_error "Swap activé"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 5. Vérifier swap dans fstab
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "! grep -q swap /etc/fstab 2>/dev/null" >/dev/null 2>&1; then
        log_success "Swap retiré de fstab"
    else
        log_error "Swap présent dans fstab"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 6. Vérifier UFW activé
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "ufw status | grep -q 'Status: active'" >/dev/null 2>&1; then
        log_success "UFW activé"
    else
        log_error "UFW non activé"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 7. Vérifier réseau privé autorisé dans UFW
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "ufw status | grep -q '10.0.0.0/16'" >/dev/null 2>&1; then
        log_success "Réseau privé autorisé dans UFW"
    else
        log_error "Réseau privé non autorisé dans UFW"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 8. Vérifier SSH durci
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "test -f /etc/ssh/sshd_config.d/99-keybuzz.conf" >/dev/null 2>&1; then
        log_success "Configuration SSH durcie présente"
    else
        log_error "Configuration SSH durcie absente"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 9. Vérifier PasswordAuthentication no
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config.d/99-keybuzz.conf 2>/dev/null" >/dev/null 2>&1; then
        log_success "Authentification par mot de passe désactivée"
    else
        log_error "Authentification par mot de passe activée"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 10. Vérifier DNS configuré
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "grep -q '1.1.1.1\|8.8.8.8' /etc/resolv.conf 2>/dev/null" >/dev/null 2>&1; then
        log_success "DNS configuré (1.1.1.1 ou 8.8.8.8)"
    else
        log_error "DNS non configuré"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 11. Vérifier sysctl optimisations
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "test -f /etc/sysctl.d/99-keybuzz.conf" >/dev/null 2>&1; then
        log_success "Optimisations sysctl présentes"
    else
        log_error "Optimisations sysctl absentes"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 12. Vérifier timezone
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "timedatectl | grep -q 'Europe/Paris'" >/dev/null 2>&1; then
        log_success "Timezone Europe/Paris"
    else
        log_error "Timezone incorrecte"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 13. Vérifier NTP activé
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "timedatectl | grep -q 'NTP service: active'" >/dev/null 2>&1; then
        log_success "NTP activé"
    else
        log_error "NTP non activé"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 14. Vérifier journald configuré
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "test -f /etc/systemd/journald.conf.d/limit.conf" >/dev/null 2>&1; then
        log_success "Configuration journald présente"
    else
        log_error "Configuration journald absente"
        failed_checks=$((failed_checks + 1))
    fi
    
    # 15. Vérifier paquets de base installés
    total_checks=$((total_checks + 1))
    if ${ssh_cmd} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
        "root@${ip}" "command -v curl >/dev/null 2>&1 && command -v wget >/dev/null 2>&1 && command -v jq >/dev/null 2>&1" >/dev/null 2>&1; then
        log_success "Paquets de base installés"
    else
        log_error "Paquets de base manquants"
        failed_checks=$((failed_checks + 1))
    fi
    
    # Résumé pour ce serveur
    echo ""
    if [[ ${failed_checks} -eq 0 ]]; then
        log_success "${hostname} : ${total_checks}/${total_checks} vérifications réussies"
        PASSED_SERVERS=$((PASSED_SERVERS + 1))
        echo "PASS (${total_checks}/${total_checks})" >> "${REPORT_FILE}"
    else
        log_error "${hostname} : ${failed_checks} échec(s) sur ${total_checks} vérifications"
        FAILED_SERVERS=$((FAILED_SERVERS + 1))
        echo "FAIL (${failed_checks}/${total_checks})" >> "${REPORT_FILE}"
    fi
    echo ""
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Validation Module 2 - Base OS & Sécurité"
echo "=============================================================="
echo ""
echo "Fichier d'inventaire : ${TSV_FILE}"
echo "Rapport : ${REPORT_FILE}"
echo ""

# Initialiser le rapport
echo "Rapport de validation Module 2 - $(date)" > "${REPORT_FILE}"
echo "==============================================================" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

export SSH_KEY_OPTS

# Lire le fichier TSV
exec 3< "${TSV_FILE}"

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    # Skip header
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    # On ne traite que env=prod
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    # Ignorer install-01 (ne peut pas se valider lui-même)
    if [[ "${HOSTNAME}" == "install-01" ]]; then
        log_warning "install-01 ignoré (serveur d'orchestration)"
        continue
    fi
    
    TARGET_IP="${IP_PRIVEE}"
    
    if [[ -z "${TARGET_IP}" ]]; then
        log_warning "IP privée vide pour ${HOSTNAME}, on saute."
        continue
    fi
    
    validate_server "${HOSTNAME}" "${TARGET_IP}" "${ROLE}" "${SUBROLE}"
done

exec 3<&-

# Résumé final
echo "=============================================================="
echo " [KeyBuzz] Résumé de la validation"
echo "=============================================================="
echo ""
echo "Total serveurs validés : ${TOTAL_SERVERS}"
log_success "Serveurs validés avec succès : ${PASSED_SERVERS}"
log_error "Serveurs avec échecs : ${FAILED_SERVERS}"
log_warning "Serveurs ignorés/sautés : ${SKIPPED_SERVERS}"
echo ""
echo "Rapport détaillé : ${REPORT_FILE}"
echo ""

# Ajouter le résumé au rapport
echo "" >> "${REPORT_FILE}"
echo "==============================================================" >> "${REPORT_FILE}"
echo "Résumé" >> "${REPORT_FILE}"
echo "==============================================================" >> "${REPORT_FILE}"
echo "Total serveurs : ${TOTAL_SERVERS}" >> "${REPORT_FILE}"
echo "Succès : ${PASSED_SERVERS}" >> "${REPORT_FILE}"
echo "Échecs : ${FAILED_SERVERS}" >> "${REPORT_FILE}"
echo "Ignorés : ${SKIPPED_SERVERS}" >> "${REPORT_FILE}"
echo "" >> "${REPORT_FILE}"
echo "Date de fin : $(date)" >> "${REPORT_FILE}"

if [[ ${FAILED_SERVERS} -eq 0 ]]; then
    echo "=============================================================="
    log_success "✅ TOUS LES SERVEURS SONT VALIDÉS !"
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    log_error "⚠️  CERTAINS SERVEURS ONT DES ÉCHECS"
    echo "Consultez le rapport pour plus de détails."
    echo "=============================================================="
    exit 1
fi

