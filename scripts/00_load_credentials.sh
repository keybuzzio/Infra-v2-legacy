#!/usr/bin/env bash
#
# 00_load_credentials.sh - Fonction standardisée pour charger les credentials
#
# Ce script fournit une fonction standardisée pour charger les credentials
# depuis différents emplacements possibles.
#

# Fonction pour charger les credentials PostgreSQL
load_postgres_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    local CREDENTIALS_FILE="${INSTALL_DIR}/credentials/postgres.env"
    
    if [[ -f "${CREDENTIALS_FILE}" ]]; then
        source "${CREDENTIALS_FILE}"
        return 0
    fi
    
    return 1
}

# Fonction pour charger les credentials Redis
load_redis_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    local CREDENTIALS_FILE="${INSTALL_DIR}/credentials/redis.env"
    
    if [[ -f "${CREDENTIALS_FILE}" ]]; then
        source "${CREDENTIALS_FILE}"
        # Exporter REDIS_PASSWORD si défini
        if [[ -n "${REDIS_PASSWORD:-}" ]]; then
            export REDIS_PASSWORD
        fi
        return 0
    fi
    
    return 1
}

# Fonction pour charger les credentials MariaDB
load_mariadb_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    local CREDENTIALS_FILE="${INSTALL_DIR}/credentials/mariadb.env"
    
    # Essayer d'abord le fichier standard
    if [[ -f "${CREDENTIALS_FILE}" ]]; then
        source "${CREDENTIALS_FILE}"
        return 0
    fi
    
    # Essayer /tmp/mariadb.env (pour compatibilité)
    if [[ -f "/tmp/mariadb.env" ]]; then
        source "/tmp/mariadb.env"
        return 0
    fi
    
    return 1
}

# Fonction pour charger les credentials RabbitMQ
load_rabbitmq_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    local CREDENTIALS_FILE="${INSTALL_DIR}/credentials/rabbitmq.env"
    
    if [[ -f "${CREDENTIALS_FILE}" ]]; then
        source "${CREDENTIALS_FILE}"
        return 0
    fi
    
    return 1
}

# Fonction pour charger les credentials MinIO
load_minio_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    local CREDENTIALS_FILE="${INSTALL_DIR}/credentials/minio.env"
    
    if [[ -f "${CREDENTIALS_FILE}" ]]; then
        source "${CREDENTIALS_FILE}"
        return 0
    fi
    
    return 1
}

# Fonction pour charger tous les credentials disponibles
load_all_credentials() {
    local INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    
    load_postgres_credentials "${INSTALL_DIR}" || true
    load_redis_credentials "${INSTALL_DIR}" || true
    load_mariadb_credentials "${INSTALL_DIR}" || true
    load_rabbitmq_credentials "${INSTALL_DIR}" || true
    load_minio_credentials "${INSTALL_DIR}" || true
}

# Si le script est exécuté directement, charger tous les credentials
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    INSTALL_DIR="${1:-/opt/keybuzz-installer}"
    load_all_credentials "${INSTALL_DIR}"
    
    echo "Credentials chargés depuis: ${INSTALL_DIR}/credentials/"
    echo ""
    echo "Variables disponibles:"
    echo "  PostgreSQL: POSTGRES_SUPERUSER, POSTGRES_SUPERPASS, POSTGRES_APP_USER, POSTGRES_APP_PASS"
    echo "  Redis: REDIS_PASSWORD"
    echo "  MariaDB: MARIADB_ROOT_PASSWORD, MARIADB_APP_USER, MARIADB_APP_PASSWORD"
    echo "  RabbitMQ: RABBITMQ_ERLANG_COOKIE, RABBITMQ_DEFAULT_USER, RABBITMQ_DEFAULT_PASS"
    echo "  MinIO: MINIO_ROOT_USER, MINIO_ROOT_PASSWORD"
fi

