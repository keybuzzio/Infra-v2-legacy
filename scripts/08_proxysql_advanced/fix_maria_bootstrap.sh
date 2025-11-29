#!/usr/bin/env bash
#
# fix_maria_bootstrap.sh - Corriger le bootstrap Galera après redémarrage
#

set -euo pipefail

MARIADB_IP="${1:-10.0.0.170}"

echo "Correction du bootstrap Galera sur ${MARIADB_IP}..."

ssh -o StrictHostKeyChecking=no root@${MARIADB_IP} bash <<'EOF'
BASE="/opt/keybuzz/mariadb"

# Forcer le bootstrap
if [[ -f "${BASE}/data/grastate.dat" ]]; then
    echo "Modification de grastate.dat..."
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "${BASE}/data/grastate.dat" || true
    echo "  ✓ grastate.dat modifié"
fi

# Redémarrer MariaDB
echo "Redémarrage de MariaDB..."
docker restart mariadb || true

# Attendre
sleep 15

# Vérifier
source /tmp/mariadb.env 2>/dev/null || source /opt/keybuzz-installer/credentials/mariadb.env
if docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
    echo "  ✓ MariaDB opérationnel"
else
    echo "  ✗ MariaDB toujours en erreur"
    docker logs mariadb 2>&1 | tail -10
fi
EOF

