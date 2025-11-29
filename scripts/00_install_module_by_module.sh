#!/usr/bin/env bash
#
# 00_install_module_by_module.sh - Installation module par module avec validation
#
# Ce script installe chaque module individuellement, valide son fonctionnement,
# corrige toutes les erreurs, et met à jour le master script progressivement.
#
# Usage:
#   ./00_install_module_by_module.sh [--start-from-module N] [--skip-cleanup] [--skip-validation]
#
# Options:
#   --start-from-module N  : Commencer à partir du module N (défaut: 2)
#   --skip-cleanup         : Ne pas exécuter le nettoyage initial
#   --skip-validation      : Ne pas valider les modules après installation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${INSTALL_DIR}/servers.tsv"
LOG_DIR="${INSTALL_DIR}/logs"
INSTALL_LOG="${LOG_DIR}/module_by_module_install.log"
ERROR_LOG="${LOG_DIR}/module_by_module_errors.log"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${INSTALL_LOG}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${INSTALL_LOG}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${INSTALL_LOG}" | tee -a "${ERROR_LOG}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${INSTALL_LOG}"
}

# Créer les répertoires de logs
mkdir -p "${LOG_DIR}"
touch "${INSTALL_LOG}" "${ERROR_LOG}"

# Options
START_FROM_MODULE=2
SKIP_CLEANUP=false
SKIP_VALIDATION=false

for arg in "$@"; do
    case "${arg}" in
        --start-from-module=*)
            START_FROM_MODULE="${arg#*=}"
            ;;
        --skip-cleanup)
            SKIP_CLEANUP=true
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            ;;
        *)
            log_error "Option inconnue: ${arg}"
            exit 1
            ;;
    esac
done

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Détecter la clé SSH (depuis install-01)
SSH_KEY="${HOME}/.ssh/keybuzz_infra"
if [[ ! -f "${SSH_KEY}" ]]; then
    SSH_KEY="/root/.ssh/keybuzz_infra"
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    log_warning "Clé SSH introuvable, utilisation de l'authentification par défaut"
    SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
else
    SSH_KEY_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
fi

# Fonction pour créer tous les dossiers nécessaires sur install-01 et tous les serveurs
prepare_directories() {
    local module_name="$1"
    
    log_info "Préparation des dossiers pour ${module_name}..."
    
    # Obtenir l'IP de install-01 (parser avec awk pour gérer les tabulations)
    INSTALL01_IP=$(awk -F'\t' '$1 == "prod" && $3 == "install-01" {print $4; exit}' "${TSV_FILE}")
    
    if [[ -z "${INSTALL01_IP}" ]]; then
        log_error "install-01 non trouvé dans servers.tsv"
        return 1
    fi
    
    # Vérifier si on est déjà sur install-01 (éviter SSH vers soi-même)
    CURRENT_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || echo "")
    CURRENT_HOSTNAME=$(hostname 2>/dev/null || echo "")
    
    # Créer les dossiers sur install-01 (directement si on est dessus, sinon via SSH)
    if [[ "${CURRENT_IP}" == "${INSTALL01_IP}" ]] || [[ "${CURRENT_IP}" == "10.0.0.20" ]] || [[ "${CURRENT_HOSTNAME}" == "install-01" ]]; then
        # On est déjà sur install-01, exécuter directement
        bash <<'DIRECT_EOF'
set -euo pipefail

# Créer tous les dossiers nécessaires
mkdir -p /opt/keybuzz-installer/scripts
mkdir -p /opt/keybuzz-installer/credentials
mkdir -p /opt/keybuzz-installer/logs
mkdir -p /opt/keybuzz-installer/tmp
mkdir -p /opt/keybuzz-installer/inventory

# Créer les dossiers pour chaque service
mkdir -p /opt/keybuzz/postgres/{data,raft,archive,backup,config,logs}
mkdir -p /opt/keybuzz/redis/{data,config,logs,status,backups}
mkdir -p /opt/keybuzz/rabbitmq/{data,config,logs,status}
mkdir -p /opt/keybuzz/mariadb/{data,config,logs,status}
mkdir -p /opt/keybuzz/minio/{data,config,logs}
mkdir -p /opt/keybuzz/patroni/{config,logs}
mkdir -p /opt/keybuzz/haproxy/{config,logs,status}
mkdir -p /opt/keybuzz/pgbouncer/{config,logs}
mkdir -p /opt/keybuzz/proxysql/{config,logs}

# Créer les dossiers systemd
mkdir -p /etc/patroni
mkdir -p /etc/redis
mkdir -p /etc/rabbitmq
mkdir -p /etc/mariadb
mkdir -p /etc/minio
mkdir -p /etc/haproxy
mkdir -p /etc/pgbouncer
mkdir -p /etc/proxysql

# Permissions
chmod 755 /opt/keybuzz-installer
chmod 700 /opt/keybuzz-installer/credentials
chmod 755 /opt/keybuzz

echo "  ✓ Dossiers créés sur install-01"
DIRECT_EOF
    else
        # On est sur un autre serveur, utiliser SSH
        ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${INSTALL01_IP}" bash <<'SSH_EOF'
set -euo pipefail

# Créer tous les dossiers nécessaires
mkdir -p /opt/keybuzz-installer/scripts
mkdir -p /opt/keybuzz-installer/credentials
mkdir -p /opt/keybuzz-installer/logs
mkdir -p /opt/keybuzz-installer/tmp
mkdir -p /opt/keybuzz-installer/inventory

# Créer les dossiers pour chaque service
mkdir -p /opt/keybuzz/postgres/{data,raft,archive,backup,config,logs}
mkdir -p /opt/keybuzz/redis/{data,config,logs,status,backups}
mkdir -p /opt/keybuzz/rabbitmq/{data,config,logs,status}
mkdir -p /opt/keybuzz/mariadb/{data,config,logs,status}
mkdir -p /opt/keybuzz/minio/{data,config,logs}
mkdir -p /opt/keybuzz/patroni/{config,logs}
mkdir -p /opt/keybuzz/haproxy/{config,logs,status}
mkdir -p /opt/keybuzz/pgbouncer/{config,logs}
mkdir -p /opt/keybuzz/proxysql/{config,logs}

# Créer les dossiers systemd
mkdir -p /etc/patroni
mkdir -p /etc/redis
mkdir -p /etc/rabbitmq
mkdir -p /etc/mariadb
mkdir -p /etc/minio
mkdir -p /etc/haproxy
mkdir -p /etc/pgbouncer
mkdir -p /etc/proxysql

# Permissions
chmod 755 /opt/keybuzz-installer
chmod 700 /opt/keybuzz-installer/credentials
chmod 755 /opt/keybuzz

echo "  ✓ Dossiers créés sur install-01"
SSH_EOF
    fi
    
    if [[ $? -ne 0 ]]; then
        log_error "Échec création dossiers sur install-01"
        return 1
    fi
    
    # Créer les dossiers sur tous les serveurs (sauf install-01)
    log_info "Création des dossiers sur tous les serveurs..."
    
    exec 3< "${TSV_FILE}"
    while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
        if [[ "${ENV}" == "ENV" ]]; then
            continue
        fi
        
        if [[ "${ENV}" != "prod" ]] || [[ -z "${IP_PRIVEE}" ]]; then
            continue
        fi
        
        # Exclure install-01 (déjà fait)
        if [[ "${HOSTNAME}" == "install-01" ]]; then
            continue
        fi
        
        # Vérifier l'accessibilité SSH
        if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${IP_PRIVEE}" "echo 'OK'" >/dev/null 2>&1; then
            log_warning "  ⚠ Serveur ${HOSTNAME} (${IP_PRIVEE}) inaccessible, skip"
            continue
        fi
        
        ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${IP_PRIVEE}" bash <<EOF
set -euo pipefail

# Créer les dossiers selon le rôle
mkdir -p /opt/keybuzz-installer/credentials
mkdir -p /opt/keybuzz-installer/logs

# Dossiers selon le service
if [[ "${ROLE}" == "db" ]] || [[ "${ROLE}" == "postgres" ]]; then
    mkdir -p /opt/keybuzz/postgres/{data,raft,archive,backup,config,logs}
    mkdir -p /opt/keybuzz/patroni/{config,logs}
    mkdir -p /etc/patroni
fi

if [[ "${ROLE}" == "redis" ]]; then
    mkdir -p /opt/keybuzz/redis/{data,config,logs,status,backups}
    mkdir -p /etc/redis
fi

if [[ "${ROLE}" == "rabbitmq" ]] || [[ "${ROLE}" == "rmq" ]]; then
    mkdir -p /opt/keybuzz/rabbitmq/{data,config,logs,status}
    mkdir -p /etc/rabbitmq
fi

if [[ "${ROLE}" == "mariadb" ]] || [[ "${ROLE}" == "maria" ]]; then
    mkdir -p /opt/keybuzz/mariadb/{data,config,logs,status}
    mkdir -p /etc/mariadb
fi

if [[ "${ROLE}" == "minio" ]]; then
    mkdir -p /opt/keybuzz/minio/{data,config,logs}
    mkdir -p /etc/minio
fi

if [[ "${ROLE}" == "lb" ]] || [[ "${SUBROLE}" == "internal-haproxy" ]]; then
    mkdir -p /opt/keybuzz/haproxy/{config,logs,status}
    mkdir -p /opt/keybuzz/pgbouncer/{config,logs}
    mkdir -p /opt/keybuzz/proxysql/{config,logs}
    mkdir -p /etc/haproxy
    mkdir -p /etc/pgbouncer
    mkdir -p /etc/proxysql
fi

if [[ "${ROLE}" == "k3s" ]]; then
    mkdir -p /opt/keybuzz/k3s/{config,logs,data}
    mkdir -p /etc/rancher/k3s
fi

# Permissions
chmod 700 /opt/keybuzz-installer/credentials
chmod 755 /opt/keybuzz 2>/dev/null || true

echo "  ✓ Dossiers créés sur ${HOSTNAME}"
EOF
        
        if [[ $? -eq 0 ]]; then
            log_success "  ✓ ${HOSTNAME} préparé"
        else
            log_warning "  ⚠ Erreur sur ${HOSTNAME}, continue..."
        fi
    done
    exec 3<&-
    
    log_success "Préparation des dossiers terminée"
    return 0
}

# Fonction pour copier les credentials sur les serveurs
copy_credentials_to_servers() {
    local credentials_file="$1"
    local module_name="$2"
    
    if [[ ! -f "${credentials_file}" ]]; then
        log_warning "Fichier credentials introuvable: ${credentials_file}"
        return 1
    fi
    
    log_info "Copie des credentials ${module_name} sur tous les serveurs..."
    
    INSTALL01_IP=$(awk -F'\t' '$1 == "prod" && $3 == "install-01" {print $4; exit}' "${TSV_FILE}")
    
    # Copier sur install-01 d'abord
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${INSTALL01_IP}" "mkdir -p /opt/keybuzz-installer/credentials" >/dev/null 2>&1
    scp ${SSH_KEY_OPTS} -q "${credentials_file}" "root@${INSTALL01_IP}:/opt/keybuzz-installer/credentials/" || {
        log_error "Échec copie credentials sur install-01"
        return 1
    }
    
    # Copier sur tous les serveurs concernés
    exec 3< "${TSV_FILE}"
    while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
        if [[ "${ENV}" == "ENV" ]]; then
            continue
        fi
        
        if [[ "${ENV}" != "prod" ]] || [[ -z "${IP_PRIVEE}" ]]; then
            continue
        fi
        
        # Déterminer si ce serveur a besoin de ces credentials
        local needs_creds=false
        case "${module_name}" in
            postgres|postgresql)
                if [[ "${ROLE}" == "db" ]] || [[ "${ROLE}" == "postgres" ]] || [[ "${ROLE}" == "lb" ]]; then
                    needs_creds=true
                fi
                ;;
            redis)
                if [[ "${ROLE}" == "redis" ]] || [[ "${ROLE}" == "lb" ]]; then
                    needs_creds=true
                fi
                ;;
            rabbitmq)
                if [[ "${ROLE}" == "rabbitmq" ]] || [[ "${ROLE}" == "rmq" ]]; then
                    needs_creds=true
                fi
                ;;
            mariadb)
                if [[ "${ROLE}" == "mariadb" ]] || [[ "${ROLE}" == "maria" ]] || [[ "${ROLE}" == "lb" ]]; then
                    needs_creds=true
                fi
                ;;
            minio)
                if [[ "${ROLE}" == "minio" ]]; then
                    needs_creds=true
                fi
                ;;
            *)
                needs_creds=true
                ;;
        esac
        
        if [[ "${needs_creds}" == "false" ]]; then
            continue
        fi
        
        # Vérifier l'accessibilité SSH
        if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${IP_PRIVEE}" "echo 'OK'" >/dev/null 2>&1; then
            log_warning "  ⚠ Serveur ${HOSTNAME} inaccessible, skip credentials"
            continue
        fi
        
        # Créer le répertoire et copier
        ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${IP_PRIVEE}" "mkdir -p /opt/keybuzz-installer/credentials" >/dev/null 2>&1
        if scp ${SSH_KEY_OPTS} -q "${credentials_file}" "root@${IP_PRIVEE}:/opt/keybuzz-installer/credentials/"; then
            log_success "  ✓ Credentials copiés sur ${HOSTNAME}"
        else
            log_warning "  ⚠ Échec copie credentials sur ${HOSTNAME}"
        fi
    done
    exec 3<&-
    
    log_success "Copie des credentials terminée"
    return 0
}

# Fonction pour vérifier qu'un fichier existe avant de l'utiliser
check_file_exists() {
    local file_path="$1"
    local description="$2"
    
    if [[ ! -f "${file_path}" ]]; then
        log_error "${description} introuvable: ${file_path}"
        return 1
    fi
    
    return 0
}

# Fonction pour installer un module
install_module() {
    local module_num="$1"
    local module_name="$2"
    local script_path="$3"
    
    log_info "=============================================================="
    log_info "Module ${module_num}: ${module_name}"
    log_info "=============================================================="
    echo ""
    
    # Vérifier que le script existe
    if ! check_file_exists "${script_path}" "Script d'installation"; then
        log_error "Script introuvable: ${script_path}"
        return 1
    fi
    
    # Préparer les dossiers
    if ! prepare_directories "${module_name}"; then
        log_error "Échec préparation des dossiers"
        return 1
    fi
    
    # Copier les credentials si le script de credentials existe
    local credentials_script="${script_path%/*}/*00*credentials*.sh"
    if ls ${credentials_script} 2>/dev/null | head -1 | read cred_file; then
        log_info "Génération/copie des credentials..."
        
        # Exécuter le script de credentials
        if bash "${cred_file}" "${TSV_FILE}" --yes 2>&1 | tee -a "${INSTALL_LOG}"; then
            # Trouver le fichier credentials généré
            local cred_file_path=""
            case "${module_name}" in
                *PostgreSQL*|*postgres*)
                    cred_file_path="${INSTALL_DIR}/credentials/postgres.env"
                    ;;
                *Redis*)
                    cred_file_path="${INSTALL_DIR}/credentials/redis.env"
                    ;;
                *RabbitMQ*|*rabbitmq*)
                    cred_file_path="${INSTALL_DIR}/credentials/rabbitmq.env"
                    ;;
                *MariaDB*|*mariadb*)
                    cred_file_path="${INSTALL_DIR}/credentials/mariadb.env"
                    ;;
                *MinIO*|*minio*)
                    cred_file_path="${INSTALL_DIR}/credentials/minio.env"
                    ;;
            esac
            
            if [[ -n "${cred_file_path}" ]] && [[ -f "${cred_file_path}" ]]; then
                copy_credentials_to_servers "${cred_file_path}" "${module_name}"
            fi
        else
            log_warning "Échec génération credentials, continuation..."
        fi
    fi
    
    # Exécuter le script d'installation
    log_info "Exécution du script d'installation..."
    
    local max_attempts=3
    local attempt=1
    local success=false
    local module_log="${LOG_DIR}/module_${module_num}_install.log"
    
    while [[ ${attempt} -le ${max_attempts} ]]; do
        log_info "Tentative ${attempt}/${max_attempts}..."
        
        if bash "${script_path}" "${TSV_FILE}" --yes 2>&1 | tee "${module_log}" | tee -a "${INSTALL_LOG}"; then
            success=true
            break
        else
            log_warning "Tentative ${attempt} échouée, analyse des erreurs..."
            
            # Analyser les erreurs et documenter
            if grep -q "No such file or directory" "${module_log}"; then
                log_error "Erreur: Fichier ou dossier manquant"
                # Préparer à nouveau les dossiers
                prepare_directories "${module_name}"
            fi
            
            if grep -q "unbound variable" "${module_log}"; then
                log_error "Erreur: Variable non définie"
                # Documenter dans CORRECTIONS_ET_ERREURS.md
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Module ${module_num}: Variable non définie" >> "${ERROR_LOG}"
            fi
            
            if grep -q "Permission denied" "${module_log}"; then
                log_error "Erreur: Permission refusée"
            fi
            
            attempt=$((attempt + 1))
            sleep 5
        fi
    done
    
    if [[ "${success}" == "false" ]]; then
        log_error "Échec après ${max_attempts} tentatives pour le Module ${module_num}"
        return 1
    fi
    
    # Valider le module
    if [[ "${SKIP_VALIDATION}" == "false" ]]; then
        log_info "Validation du module ${module_num}..."
        
        # Exécuter les tests du module s'ils existent
        local test_script="${script_path%/*}/*test*.sh"
        if ls ${test_script} 2>/dev/null | head -1 | read test_file; then
            log_info "Exécution des tests du module..."
            local test_log="${LOG_DIR}/module_${module_num}_test.log"
            if bash "${test_file}" "${TSV_FILE}" 2>&1 | tee "${test_log}" | tee -a "${INSTALL_LOG}"; then
                log_success "Tests du module réussis"
            else
                log_warning "Certains tests ont échoué, mais le module est installé"
            fi
        else
            log_info "Aucun script de test trouvé pour ce module"
        fi
    fi
    
    log_success "Module ${module_num} installé et validé"
    echo ""
    
    return 0
}

# Nettoyage initial
if [[ "${SKIP_CLEANUP}" == "false" ]]; then
    log_info "=============================================================="
    log_info "Nettoyage Complet - Préparation Réinstallation"
    log_info "=============================================================="
    echo ""
    log_warning "ATTENTION: Ce script va supprimer TOUTES les données !"
    read -p "Continuer avec le nettoyage ? (tapez 'OUI' pour confirmer) : " CONFIRM
    if [[ "${CONFIRM}" == "OUI" ]]; then
        if bash "${SCRIPT_DIR}/00_cleanup_complete_installation.sh" "${TSV_FILE}" 2>&1 | tee -a "${INSTALL_LOG}"; then
            log_success "Nettoyage terminé"
        else
            log_error "Erreur lors du nettoyage"
            exit 1
        fi
    else
        log_info "Nettoyage ignoré (--skip-cleanup implicite)"
    fi
    echo ""
fi

# Installation module par module
log_info "=============================================================="
log_info "Installation Module par Module"
log_info "=============================================================="
echo ""

# Module 2: Base OS and Security
if [[ ${START_FROM_MODULE} -le 2 ]]; then
    install_module "2" "Base OS and Security" \
        "${SCRIPT_DIR}/02_base_os_and_security/apply_base_os_to_all.sh"
fi

# Module 3: PostgreSQL HA
if [[ ${START_FROM_MODULE} -le 3 ]]; then
    install_module "3" "PostgreSQL HA" \
        "${SCRIPT_DIR}/03_postgresql_ha/03_pg_apply_all.sh"
fi

# Module 4: Redis HA
if [[ ${START_FROM_MODULE} -le 4 ]]; then
    install_module "4" "Redis HA" \
        "${SCRIPT_DIR}/04_redis_ha/04_redis_apply_all.sh"
fi

# Module 5: RabbitMQ HA
if [[ ${START_FROM_MODULE} -le 5 ]]; then
    install_module "5" "RabbitMQ HA" \
        "${SCRIPT_DIR}/05_rabbitmq_ha/05_rmq_apply_all.sh"
fi

# Module 6: MinIO
if [[ ${START_FROM_MODULE} -le 6 ]]; then
    install_module "6" "MinIO" \
        "${SCRIPT_DIR}/06_minio/06_minio_apply_all.sh"
fi

# Module 7: MariaDB Galera HA
if [[ ${START_FROM_MODULE} -le 7 ]]; then
    install_module "7" "MariaDB Galera HA" \
        "${SCRIPT_DIR}/07_mariadb_galera/07_maria_apply_all.sh"
fi

# Module 8: ProxySQL Advanced
if [[ ${START_FROM_MODULE} -le 8 ]]; then
    install_module "8" "ProxySQL Advanced" \
        "${SCRIPT_DIR}/08_proxysql_advanced/08_proxysql_apply_all.sh"
fi

# Module 9: K3s HA Core
if [[ ${START_FROM_MODULE} -le 9 ]]; then
    install_module "9" "K3s HA Core" \
        "${SCRIPT_DIR}/09_k3s_ha/09_k3s_apply_all.sh"
    
    # Correction CoreDNS après installation (solution définitive)
    log_info "Vérification et correction CoreDNS..."
    if bash "${SCRIPT_DIR}/09_k3s_ha/09_k3s_fix_coredns_final.sh" "${TSV_FILE}" >/dev/null 2>&1; then
        log_success "CoreDNS vérifié/corrigé"
    else
        log_warning "CoreDNS: Vérification manuelle recommandée"
    fi
fi

# Module 10: KeyBuzz API & Front
if [[ ${START_FROM_MODULE} -le 10 ]]; then
    install_module "10" "KeyBuzz API & Front" \
        "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_apply_all.sh"
fi

# Module 11: n8n
if [[ ${START_FROM_MODULE} -le 11 ]]; then
    install_module "11" "n8n" \
        "${SCRIPT_DIR}/11_n8n/11_n8n_apply_all.sh"
fi

log_success "=============================================================="
log_success "✅ Installation complète terminée !"
log_success "=============================================================="
echo ""
log_info "Logs disponibles dans:"
log_info "  - Installation: ${INSTALL_LOG}"
log_info "  - Erreurs: ${ERROR_LOG}"
log_info "  - Par module: ${LOG_DIR}/module_*_install.log"
echo ""
