#!/bin/bash
# Script pour copier les scripts corrigés Patroni sur install-01
# Usage: ./copy_fixed_patroni_scripts.sh

# Chemins locaux (Windows)
LOCAL_SCRIPT_DIR="Infra/scripts/03_postgresql_ha"
INSTALL01_IP="91.98.128.153"
INSTALL01_USER="root"
REMOTE_SCRIPT_DIR="/opt/keybuzz-installer/scripts/03_postgresql_ha"

echo "=== Copie des scripts corrigés Patroni vers install-01 ==="
echo ""

# Fichiers à copier
FILES=(
    "03_pg_02_install_patroni_cluster.sh"
    "03_pg_apply_all.sh"
)

for file in "${FILES[@]}"; do
    if [[ -f "${LOCAL_SCRIPT_DIR}/${file}" ]]; then
        echo "Copie de ${file}..."
        # Copier via scp (nécessite que scp soit configuré)
        scp "${LOCAL_SCRIPT_DIR}/${file}" "${INSTALL01_USER}@${INSTALL01_IP}:${REMOTE_SCRIPT_DIR}/${file}"
        echo "  ✅ ${file} copié"
    else
        echo "  ❌ ${file} introuvable localement"
    fi
done

echo ""
echo "✅ Copie terminée"
echo ""
echo "Pour relancer l'installation :"
echo "  ssh root@${INSTALL01_IP}"
echo "  cd ${REMOTE_SCRIPT_DIR}"
echo "  ./03_pg_apply_all.sh ../../servers.tsv --yes"













