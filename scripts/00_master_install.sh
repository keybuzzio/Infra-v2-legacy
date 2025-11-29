#!/usr/bin/env bash
#
# 00_master_install.sh - Script maître d'installation KeyBuzz
#
# Ce script orchestre l'installation complète de l'infrastructure KeyBuzz
# en lançant les modules dans le bon ordre.
#
# Usage:
#   ./00_master_install.sh [--skip-module-2] [--module N] [--help]
#
# Options:
#   --skip-module-2    : Ignore le Module 2 (si déjà appliqué)
#   --module N         : Lance uniquement le module N
#   --help             : Affiche cette aide
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH root vers tous les serveurs
#   - servers.tsv correctement configuré
#   - ADMIN_IP configuré dans base_os.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${INSTALL_DIR}/servers.tsv"
LOG_DIR="${INSTALL_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Fonctions utilitaires
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Créer le répertoire de logs
mkdir -p "${LOG_DIR}"

# Afficher le header
echo "=============================================================="
echo " [KeyBuzz] Installation Maître - Infrastructure Complète"
echo "=============================================================="
echo ""
echo "Date de démarrage: $(date)"
echo "Répertoire: ${INSTALL_DIR}"
echo "Logs: ${LOG_DIR}"
echo ""

# Vérifier les prérequis
log_info "Vérification des prérequis..."

if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
    log_error "Ce script doit être exécuté en root."
    exit 1
fi

log_success "Prérequis validés"
echo ""

# Fonction pour exécuter un module
run_module() {
    local module_num=$1
    local module_name=$2
    local script_path=$3
    
    log_info "=============================================================="
    log_info "Module ${module_num}: ${module_name}"
    log_info "=============================================================="
    
    if [[ ! -f "${script_path}" ]]; then
        log_warning "Script introuvable: ${script_path}"
        log_warning "Module ${module_num} ignoré"
        return 1
    fi
    
    if [[ ! -x "${script_path}" ]]; then
        chmod +x "${script_path}"
    fi
    
    local log_file="${LOG_DIR}/module_${module_num}_${TIMESTAMP}.log"
    
    log_info "Lancement du module ${module_num}..."
    log_info "Log: ${log_file}"
    echo ""
    
    if "${script_path}" 2>&1 | tee "${log_file}"; then
        log_success "Module ${module_num} terminé avec succès"
        echo ""
        return 0
    else
        log_error "Module ${module_num} a échoué"
        log_error "Consulter le log: ${log_file}"
        echo ""
        return 1
    fi
}

# Traitement des arguments
SKIP_MODULE_2=false
MODULE_ONLY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-module-2)
            SKIP_MODULE_2=true
            shift
            ;;
        --module)
            MODULE_ONLY="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-module-2    Ignore le Module 2 (si déjà appliqué)"
            echo "  --module N         Lance uniquement le module N"
            echo "  --help             Affiche cette aide"
            echo ""
            echo "Modules disponibles:"
            echo "  2  - Base OS & Sécurité (OBLIGATOIRE EN PREMIER)"
            echo "  3  - PostgreSQL HA"
            echo "  4  - Redis HA"
            echo "  5  - RabbitMQ HA"
            echo "  6  - MinIO"
            echo "  7  - MariaDB Galera"
            echo "  8  - ProxySQL Avancé & Optimisation Galera"
            echo "  9  - K3s HA"
            echo "  10 - KeyBuzz API & Front"
            echo "  11 - n8n (Workflow Automation)"
            exit 0
            ;;
        *)
            log_error "Option inconnue: $1"
            echo "Utilisez --help pour voir l'aide"
            exit 1
            ;;
    esac
done

# Si un module spécifique est demandé
if [[ -n "${MODULE_ONLY}" ]]; then
    case "${MODULE_ONLY}" in
        2)
            run_module "2" "Base OS & Sécurité" \
                "${SCRIPT_DIR}/02_base_os_and_security/apply_base_os_to_all.sh ${TSV_FILE}"
            ;;
        3)
            if [[ -f "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh" ]]; then
                run_module "3" "PostgreSQL HA" \
                    "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh ${TSV_FILE}"
            else
                log_error "Script Module 3 introuvable"
                exit 1
            fi
            ;;
        4)
            if [[ -f "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh" ]]; then
                run_module "4" "Redis HA" \
                    "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh ${TSV_FILE}"
            else
                log_error "Script Module 4 introuvable"
                exit 1
            fi
            ;;
        5)
            if [[ -f "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh" ]]; then
                if ! run_module "5" "RabbitMQ HA" \
                    "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh ${TSV_FILE}"; then
                    log_error "Le Module 5 a échoué. Installation arrêtée."
                    exit 1
                fi
            else
                log_error "Script Module 5 introuvable"
                exit 1
            fi
            ;;
        6)
            if [[ -f "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh" ]]; then
                if ! run_module "6" "MinIO S3 HA" \
                    "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh ${TSV_FILE}"; then
                    log_error "Le Module 6 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 6 introuvable"
                exit 1
            fi
            ;;
        7)
            if [[ -f "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh" ]]; then
                if ! run_module "7" "MariaDB Galera HA" \
                    "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh ${TSV_FILE} --yes"; then
                    log_error "Le Module 7 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 7 introuvable"
                exit 1
            fi
            ;;
        8)
            if [[ -f "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh" ]]; then
                if ! "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh ${TSV_FILE} --yes"; then
                    log_error "Le Module 8 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 8 introuvable"
                exit 1
            fi
            ;;
        9)
            if [[ -f "${SCRIPT_DIR}/09_k3s_ha/09_k3s_apply_all.sh" ]]; then
                if ! "${SCRIPT_DIR}/09_k3s_ha/09_k3s_apply_all.sh ${TSV_FILE} --yes"; then
                    log_error "Le Module 9 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 9 introuvable"
                exit 1
            fi
            ;;
        10)
            log_info "Installation du Module 10: KeyBuzz API & Front"
            if [[ -f "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_apply_all.sh" ]]; then
                if ! "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_apply_all.sh ${TSV_FILE} --yes"; then
                    log_error "Le Module 10 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 10 introuvable"
                exit 1
            fi
            ;;
        11)
            log_info "Installation du Module 11: n8n (Workflow Automation)"
            if [[ -f "${SCRIPT_DIR}/11_n8n/11_n8n_apply_all.sh" ]]; then
                if ! "${SCRIPT_DIR}/11_n8n/11_n8n_apply_all.sh ${TSV_FILE} --yes"; then
                    log_error "Le Module 11 a échoué"
                    exit 1
                fi
            else
                log_error "Script Module 11 introuvable"
                exit 1
            fi
            ;;
        *)
            log_error "Module inconnu: ${MODULE_ONLY}"
            exit 1
            ;;
    esac
    exit $?
fi

# Installation complète dans l'ordre
log_info "Démarrage de l'installation complète KeyBuzz"
echo ""

# Module 2 : Base OS & Sécurité (OBLIGATOIRE)
if [[ "${SKIP_MODULE_2}" == "false" ]]; then
    if ! run_module "2" "Base OS & Sécurité" \
        "${SCRIPT_DIR}/02_base_os_and_security/apply_base_os_to_all.sh ${TSV_FILE}"; then
        log_error "Le Module 2 est obligatoire. Installation arrêtée."
        exit 1
    fi
    
    # Validation du Module 2
    log_info "Validation du Module 2..."
    if [[ -f "${SCRIPT_DIR}/02_base_os_and_security/validate_module2.sh" ]]; then
        if "${SCRIPT_DIR}/02_base_os_and_security/validate_module2.sh" "${TSV_FILE}"; then
            log_success "Module 2 validé avec succès"
        else
            log_warning "Module 2 : certains serveurs ont des échecs de validation"
            log_warning "Consultez le rapport de validation pour plus de détails"
            read -p "Continuer malgré les échecs ? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Installation arrêtée par l'utilisateur"
                exit 1
            fi
        fi
    else
        log_warning "Script de validation non trouvé, validation ignorée"
    fi
    echo ""
else
    log_warning "Module 2 ignoré (--skip-module-2)"
    echo ""
fi

# Module 3 : PostgreSQL HA
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "3" ]]; then
    if [[ -f "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh" ]]; then
        if ! "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh" "${TSV_FILE}" --yes; then
            log_error "Le Module 3 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 3 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 4 : Redis HA
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "4" ]]; then
    if [[ -f "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh" ]]; then
        log_info "=============================================================="
        log_info "Module 4: Redis HA"
        log_info "=============================================================="
        if ! "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh" "${TSV_FILE}" --yes; then
            log_error "Le Module 4 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 4 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 5 : RabbitMQ HA
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "5" ]]; then
    if [[ -f "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh" ]]; then
        if ! "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh" "${TSV_FILE}" --yes; then
            log_error "Le Module 5 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 5 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 6 : MinIO
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "6" ]]; then
    if [[ -f "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh" ]]; then
        if ! "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh" "${TSV_FILE}" --yes; then
            log_error "Le Module 6 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 6 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 7 : MariaDB Galera HA
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "7" ]]; then
    if [[ -f "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh" ]]; then
        log_info "=============================================================="
        log_info "Module 7: MariaDB Galera HA"
        log_info "=============================================================="
        if ! "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh" "${TSV_FILE}" --yes; then
            log_error "Le Module 7 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 7 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 8 : ProxySQL Avancé & Optimisation Galera
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "8" ]]; then
    if [[ -f "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh" ]]; then
        if ! run_module "8" "ProxySQL Avancé & Optimisation Galera" \
            "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh ${TSV_FILE} --yes"; then
            log_error "Le Module 8 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 8 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 9 : K3s HA Core
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "9" ]]; then
    if [[ -f "${SCRIPT_DIR}/09_k3s_ha/09_k3s_apply_all.sh" ]]; then
        if ! run_module "9" "K3s HA Core" \
            "${SCRIPT_DIR}/09_k3s_ha/09_k3s_apply_all.sh ${TSV_FILE} --yes"; then
            log_error "Le Module 9 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 9 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 10 : KeyBuzz API & Front
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "10" ]]; then
    if [[ -f "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_apply_all.sh" ]]; then
        if ! run_module "10" "KeyBuzz API & Front" \
            "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_apply_all.sh ${TSV_FILE} --yes"; then
            log_error "Le Module 10 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 10 introuvable, module ignoré"
    fi
    echo ""
fi

# Module 11 : n8n (Workflow Automation)
if [[ -z "${MODULE_ONLY}" ]] || [[ "${MODULE_ONLY}" == "11" ]]; then
    if [[ -f "${SCRIPT_DIR}/11_n8n/11_n8n_apply_all.sh" ]]; then
        if ! run_module "11" "n8n (Workflow Automation)" \
            "${SCRIPT_DIR}/11_n8n/11_n8n_apply_all.sh ${TSV_FILE} --yes"; then
            log_error "Le Module 11 a échoué. Installation arrêtée."
            exit 1
        fi
    else
        log_warning "Script Module 11 introuvable, module ignoré"
    fi
    echo ""
fi

# Résumé final
echo "=============================================================="
log_success "Installation maître terminée"
echo "=============================================================="
echo ""
echo "Date de fin: $(date)"
echo "Logs disponibles dans: ${LOG_DIR}"
echo ""
echo "Modules installés:"
echo "  ✅ Module 2: Base OS & Sécurité"
echo "  ✅ Module 3: PostgreSQL HA"
echo "  ✅ Module 4: Redis HA"
echo "  ✅ Module 5: RabbitMQ HA"
echo "  ✅ Module 6: MinIO S3 HA"
echo "  ✅ Module 7: MariaDB Galera HA"
echo "  ✅ Module 8: ProxySQL Avancé & Optimisation Galera"
echo "  ✅ Module 9: K3s HA Core"
echo "  ✅ Module 10: KeyBuzz API & Front"
echo "  ✅ Module 11: n8n (Workflow Automation)"
echo "  ⏳ Modules 12-15: Applications (à implémenter)"
echo ""
echo "Prochaines étapes:"
echo "  1. Vérifier les logs dans ${LOG_DIR}"
echo "  2. Implémenter les modules suivants selon les besoins"
echo "  3. Configurer les applications KeyBuzz sur K3s"
echo ""

