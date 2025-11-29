#!/usr/bin/env bash
#
# 00_restart_all_servers_safe.sh - Redemarrage securise de tous les serveurs sauf install-01
#
# Ce script redemarre tous les serveurs par groupes pour eviter les coupures de service
# et respecter les dependances entre services.
#
# Usage:
#   ./00_restart_all_servers_safe.sh [servers.tsv] [--yes]
#
# Prerequis:
#   - Executer depuis install-01
#   - Acces SSH a tous les serveurs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Options SSH
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

# Fonction pour parser servers.tsv
get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

# Fonction pour tester l'acces SSH
test_ssh() {
    local ip="$1"
    local hostname="$2"
    if ssh ${SSH_OPTS} root@"${ip}" "echo OK" 2>/dev/null | grep -q "OK"; then
        return 0
    else
        return 1
    fi
}

# Fonction pour redemarrer un serveur
restart_server() {
    local hostname="$1"
    local ip="$2"
    
    log_info "Redemarrage de ${hostname} (${ip})..."
    
    if ssh ${SSH_OPTS} root@"${ip}" "reboot" 2>/dev/null; then
        log_success "Commande de redemarrage envoyee a ${hostname}"
        return 0
    else
        log_error "Impossible de redemarrer ${hostname}"
        return 1
    fi
}

# Fonction pour attendre qu'un serveur soit de nouveau accessible
wait_for_server() {
    local hostname="$1"
    local ip="$2"
    local max_wait=300  # 5 minutes max
    local elapsed=0
    
    log_info "Attente de la disponibilite de ${hostname} (${ip})..."
    
    while [ ${elapsed} -lt ${max_wait} ]; do
        if test_ssh "${ip}" "${hostname}"; then
            log_success "${hostname} est de nouveau accessible (${elapsed}s)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $((elapsed % 30)) -eq 0 ]; then
            log_info "  Attente... (${elapsed}s/${max_wait}s)"
        fi
    done
    
    log_error "${hostname} n'est pas accessible apres ${max_wait}s"
    return 1
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Redemarrage Securise - Tous les Serveurs"
echo "=============================================================="
echo ""
log_warning "Ce script va redemarrer TOUS les serveurs sauf install-01"
log_warning "Les serveurs seront redemarres par groupes pour eviter les coupures"
echo ""

# Confirmation
if [[ "${AUTO_YES}" != "--yes" ]]; then
    read -p "Continuer ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Operation annulee"
        exit 0
    fi
fi

# Phase 1: Test d'acces a tous les serveurs
log_info "Phase 1: Test d'acces SSH a tous les serveurs..."
echo ""

ACCESSIBLE=0
INACCESSIBLE=0
SERVERS_TO_RESTART=()

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    # Ignorer la ligne d'en-tete et install-01
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "install-01" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]] || [[ -z "${HOSTNAME}" ]]; then
        continue
    fi
    
    if test_ssh "${IP_PRIVEE}" "${HOSTNAME}"; then
        log_success "Acces SSH OK: ${HOSTNAME} (${IP_PRIVEE})"
        ACCESSIBLE=$((ACCESSIBLE + 1))
        SERVERS_TO_RESTART+=("${HOSTNAME}:${IP_PRIVEE}")
    else
        log_error "Acces SSH FAIL: ${HOSTNAME} (${IP_PRIVEE})"
        INACCESSIBLE=$((INACCESSIBLE + 1))
    fi
done < "${TSV_FILE}"

echo ""
log_info "Resume: ${ACCESSIBLE} serveurs accessibles, ${INACCESSIBLE} serveurs inaccessibles"
echo ""

if [[ ${ACCESSIBLE} -eq 0 ]]; then
    log_error "Aucun serveur accessible. Abandon."
    exit 1
fi

if [[ ${INACCESSIBLE} -gt 0 ]]; then
    log_warning "${INACCESSIBLE} serveur(s) inaccessibles seront ignores"
    echo ""
fi

# Phase 2: Redemarrage par groupes
log_info "Phase 2: Redemarrage par groupes (pour eviter les coupures)"
echo ""

# Groupe 1: Services non critiques (apps, monitoring, etc.)
log_info "Groupe 1: Services non critiques..."
NON_CRITICAL=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${HOSTNAME}" == "install-01" ]]; then
        continue
    fi
    if [[ "${CORE}" != "yes" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        NON_CRITICAL+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#NON_CRITICAL[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#NON_CRITICAL[@]} serveurs non critiques..."
    for server in "${NON_CRITICAL[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
    done
    log_info "Attente 30 secondes avant le groupe suivant..."
    sleep 30
    echo ""
fi

# Groupe 2: K3s Workers (avant les masters)
log_info "Groupe 2: K3s Workers..."
K3S_WORKERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "worker" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_WORKERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#K3S_WORKERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#K3S_WORKERS[@]} K3s workers..."
    for server in "${K3S_WORKERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10  # Petit delai entre chaque worker
    done
    log_info "Attente 60 secondes pour que les workers redemarrent..."
    sleep 60
    echo ""
fi

# Groupe 3: K3s Masters
log_info "Groupe 3: K3s Masters..."
K3S_MASTERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_MASTERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#K3S_MASTERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#K3S_MASTERS[@]} K3s masters..."
    for server in "${K3S_MASTERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 90 secondes pour que les masters redemarrent..."
    sleep 90
    echo ""
fi

# Groupe 4: Services de stockage (MinIO)
log_info "Groupe 4: MinIO (stockage)..."
MINIO_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "storage" ]] && [[ "${SUBROLE}" == "minio" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        MINIO_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#MINIO_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#MINIO_SERVERS[@]} serveurs MinIO..."
    for server in "${MINIO_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 60 secondes pour que MinIO redemarre..."
    sleep 60
    echo ""
fi

# Groupe 5: Redis (avant HAProxy)
log_info "Groupe 5: Redis..."
REDIS_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "redis" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        REDIS_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#REDIS_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#REDIS_SERVERS[@]} serveurs Redis..."
    for server in "${REDIS_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 60 secondes pour que Redis redemarre..."
    sleep 60
    echo ""
fi

# Groupe 6: RabbitMQ
log_info "Groupe 6: RabbitMQ..."
RABBITMQ_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "queue" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        RABBITMQ_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#RABBITMQ_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#RABBITMQ_SERVERS[@]} serveurs RabbitMQ..."
    for server in "${RABBITMQ_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 60 secondes pour que RabbitMQ redemarre..."
    sleep 60
    echo ""
fi

# Groupe 7: MariaDB Galera
log_info "Groupe 7: MariaDB Galera..."
MARIADB_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "mariadb" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        MARIADB_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#MARIADB_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#MARIADB_SERVERS[@]} serveurs MariaDB..."
    for server in "${MARIADB_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 90 secondes pour que MariaDB redemarre..."
    sleep 90
    echo ""
fi

# Groupe 8: ProxySQL
log_info "Groupe 8: ProxySQL..."
PROXYSQL_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db_proxy" ]] && [[ "${SUBROLE}" == "proxysql" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PROXYSQL_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#PROXYSQL_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#PROXYSQL_SERVERS[@]} serveurs ProxySQL..."
    for server in "${PROXYSQL_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 60 secondes pour que ProxySQL redemarre..."
    sleep 60
    echo ""
fi

# Groupe 9: PostgreSQL (avant HAProxy)
log_info "Groupe 9: PostgreSQL (Patroni)..."
PG_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PG_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#PG_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#PG_SERVERS[@]} serveurs PostgreSQL..."
    for server in "${PG_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 90 secondes pour que PostgreSQL redemarre..."
    sleep 90
    echo ""
fi

# Groupe 10: HAProxy (en dernier, apres les backends)
log_info "Groupe 10: HAProxy (en dernier)..."
HAPROXY_SERVERS=()
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        HAPROXY_SERVERS+=("${HOSTNAME}:${IP_PRIVEE}")
    fi
done < "${TSV_FILE}"

if [[ ${#HAPROXY_SERVERS[@]} -gt 0 ]]; then
    log_info "Redemarrage de ${#HAPROXY_SERVERS[@]} serveurs HAProxy..."
    for server in "${HAPROXY_SERVERS[@]}"; do
        IFS=':' read -r hostname ip <<< "${server}"
        restart_server "${hostname}" "${ip}" || true
        sleep 10
    done
    log_info "Attente 60 secondes pour que HAProxy redemarre..."
    sleep 60
    echo ""
fi

# Resume final
echo ""
echo "=============================================================="
echo " Redemarrage termine"
echo "=============================================================="
log_info "Tous les serveurs ont ete redemarres par groupes"
log_info "Attendez quelques minutes pour que tous les services redemarrent completement"
log_info "Vous pouvez ensuite executer les scripts de test pour verifier l'etat"
echo ""

