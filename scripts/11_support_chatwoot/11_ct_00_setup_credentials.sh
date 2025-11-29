#!/usr/bin/env bash
#
# 11_ct_00_setup_credentials.sh - Setup credentials et création DB Chatwoot
#
# Ce script :
# - Charge les credentials depuis /opt/keybuzz-installer-v2/credentials/
# - Crée la DB chatwoot et l'utilisateur dans PostgreSQL
# - Vérifie la connexion Redis
# - Prépare le bucket S3 si nécessaire
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDENTIALS_DIR="/opt/keybuzz-installer-v2/credentials"

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

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Setup Credentials Chatwoot"
echo "=============================================================="
echo ""

# 1. Charger les credentials
log_info "Chargement des credentials..."

if [ ! -f "${CREDENTIALS_DIR}/postgres.env" ]; then
    log_error "Fichier postgres.env non trouvé dans ${CREDENTIALS_DIR}"
    exit 1
fi

if [ ! -f "${CREDENTIALS_DIR}/redis.env" ]; then
    log_error "Fichier redis.env non trouvé dans ${CREDENTIALS_DIR}"
    exit 1
fi

source "${CREDENTIALS_DIR}/postgres.env"
source "${CREDENTIALS_DIR}/redis.env"

# Variables PostgreSQL
POSTGRES_HOST="${POSTGRES_HOST:-10.0.0.10}"
# Utiliser le port direct (5432) pour les opérations admin
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
# Utiliser POSTGRES_SUPERUSER si disponible, sinon postgres
POSTGRES_ADMIN_USER="${POSTGRES_SUPERUSER:-${POSTGRES_ADMIN_USER:-postgres}}"
# Utiliser POSTGRES_SUPERPASS si disponible
POSTGRES_ADMIN_PASSWORD="${POSTGRES_SUPERPASS:-${POSTGRES_ADMIN_PASSWORD:-${POSTGRES_PASSWORD:-${PGPASSWORD:-}}}}"

# Vérifier que le mot de passe est défini
if [ -z "${POSTGRES_ADMIN_PASSWORD}" ]; then
    log_error "Mot de passe PostgreSQL non défini dans postgres.env"
    log_info "Variables cherchées: POSTGRES_SUPERPASS, POSTGRES_ADMIN_PASSWORD, POSTGRES_PASSWORD"
    exit 1
fi

# Variables Chatwoot DB
CHATWOOT_DB="chatwoot"
CHATWOOT_USER="chatwoot"
CHATWOOT_PASSWORD="${CHATWOOT_PASSWORD:-$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)}"

log_success "Credentials chargés"

# 2. Créer la DB et l'utilisateur Chatwoot
log_info "Création de la base de données Chatwoot..."

export PGPASSWORD="${POSTGRES_ADMIN_PASSWORD}"

# Vérifier la connexion
log_info "Test de connexion à PostgreSQL..."
if ! timeout 10 psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
    log_error "Impossible de se connecter à PostgreSQL sur ${POSTGRES_HOST}:${POSTGRES_PORT}"
    log_info "Vérification des credentials..."
    log_info "POSTGRES_HOST: ${POSTGRES_HOST}"
    log_info "POSTGRES_PORT: ${POSTGRES_PORT}"
    log_info "POSTGRES_ADMIN_USER: ${POSTGRES_ADMIN_USER}"
    exit 1
fi

log_success "Connexion PostgreSQL OK"

# Créer l'utilisateur (si n'existe pas)
log_info "Création de l'utilisateur ${CHATWOOT_USER}..."
timeout 30 psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres <<EOF
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = '${CHATWOOT_USER}') THEN
        CREATE USER ${CHATWOOT_USER} WITH PASSWORD '${CHATWOOT_PASSWORD}';
    ELSE
        ALTER USER ${CHATWOOT_USER} WITH PASSWORD '${CHATWOOT_PASSWORD}';
    END IF;
END
\$\$;
EOF

log_success "Utilisateur ${CHATWOOT_USER} créé/mis à jour"

# Créer la base de données (si n'existe pas)
log_info "Création de la base de données ${CHATWOOT_DB}..."
timeout 30 psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres <<EOF
SELECT 'CREATE DATABASE ${CHATWOOT_DB} OWNER ${CHATWOOT_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${CHATWOOT_DB}')\gexec
EOF

# Donner les permissions
timeout 30 psql -h "${POSTGRES_HOST}" -p "${POSTGRES_PORT}" -U "${POSTGRES_ADMIN_USER}" -d postgres <<EOF
GRANT ALL PRIVILEGES ON DATABASE ${CHATWOOT_DB} TO ${CHATWOOT_USER};
EOF

log_success "Base de données ${CHATWOOT_DB} créée"

# 3. Vérifier Redis
log_info "Vérification de la connexion Redis..."
REDIS_HOST="${REDIS_HOST:-10.0.0.10}"
REDIS_PORT="${REDIS_PORT:-6379}"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

if [ -n "${REDIS_PASSWORD}" ]; then
    REDIS_URL="redis://:${REDIS_PASSWORD}@${REDIS_HOST}:${REDIS_PORT}/0"
else
    REDIS_URL="redis://${REDIS_HOST}:${REDIS_PORT}/0"
fi

if command -v redis-cli > /dev/null 2>&1; then
    if [ -n "${REDIS_PASSWORD}" ]; then
        if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" -a "${REDIS_PASSWORD}" ping > /dev/null 2>&1; then
            log_success "Connexion Redis OK"
        else
            log_warning "Impossible de se connecter à Redis (peut être normal si Redis n'est pas encore configuré)"
        fi
    else
        if redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" ping > /dev/null 2>&1; then
            log_success "Connexion Redis OK"
        else
            log_warning "Impossible de se connecter à Redis (peut être normal si Redis n'est pas encore configuré)"
        fi
    fi
else
    log_warning "redis-cli non disponible, test de connexion ignoré"
fi

# 4. Préparer S3/MinIO (optionnel)
log_info "Vérification de la configuration S3/MinIO..."

if [ -f "${CREDENTIALS_DIR}/minio.env" ]; then
    source "${CREDENTIALS_DIR}/minio.env"
    MINIO_ENDPOINT="${MINIO_ENDPOINT:-http://10.0.0.134:9000}"
    MINIO_ACCESS_KEY="${MINIO_ACCESS_KEY:-}"
    MINIO_SECRET_KEY="${MINIO_SECRET_KEY:-}"
    MINIO_BUCKET="keybuzz-chatwoot"
    
    if [ -n "${MINIO_ACCESS_KEY}" ] && [ -n "${MINIO_SECRET_KEY}" ]; then
        log_info "Configuration S3/MinIO trouvée"
        log_info "Bucket à créer : ${MINIO_BUCKET}"
        log_warning "Création du bucket S3 à faire manuellement via 'mc' ou via l'API MinIO"
    fi
else
    log_warning "Fichier minio.env non trouvé, S3 désactivé pour l'instant"
fi

# 5. Sauvegarder les credentials Chatwoot
log_info "Sauvegarde des credentials Chatwoot..."

mkdir -p "${CREDENTIALS_DIR}"
cat > "${CREDENTIALS_DIR}/chatwoot.env" <<EOF
# Chatwoot Database Credentials
CHATWOOT_DB=${CHATWOOT_DB}
CHATWOOT_USER=${CHATWOOT_USER}
CHATWOOT_PASSWORD=${CHATWOOT_PASSWORD}

# PostgreSQL Connection
POSTGRES_HOST=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}

# Redis Connection
REDIS_URL=${REDIS_URL}
REDIS_HOST=${REDIS_HOST}
REDIS_PORT=${REDIS_PORT}
REDIS_PASSWORD=${REDIS_PASSWORD}

# S3/MinIO (si configuré)
MINIO_ENDPOINT=${MINIO_ENDPOINT:-}
MINIO_ACCESS_KEY=${MINIO_ACCESS_KEY:-}
MINIO_SECRET_KEY=${MINIO_SECRET_KEY:-}
MINIO_BUCKET=${MINIO_BUCKET:-}
EOF

chmod 600 "${CREDENTIALS_DIR}/chatwoot.env"
log_success "Credentials sauvegardés dans ${CREDENTIALS_DIR}/chatwoot.env"

echo ""
log_success "✅ Setup credentials terminé"
echo ""
log_info "Résumé :"
echo "  - Base de données : ${CHATWOOT_DB}"
echo "  - Utilisateur : ${CHATWOOT_USER}"
echo "  - Redis URL : ${REDIS_URL}"
echo ""

