#!/usr/bin/env bash
#
# 00_disaster_recovery_haproxy_01_SIMPLE.sh - Disaster Recovery automatique pour haproxy-01
#
# IMPORTANT: Ce script DOIT etre execute depuis install-01 uniquement
# Conforme au Context.txt : tous les scripts d'installation s'executent depuis install-01
#
# Usage:
#   cd /opt/keybuzz-installer/scripts
#   bash 00_disaster_recovery_haproxy_01_SIMPLE.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${INSTALL_DIR}/servers.tsv"
HAPROXY_01_IP="10.0.0.11"

# Options SSH (depuis install-01 vers IP privees 10.0.0.x, pas besoin de cle)
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes"

echo "=============================================================="
echo " [KeyBuzz] Disaster Recovery - haproxy-01 (SIMPLE)"
echo " IP: ${HAPROXY_01_IP}"
echo "=============================================================="
echo ""

# Phase 1: Verification SSH
echo "[1] Verification SSH..."
if ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
    echo "  [OK] SSH accessible"
else
    echo "  [FAIL] SSH inaccessible"
    exit 1
fi

# Phase 2: Detection etat
echo "[2] Detection etat serveur..."
DOCKER_INSTALLED=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "command -v docker >/dev/null 2>&1 && echo yes || echo no" 2>/dev/null || echo "no")
HAPROXY_CONTAINER=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps -a 2>/dev/null | grep -q haproxy && echo yes || echo no" 2>/dev/null || echo "no")

echo "  Docker: ${DOCKER_INSTALLED}"
echo "  HAProxy container: ${HAPROXY_CONTAINER}"

if [[ "${DOCKER_INSTALLED}" == "no" ]] || [[ "${HAPROXY_CONTAINER}" == "no" ]]; then
    echo "  [INFO] Serveur vide - Reinstallation necessaire"
    echo ""
    
    # Phase 3: Base OS
    echo "[3] Installation Base OS..."
    if [[ -f "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" ]]; then
        echo "  Copie du script base_os.sh vers haproxy-01..."
        scp ${SSH_OPTS} "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" root@"${HAPROXY_01_IP}":/tmp/base_os.sh
        echo "  Execution du script base_os.sh sur haproxy-01..."
        ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "chmod +x /tmp/base_os.sh && bash /tmp/base_os.sh lb internal-haproxy"
        echo "  [OK] Base OS installe"
    else
        echo "  [WARN] Script base_os.sh non trouve: ${SCRIPT_DIR}/02_base_os_and_security/base_os.sh"
    fi
    echo ""
    
    # Phase 4: HAProxy PostgreSQL
    echo "[4] Installation HAProxy PostgreSQL..."
    if [[ -f "${SCRIPT_DIR}/03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh" ]]; then
        echo "  Execution: 03_pg_03_install_haproxy_db_lb.sh"
        if bash "${SCRIPT_DIR}/03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh" "${TSV_FILE}"; then
            echo "  [OK] HAProxy PostgreSQL installe"
        else
            echo "  [FAIL] Echec installation HAProxy PostgreSQL"
            exit 1
        fi
    else
        echo "  [WARN] Script HAProxy PostgreSQL non trouve"
    fi
    echo ""
    
    # Phase 5: HAProxy Redis
    echo "[5] Installation HAProxy Redis..."
    if [[ -f "${SCRIPT_DIR}/04_redis_ha/04_redis_04_configure_haproxy_redis.sh" ]]; then
        echo "  Execution: 04_redis_04_configure_haproxy_redis.sh"
        if bash "${SCRIPT_DIR}/04_redis_ha/04_redis_04_configure_haproxy_redis.sh" "${TSV_FILE}"; then
            echo "  [OK] HAProxy Redis installe"
        else
            echo "  [FAIL] Echec installation HAProxy Redis"
            exit 1
        fi
    else
        echo "  [WARN] Script HAProxy Redis non trouve"
    fi
    echo ""
    
    # Phase 6: Verification
    echo "[6] Verification finale..."
    sleep 5
    if ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps | grep -q haproxy" 2>/dev/null; then
        echo "  [OK] HAProxy container actif"
    else
        echo "  [FAIL] HAProxy container non actif"
    fi
    
    echo ""
    echo "=============================================================="
    echo " [OK] Disaster Recovery termine"
    echo "=============================================================="
else
    echo "  [OK] Serveur deja configure"
fi

