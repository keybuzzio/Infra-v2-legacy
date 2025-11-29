#!/usr/bin/env bash
#
# 00_load_versions.sh - Helper script pour charger les versions Docker depuis versions.yaml
#
# Usage:
#   source 00_load_versions.sh
#   ou
#   . 00_load_versions.sh
#
# Ce script charge toutes les versions d'images Docker dans des variables d'environnement
# pour être utilisées dans les scripts d'installation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${INSTALL_DIR}/versions.yaml"

if [[ ! -f "${VERSIONS_FILE}" ]]; then
    echo "⚠️  Fichier versions.yaml introuvable: ${VERSIONS_FILE}" >&2
    echo "⚠️  Utilisation des versions par défaut" >&2
    export POSTGRES_IMAGE="postgres:16.4-alpine"
    export PATRONI_IMAGE="zalando/patroni:3.3.0"
    export REDIS_IMAGE="redis:7.2.5-alpine"
    export RABBITMQ_IMAGE="rabbitmq:3.13.2-management"
    export MINIO_IMAGE="minio/minio:RELEASE.2024-10-02T10-00Z"
    export HAPROXY_IMAGE="haproxy:2.8.5"
    export MARIADB_GALERA_IMAGE="bitnami/mariadb-galera:10.11.6"
    export PROXYSQL_IMAGE="proxysql/proxysql:2.6.4"
    export K3S_VERSION="v1.33.5+k3s1"
    return 0
fi

# Parser versions.yaml et exporter les variables
while IFS= read -r line; do
    # Ignorer les commentaires et lignes vides
    [[ -z "${line}" ]] && continue
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    
    # Extraire clé et valeur
    if [[ "${line}" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value="${BASH_REMATCH[2]}"
        
        # Nettoyer la valeur (supprimer guillemets)
        value=$(echo "${value}" | sed 's/^"\(.*\)"$/\1/' | sed "s/^'\(.*\)'$/\1/")
        
        # Convertir en nom de variable (minuscules -> majuscules, tirets -> underscores)
        var_name=$(echo "${key}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        
        # Exporter la variable
        export "${var_name}"="${value}"
    fi
done < "${VERSIONS_FILE}"

# Exporter aussi les noms avec préfixe IMAGE_ pour compatibilité
export POSTGRES_IMAGE="${POSTGRES_IMAGE:-postgres:16.4-alpine}"
export PATRONI_IMAGE="${PATRONI_IMAGE:-zalando/patroni:3.3.0}"
export REDIS_IMAGE="${REDIS_IMAGE:-redis:7.2.5-alpine}"
export RABBITMQ_IMAGE="${RABBITMQ_IMAGE:-rabbitmq:3.13.2-management}"
export MINIO_IMAGE="${MINIO_IMAGE:-minio/minio:RELEASE.2024-10-02T10-00Z}"
export HAPROXY_IMAGE="${HAPROXY_IMAGE:-haproxy:2.8.5}"
export MARIADB_GALERA_IMAGE="${MARIADB_GALERA_IMAGE:-bitnami/mariadb-galera:10.11.6}"
export PROXYSQL_IMAGE="${PROXYSQL_IMAGE:-proxysql/proxysql:2.6.4}"
export K3S_VERSION="${K3S_VERSION:-v1.33.5+k3s1}"

