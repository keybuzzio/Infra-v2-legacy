#!/usr/bin/env bash
#
# 03_pg_00_setup_credentials.sh - Configuration des credentials PostgreSQL
#
# Ce script crée le fichier postgres.env avec les credentials nécessaires
# pour le cluster PostgreSQL HA.
#
# Usage:
#   ./03_pg_00_setup_credentials.sh [--interactive]
#
# Options:
#   --interactive : Mode interactif pour saisir les mots de passe
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Répertoire credentials/ doit exister

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/postgres.env"

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

# Fonction pour générer un mot de passe fort
generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

# Fonction pour valider un mot de passe
validate_password() {
    local password=$1
    if [[ ${#password} -lt 16 ]]; then
        return 1
    fi
    return 0
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Configuration Credentials PostgreSQL"
echo "=============================================================="
echo ""

# Créer le répertoire credentials si nécessaire
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

# Mode interactif ou automatique
INTERACTIVE=false
NON_INTERACTIVE=false
for arg in "$@"; do
    if [[ "${arg}" == "--interactive" ]]; then
        INTERACTIVE=true
    elif [[ "${arg}" == "--yes" ]] || [[ "${arg}" == "-y" ]]; then
        NON_INTERACTIVE=true
    fi
done

# Vérifier si le fichier existe déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    if [[ "${NON_INTERACTIVE}" == "true" ]]; then
        log_info "Le fichier ${CREDENTIALS_FILE} existe déjà."
        log_info "Utilisation du fichier existant (mode non-interactif)."
        source "${CREDENTIALS_FILE}"
        log_success "Credentials chargés depuis ${CREDENTIALS_FILE}"
        exit 0
    else
        log_warning "Le fichier ${CREDENTIALS_FILE} existe déjà."
        read -p "Voulez-vous le regénérer ? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Utilisation du fichier existant."
            source "${CREDENTIALS_FILE}"
            log_success "Credentials chargés depuis ${CREDENTIALS_FILE}"
            exit 0
        fi
        log_warning "Regénération des credentials..."
    fi
fi

# Générer ou demander les credentials
if [[ "${INTERACTIVE}" == "true" ]]; then
    log_info "Mode interactif : saisie des mots de passe"
    echo ""
    
    # Superuser
    read -sp "Mot de passe pour superuser (kb_admin) [min 16 caractères] : " POSTGRES_SUPERPASS
    echo
    while ! validate_password "${POSTGRES_SUPERPASS}"; do
        log_error "Le mot de passe doit contenir au moins 16 caractères"
        read -sp "Mot de passe pour superuser (kb_admin) : " POSTGRES_SUPERPASS
        echo
    done
    
    # Replication user
    read -sp "Mot de passe pour replication user (kb_repl) [min 16 caractères] : " POSTGRES_REPL_PASS
    echo
    while ! validate_password "${POSTGRES_REPL_PASS}"; do
        log_error "Le mot de passe doit contenir au moins 16 caractères"
        read -sp "Mot de passe pour replication user (kb_repl) : " POSTGRES_REPL_PASS
        echo
    done
    
    # App user
    read -sp "Mot de passe pour app user (kb_app) [min 16 caractères] : " POSTGRES_APP_PASS
    echo
    while ! validate_password "${POSTGRES_APP_PASS}"; do
        log_error "Le mot de passe doit contenir au moins 16 caractères"
        read -sp "Mot de passe pour app user (kb_app) : " POSTGRES_APP_PASS
        echo
    done
else
    log_info "Génération automatique des mots de passe..."
    POSTGRES_SUPERPASS=$(generate_password)
    POSTGRES_REPL_PASS=$(generate_password)
    POSTGRES_APP_PASS=$(generate_password)
    log_success "Mots de passe générés"
fi

# Valeurs par défaut
POSTGRES_SUPERUSER="${POSTGRES_SUPERUSER:-kb_admin}"
POSTGRES_REPL_USER="${POSTGRES_REPL_USER:-kb_repl}"
POSTGRES_APP_USER="${POSTGRES_APP_USER:-kb_app}"
POSTGRES_DB="${POSTGRES_DB:-keybuzz}"
PATRONI_CLUSTER_NAME="${PATRONI_CLUSTER_NAME:-keybuzz-pg}"

# Générer PATRONI_API_PASSWORD si nécessaire
if [[ -z "${PATRONI_API_PASSWORD:-}" ]]; then
    PATRONI_API_PASSWORD=$(generate_password)
fi

# Créer le fichier postgres.env
log_info "Création du fichier ${CREDENTIALS_FILE}..."

cat > "${CREDENTIALS_FILE}" <<EOF
# PostgreSQL Credentials for KeyBuzz
# Generated on $(date)
# DO NOT COMMIT THIS FILE TO GIT

POSTGRES_SUPERUSER=${POSTGRES_SUPERUSER}
POSTGRES_SUPERPASS=${POSTGRES_SUPERPASS}
POSTGRES_REPL_USER=${POSTGRES_REPL_USER}
POSTGRES_REPL_PASS=${POSTGRES_REPL_PASS}
POSTGRES_APP_USER=${POSTGRES_APP_USER}
POSTGRES_APP_PASS=${POSTGRES_APP_PASS}
POSTGRES_DB=${POSTGRES_DB}
PATRONI_CLUSTER_NAME=${PATRONI_CLUSTER_NAME}
PATRONI_API_PASSWORD=${PATRONI_API_PASSWORD}
EOF

chmod 600 "${CREDENTIALS_FILE}"
log_success "Fichier créé : ${CREDENTIALS_FILE}"

# Afficher un résumé (sans les mots de passe)
echo ""
echo "=============================================================="
log_success "Credentials configurés avec succès !"
echo "=============================================================="
echo ""
echo "Superuser      : ${POSTGRES_SUPERUSER}"
echo "Replication    : ${POSTGRES_REPL_USER}"
echo "Application    : ${POSTGRES_APP_USER}"
echo "Database       : ${POSTGRES_DB}"
echo "Cluster Name   : ${PATRONI_CLUSTER_NAME}"
echo ""
if [[ "${INTERACTIVE}" == "false" ]]; then
    log_warning "Les mots de passe ont été générés automatiquement."
    log_warning "Ils sont stockés dans : ${CREDENTIALS_FILE}"
    log_warning "Assurez-vous de sauvegarder ce fichier de manière sécurisée !"
fi
echo ""

