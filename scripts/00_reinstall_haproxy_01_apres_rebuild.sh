#!/usr/bin/env bash
#
# 00_reinstall_haproxy_01_apres_rebuild.sh - Reinstallation complete de haproxy-01 apres rebuild
#
# Ce script reinstallera tous les modules necessaires sur haproxy-01 :
# - Module 1 & 2 : Base OS + Securite
# - Module 3 : HAProxy (PostgreSQL + PgBouncer + Redis + RabbitMQ)
# - Module 4 : PgBouncer
#
# Usage:
#   ./00_reinstall_haproxy_01_apres_rebuild.sh [servers.tsv]
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

HAPROXY_01_IP=$(get_ip "haproxy-01")

if [[ -z "${HAPROXY_01_IP}" ]]; then
    echo "  [FAIL] IP de haproxy-01 non trouvee dans servers.tsv"
    exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Reinstallation haproxy-01 apres Rebuild"
echo " IP: ${HAPROXY_01_IP}"
echo "=============================================================="
echo ""

# Verification acces SSH
echo "--- ETAPE 1: Verification Acces SSH ---"
if ! ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
    echo "  [FAIL] SSH inaccessible sur haproxy-01 (${HAPROXY_01_IP})"
    echo "  [INFO] Verifiez que le serveur est bien rebuild et accessible"
    exit 1
fi
echo "  [OK] SSH accessible"
echo ""

# Liste des scripts a executer dans l'ordre
echo "--- ETAPE 2: Plan de Reinstallation ---"
echo "  Les scripts suivants seront executes dans l'ordre :"
echo ""
echo "  1. Module 1 & 2 : Base OS + Securite"
echo "     - 01_base_os/01_base_os_install.sh (sur haproxy-01 uniquement)"
echo ""
echo "  2. Module 3 : HAProxy"
echo "     - 03_postgresql_ha/05_haproxy_patroni_FIXED_V2.sh (sur haproxy-01 uniquement)"
echo ""
echo "  3. Module 4 : PgBouncer"
echo "     - 03_postgresql_ha/06_pgbouncer_scram_CORRECTED_V5.sh (sur haproxy-01 uniquement)"
echo ""
echo "  4. Module 4 : HAProxy Redis"
echo "     - 04_redis_ha/04_redis_04_configure_haproxy_redis.sh (sur haproxy-01 uniquement)"
echo ""
echo "  [INFO] Note: Les scripts doivent etre adaptes pour ne traiter que haproxy-01"
echo ""

# Confirmation
read -p "Continuer avec la reinstallation ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    echo "  [INFO] Operation annulee"
    exit 0
fi

echo ""
echo "=============================================================="
echo " [INFO] Instructions manuelles"
echo "=============================================================="
echo ""
echo "  Pour reinstaller haproxy-01, executez les commandes suivantes"
echo "  depuis install-01 dans l'ordre :"
echo ""
echo "  1. Base OS :"
echo "     cd /opt/keybuzz-installer/scripts/01_base_os"
echo "     bash 01_base_os_install.sh /opt/keybuzz-installer/servers.tsv haproxy-01"
echo ""
echo "  2. HAProxy (PostgreSQL + PgBouncer) :"
echo "     cd /opt/keybuzz-installer/scripts/03_postgresql_ha"
echo "     bash 05_haproxy_patroni_FIXED_V2.sh /opt/keybuzz-installer/servers.tsv haproxy-01"
echo ""
echo "  3. PgBouncer :"
echo "     cd /opt/keybuzz-installer/scripts/03_postgresql_ha"
echo "     bash 06_pgbouncer_scram_CORRECTED_V5.sh /opt/keybuzz-installer/servers.tsv haproxy-01"
echo ""
echo "  4. HAProxy Redis :"
echo "     cd /opt/keybuzz-installer/scripts/04_redis_ha"
echo "     bash 04_redis_04_configure_haproxy_redis.sh /opt/keybuzz-installer/servers.tsv haproxy-01"
echo ""
echo "  5. Verification :"
echo "     cd /opt/keybuzz-installer/scripts"
echo "     bash 00_verification_complete_apres_redemarrage.sh /opt/keybuzz-installer/servers.tsv"
echo ""
echo "=============================================================="

