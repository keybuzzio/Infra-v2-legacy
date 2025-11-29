#!/usr/bin/env bash
#
# 00_correction_problemes_restants.sh - Correction des 3 problemes identifies
#
# 1. HAProxy sur haproxy-01 : Redemarrer le conteneur
# 2. Patroni cluster : Forcer le bootstrap du leader
# 3. Redis Sentinel : Verifier et redemarrer si necessaire
#
# Usage:
#   ./00_correction_problemes_restants.sh [servers.tsv]
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
echo " [KeyBuzz] Correction des Problemes Restants"
echo "=============================================================="
echo ""

# Probleme 1: HAProxy sur haproxy-01
echo "--- CORRECTION 1: HAProxy sur haproxy-01 ---"
HAPROXY_01_IP=$(get_ip "haproxy-01")
if [[ -n "${HAPROXY_01_IP}" ]]; then
    echo "  IP: ${HAPROXY_01_IP}"
    
    # Verifier l'acces SSH
    if ! ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
        echo "  [FAIL] SSH inaccessible - Le serveur est peut-etre encore en redemarrage"
        echo "  [INFO] Attente 30 secondes..."
        sleep 30
    fi
    
    # Verifier si le conteneur existe
    if ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps -a | grep -q haproxy" 2>/dev/null; then
        echo "  [INFO] Conteneur HAProxy trouve, redemarrage..."
        ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker restart haproxy 2>&1 || docker start haproxy 2>&1" 2>/dev/null || true
        sleep 5
        if ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps | grep -q haproxy" 2>/dev/null; then
            echo "  [OK] HAProxy redemarre"
        else
            echo "  [FAIL] HAProxy n'a pas redemarre correctement"
        fi
    else
        echo "  [WARN] Conteneur HAProxy non trouve - Peut-etre deploye via systemd ou autre methode"
        # Essayer de redemarrer via systemd
        ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "systemctl restart haproxy 2>&1 || true" 2>/dev/null || true
        echo "  [INFO] Tentative de redemarrage via systemd effectuee"
    fi
else
    echo "  [FAIL] IP de haproxy-01 non trouvee dans servers.tsv"
fi
echo ""

# Probleme 2: Patroni cluster - Forcer bootstrap
echo "--- CORRECTION 2: Patroni cluster - Forcer bootstrap ---"
DB_MASTER_01_IP=$(get_ip "db-master-01")
DB_SLAVE_01_IP=$(get_ip "db-slave-01")
DB_SLAVE_02_IP=$(get_ip "db-slave-02")

if [[ -n "${DB_MASTER_01_IP}" ]] && [[ -n "${DB_SLAVE_01_IP}" ]] && [[ -n "${DB_SLAVE_02_IP}" ]]; then
    echo "  [INFO] Arret de tous les nœuds Patroni pour reinitialisation..."
    
    # Arreter tous les nœuds
    for ip in "${DB_MASTER_01_IP}" "${DB_SLAVE_01_IP}" "${DB_SLAVE_02_IP}"; do
        echo "    Arret Patroni sur ${ip}..."
        ssh ${SSH_OPTS} root@"${ip}" "docker stop patroni 2>/dev/null || true" 2>/dev/null || true
    done
    
    echo "  [INFO] Attente 10 secondes..."
    sleep 10
    
    # Redemarrer db-master-01 en premier (bootstrap)
    echo "  [INFO] Redemarrage de db-master-01 en premier (bootstrap)..."
    ssh ${SSH_OPTS} root@"${DB_MASTER_01_IP}" "docker start patroni 2>/dev/null || docker restart patroni 2>/dev/null" 2>/dev/null || true
    
    echo "  [INFO] Attente 30 secondes pour le bootstrap..."
    sleep 30
    
    # Redemarrer les replicas
    echo "  [INFO] Redemarrage des replicas..."
    for ip in "${DB_SLAVE_01_IP}" "${DB_SLAVE_02_IP}"; do
        echo "    Redemarrage Patroni sur ${ip}..."
        ssh ${SSH_OPTS} root@"${ip}" "docker start patroni 2>/dev/null || docker restart patroni 2>/dev/null" 2>/dev/null || true
        sleep 5
    done
    
    echo "  [INFO] Attente 30 secondes pour l'etablissement du cluster..."
    sleep 30
    
    # Verifier le leader
    echo "  [INFO] Verification du leader..."
    CLUSTER_STATUS=$(ssh ${SSH_OPTS} root@"${DB_MASTER_01_IP}" "docker exec patroni patronictl list 2>&1" 2>/dev/null || echo "")
    if echo "${CLUSTER_STATUS}" | grep -q "Leader"; then
        echo "  [OK] Leader Patroni detecte"
        echo "${CLUSTER_STATUS}" | head -10
    else
        echo "  [WARN] Leader Patroni non detecte encore"
        echo "  [INFO] Status actuel:"
        echo "${CLUSTER_STATUS}" | head -10
    fi
else
    echo "  [FAIL] IPs des nœuds Patroni non trouvees dans servers.tsv"
fi
echo ""

# Probleme 3: Redis Sentinel
echo "--- CORRECTION 3: Redis Sentinel ---"
REDIS_01_IP=$(get_ip "redis-01")
REDIS_02_IP=$(get_ip "redis-02")
REDIS_03_IP=$(get_ip "redis-03")

if [[ -n "${REDIS_01_IP}" ]] && [[ -n "${REDIS_02_IP}" ]] && [[ -n "${REDIS_03_IP}" ]]; then
    # Verifier et redemarrer Sentinel sur chaque nœud
    for hostname in redis-01 redis-02 redis-03; do
        case "${hostname}" in
            redis-01) ip="${REDIS_01_IP}" ;;
            redis-02) ip="${REDIS_02_IP}" ;;
            redis-03) ip="${REDIS_03_IP}" ;;
        esac
        
        echo "  [INFO] Verification Sentinel sur ${hostname} (${ip})..."
        
        # Verifier si le conteneur existe
        if ssh ${SSH_OPTS} root@"${ip}" "docker ps -a | grep -q redis-sentinel" 2>/dev/null; then
            # Verifier s'il est en cours d'execution
            if ssh ${SSH_OPTS} root@"${ip}" "docker ps | grep -q redis-sentinel" 2>/dev/null; then
                echo "    [OK] Sentinel actif sur ${hostname}"
            else
                echo "    [INFO] Sentinel arrete, redemarrage..."
                ssh ${SSH_OPTS} root@"${ip}" "docker start redis-sentinel 2>/dev/null || docker restart redis-sentinel 2>/dev/null" 2>/dev/null || true
                sleep 3
                if ssh ${SSH_OPTS} root@"${ip}" "docker ps | grep -q redis-sentinel" 2>/dev/null; then
                    echo "    [OK] Sentinel redemarre sur ${hostname}"
                else
                    echo "    [FAIL] Sentinel n'a pas redemarre sur ${hostname}"
                fi
            fi
        else
            echo "    [WARN] Conteneur redis-sentinel non trouve sur ${hostname}"
            echo "    [INFO] Il faudra peut-etre reinstaller Sentinel (04_redis_03_deploy_sentinel.sh)"
        fi
    done
    
    # Verifier le master via Sentinel
    echo "  [INFO] Verification du master Redis via Sentinel..."
    MASTER_INFO=$(ssh ${SSH_OPTS} root@"${REDIS_01_IP}" "docker exec redis-sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name keybuzz-master 2>/dev/null || docker exec redis-sentinel redis-cli -p 26379 SENTINEL get-master-addr-by-name kb-redis-master 2>/dev/null" 2>/dev/null || echo "")
    if [[ -n "${MASTER_INFO}" ]]; then
        MASTER_IP=$(echo "${MASTER_INFO}" | head -1)
        echo "  [OK] Master Redis detecte via Sentinel: ${MASTER_IP}"
    else
        echo "  [WARN] Master Redis non detecte via Sentinel"
        echo "  [INFO] Il faudra peut-etre reconfigurer Sentinel (04_redis_03_deploy_sentinel.sh)"
    fi
else
    echo "  [FAIL] IPs des nœuds Redis non trouvees dans servers.tsv"
fi
echo ""

echo "=============================================================="
echo " Correction terminee"
echo "=============================================================="
echo "  [INFO] Relancer 00_verification_complete_apres_redemarrage.sh pour verifier"
echo ""

