#!/usr/bin/env bash
#
# 00_diagnostic_services.sh - Diagnostic de l'état des services
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

echo "=============================================================="
echo " Diagnostic des Services"
echo "=============================================================="
echo ""

# PostgreSQL
echo "=== PostgreSQL ==="
PG_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]]; then
        if [[ "${HOSTNAME}" == "db-master-01" ]] || [[ "${HOSTNAME}" == "db-slave-01" ]] || [[ "${HOSTNAME}" == "db-slave-02" ]]; then
            PG_IPS+=("${IP_PRIVEE}")
        fi
    fi
done
exec 3<&-

for ip in "${PG_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'patroni|postgres' || echo '    Aucun conteneur PostgreSQL'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

# Redis
echo "=== Redis ==="
REDIS_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "redis" ]] && [[ "${HOSTNAME}" =~ ^redis- ]]; then
        REDIS_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${REDIS_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'redis|sentinel' || echo '    Aucun conteneur Redis'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

# RabbitMQ
echo "=== RabbitMQ ==="
RABBITMQ_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "queue" ]] && [[ "${SUBROLE}" == "rabbitmq" ]] && [[ "${HOSTNAME}" =~ ^queue- ]]; then
        RABBITMQ_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${RABBITMQ_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'rabbitmq' || echo '    Aucun conteneur RabbitMQ'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

# MariaDB
echo "=== MariaDB ==="
MARIADB_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "mariadb" ]] && [[ "${HOSTNAME}" =~ ^maria- ]]; then
        MARIADB_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${MARIADB_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'mariadb' || echo '    Aucun conteneur MariaDB'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

# ProxySQL
echo "=== ProxySQL ==="
PROXYSQL_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db_proxy" ]] && ([[ "${HOSTNAME}" == "proxysql-01" ]] || [[ "${HOSTNAME}" == "proxysql-02" ]]); then
        PROXYSQL_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${PROXYSQL_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'proxysql' || echo '    Aucun conteneur ProxySQL'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

# MinIO
echo "=== MinIO ==="
MINIO_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "storage" ]] && [[ "${SUBROLE}" == "minio" ]] && [[ "${HOSTNAME}" =~ ^minio- ]]; then
        MINIO_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${MINIO_IPS[@]}"; do
    echo "  ${ip}:"
    ssh ${SSH_OPTS} root@${ip} "docker ps --format 'table {{.Names}}\t{{.Status}}' | grep -E 'minio' || echo '    Aucun conteneur MinIO'" 2>/dev/null || echo "    Erreur connexion"
done
echo ""

