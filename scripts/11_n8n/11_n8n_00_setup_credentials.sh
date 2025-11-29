#!/usr/bin/env bash
#
# 11_n8n_00_setup_credentials.sh - Configuration des credentials n8n
#
# Ce script génère ou charge les credentials n8n et crée la base de données
# PostgreSQL nécessaire pour n8n.
#
# Usage:
#   ./11_n8n_00_setup_credentials.sh [servers.tsv]
#
# Prérequis:
#   - Module 3 installé (PostgreSQL HA)
#   - Module 4 installé (Redis HA)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Gérer les arguments
TSV_FILE="${INSTALL_DIR}/servers.tsv"
for arg in "$@"; do
    if [[ -f "${arg}" ]]; then
        TSV_FILE="${arg}"
    fi
done

# Si TSV_FILE n'est pas un fichier, essayer le chemin par défaut
if [[ ! -f "${TSV_FILE}" ]]; then
    TSV_FILE="${INSTALL_DIR}/servers.tsv"
fi

# Trouver le répertoire credentials
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
if [[ ! -d "${CREDENTIALS_DIR}" ]]; then
    # Essayer d'autres emplacements possibles
    for path in /root/credentials /root/install-01/credentials; do
        if [[ -d "${path}" ]]; then
            CREDENTIALS_DIR="${path}"
            break
        fi
    done
fi

# Créer le répertoire si nécessaire
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

CREDENTIALS_FILE="${CREDENTIALS_DIR}/n8n.env"

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

# Fonction pour générer une clé d'encryption
generate_encryption_key() {
    openssl rand -hex 32
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 11 - Configuration Credentials n8n"
echo "=============================================================="
echo ""

# Créer le répertoire credentials si nécessaire
mkdir -p "${CREDENTIALS_DIR}"
chmod 700 "${CREDENTIALS_DIR}"

# Vérifier si le fichier existe déjà
if [[ -f "${CREDENTIALS_FILE}" ]]; then
    log_info "Fichier credentials existant trouvé: ${CREDENTIALS_FILE}"
    source "${CREDENTIALS_FILE}"
    
    if [[ -n "${N8N_DB_PASSWORD:-}" ]] && [[ -n "${N8N_ENCRYPTION_KEY:-}" ]]; then
        log_success "Credentials n8n déjà configurés"
        log_info "Database User: n8n"
        log_info "Database: n8n"
        log_info "Encryption Key: ${N8N_ENCRYPTION_KEY:0:8}..."
        echo ""
        read -p "Voulez-vous régénérer les credentials ? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Utilisation des credentials existants"
            exit 0
        fi
    else
        log_warning "Fichier credentials incomplet, régénération..."
    fi
fi

# Charger les credentials des services backend
log_info "Chargement des credentials des services backend..."

# PostgreSQL
POSTGRES_CREDENTIALS="${CREDENTIALS_DIR}/postgres.env"
if [[ ! -f "${POSTGRES_CREDENTIALS}" ]]; then
    log_error "Fichier credentials PostgreSQL introuvable: ${POSTGRES_CREDENTIALS}"
    log_error "Exécutez d'abord le Module 3 (PostgreSQL HA)"
    exit 1
fi
source "${POSTGRES_CREDENTIALS}"

# Redis
REDIS_CREDENTIALS="${CREDENTIALS_DIR}/redis.env"
if [[ ! -f "${REDIS_CREDENTIALS}" ]]; then
    log_error "Fichier credentials Redis introuvable: ${REDIS_CREDENTIALS}"
    log_error "Exécutez d'abord le Module 4 (Redis HA)"
    exit 1
fi
source "${REDIS_CREDENTIALS}"

# Générer les credentials n8n
log_info "Génération des credentials n8n..."

N8N_DB_USER="n8n"
N8N_DB_PASSWORD=$(generate_password)
N8N_DB_NAME="n8n"
N8N_ENCRYPTION_KEY=$(generate_encryption_key)

# Trouver le premier serveur PostgreSQL pour créer la base
declare -a PG_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    # Chercher les serveurs PostgreSQL (ROLE=db, SUBROLE=postgres)
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PG_MASTER_IPS+=("${IP_PRIVEE}")
    fi
    # Aussi chercher ROLE=postgres pour compatibilité
    if [[ "${ROLE}" == "postgres" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PG_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#PG_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun serveur PostgreSQL trouvé dans servers.tsv"
    log_error "Vérifiez que les serveurs PostgreSQL sont listés avec ROLE=db SUBROLE=postgres"
    exit 1
fi

PG_MASTER_IP="${PG_MASTER_IPS[0]}"
log_info "Utilisation du serveur PostgreSQL: ${PG_MASTER_IP} (${HOSTNAME:-N/A})"

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Créer l'utilisateur et la base de données
log_info "Création de l'utilisateur et de la base de données n8n..."

ssh ${SSH_KEY_OPTS} "root@${PG_MASTER_IP}" bash <<EOF
set -e

# Se connecter au cluster PostgreSQL via Patroni
export PGPASSWORD="${POSTGRES_SUPERUSER_PASSWORD}"

# Vérifier si l'utilisateur existe déjà
USER_EXISTS=\$(psql -h localhost -U postgres -d postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='${N8N_DB_USER}'" 2>/dev/null || echo "0")

if [[ "\${USER_EXISTS}" == "1" ]]; then
    echo "Utilisateur ${N8N_DB_USER} existe déjà"
    # Changer le mot de passe
    psql -h localhost -U postgres -d postgres -c "ALTER USER ${N8N_DB_USER} WITH PASSWORD '${N8N_DB_PASSWORD}';" 2>/dev/null || true
else
    # Créer l'utilisateur
    psql -h localhost -U postgres -d postgres -c "CREATE USER ${N8N_DB_USER} WITH PASSWORD '${N8N_DB_PASSWORD}';" 2>/dev/null || true
fi

# Vérifier si la base existe déjà
DB_EXISTS=\$(psql -h localhost -U postgres -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${N8N_DB_NAME}'" 2>/dev/null || echo "0")

if [[ "\${DB_EXISTS}" == "1" ]]; then
    echo "Base de données ${N8N_DB_NAME} existe déjà"
else
    # Créer la base de données
    psql -h localhost -U postgres -d postgres -c "CREATE DATABASE ${N8N_DB_NAME} OWNER ${N8N_DB_USER};" 2>/dev/null || true
fi

# Donner les permissions
psql -h localhost -U postgres -d ${N8N_DB_NAME} -c "GRANT ALL PRIVILEGES ON DATABASE ${N8N_DB_NAME} TO ${N8N_DB_USER};" 2>/dev/null || true
psql -h localhost -U postgres -d ${N8N_DB_NAME} -c "GRANT ALL ON SCHEMA public TO ${N8N_DB_USER};" 2>/dev/null || true

echo "✅ Utilisateur et base de données créés"
EOF

log_success "Base de données n8n créée"

# Sauvegarder les credentials
log_info "Sauvegarde des credentials..."

cat > "${CREDENTIALS_FILE}" <<EOF
# n8n Configuration - KeyBuzz Production
# Généré le: $(date)

# Database (PostgreSQL HA via PgBouncer)
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=${POSTGRES_LB_IP:-10.0.0.10}
DB_POSTGRESDB_PORT=4632
DB_POSTGRESDB_DATABASE=${N8N_DB_NAME}
DB_POSTGRESDB_USER=${N8N_DB_USER}
DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
DB_POSTGRESDB_SCHEMA=public

# Queue (Bull with Redis)
QUEUE_BULL_REDIS_HOST=${REDIS_LB_IP:-10.0.0.10}
QUEUE_BULL_REDIS_PORT=6379
QUEUE_BULL_REDIS_PASSWORD=${REDIS_PASSWORD}
QUEUE_BULL_REDIS_DB=0
EXECUTIONS_MODE=queue

# URLs
WEBHOOK_URL=https://n8n.keybuzz.io/
N8N_PROTOCOL=https
N8N_HOST=n8n.keybuzz.io
N8N_PORT=5678

# Security
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}

# Timezone
GENERIC_TIMEZONE=Europe/Paris
TZ=Europe/Paris

# Logs
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
EOF

chmod 600 "${CREDENTIALS_FILE}"
log_success "Credentials sauvegardés: ${CREDENTIALS_FILE}"

echo ""
echo "=============================================================="
log_success "✅ Credentials n8n configurés"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Database: ${N8N_DB_NAME}@${POSTGRES_LB_IP:-10.0.0.10}:4632"
log_info "  - User: ${N8N_DB_USER}"
log_info "  - Redis: ${REDIS_LB_IP:-10.0.0.10}:6379"
log_info "  - Encryption Key: ${N8N_ENCRYPTION_KEY:0:16}..."
echo ""
log_info "Prochaine étape: ./11_n8n_01_deploy.sh"
echo ""

