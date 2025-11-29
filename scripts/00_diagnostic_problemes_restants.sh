#!/usr/bin/env bash
#
# 00_diagnostic_problemes_restants.sh - Diagnostic des 3 problemes identifies
#
# Usage:
#   ./00_diagnostic_problemes_restants.sh [servers.tsv]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

echo "=============================================================="
echo " [KeyBuzz] Diagnostic des Problemes Restants"
echo "=============================================================="
echo ""

# Probleme 1: HAProxy sur haproxy-01
echo "--- PROBLEME 1: HAProxy container sur haproxy-01 ---"
HAPROXY_01_IP=$(get_ip "haproxy-01")
if [[ -n "${HAPROXY_01_IP}" ]]; then
    echo "  IP: ${HAPROXY_01_IP}"
    echo "  Docker containers:"
    ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps -a | grep haproxy || echo '  Aucun conteneur haproxy'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Docker logs (dernieres 20 lignes):"
    ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker logs haproxy --tail 20 2>&1 || echo '  Pas de logs disponibles'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Systemd status:"
    ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "systemctl status haproxy --no-pager -l 2>&1 | head -20 || echo '  Service systemd non trouve'" 2>/dev/null || echo "  SSH inaccessible"
fi
echo ""

# Probleme 2: Patroni cluster - pas de leader
echo "--- PROBLEME 2: Patroni cluster - pas de leader ---"
DB_MASTER_01_IP=$(get_ip "db-master-01")
if [[ -n "${DB_MASTER_01_IP}" ]]; then
    echo "  IP db-master-01: ${DB_MASTER_01_IP}"
    echo "  Patroni cluster status:"
    ssh ${SSH_OPTS} root@"${DB_MASTER_01_IP}" "docker exec patroni patronictl list 2>&1 || echo '  Erreur patronictl'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Patroni container logs (dernieres 30 lignes):"
    ssh ${SSH_OPTS} root@"${DB_MASTER_01_IP}" "docker logs patroni --tail 30 2>&1 | tail -30" 2>/dev/null || echo "  SSH inaccessible"
fi
echo ""

# Probleme 3: Redis master non detecte via Sentinel
echo "--- PROBLEME 3: Redis master non detecte via Sentinel ---"
REDIS_01_IP=$(get_ip "redis-01")
if [[ -n "${REDIS_01_IP}" ]]; then
    echo "  IP redis-01: ${REDIS_01_IP}"
    echo "  Sentinel info:"
    ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec sentinel redis-cli -p 26379 SENTINEL masters 2>&1 || echo '  Erreur Sentinel'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Sentinel get-master-addr-by-name:"
    ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name keybuzz-master 2>&1 || echo '  Erreur get-master-addr-by-name'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Sentinel sentinels:"
    ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec sentinel redis-cli -p 26379 SENTINEL sentinels keybuzz-master 2>&1 | head -20 || echo '  Erreur sentinels'" 2>/dev/null || echo "  SSH inaccessible"
    echo "  Redis containers status:"
    for hostname in redis-01 redis-02 redis-03; do
        ip=$(get_ip "${hostname}")
        if [[ -n "${ip}" ]]; then
            echo "    ${hostname} (${ip}):"
            ssh ${SSH_OPTS} root@"${ip}" "docker exec redis redis-cli INFO replication 2>&1 | grep -E 'role|master_host|master_port|master_link_status' || echo '      Erreur INFO replication'" 2>/dev/null || echo "      SSH inaccessible"
        fi
    done
fi
echo ""

echo "=============================================================="
echo " Diagnostic termine"
echo "=============================================================="

