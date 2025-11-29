#!/bin/bash
#
# reboot_immediate.sh - Redémarrage immédiat d'install-01
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Redémarrage IMMÉDIAT install-01"
echo "=============================================================="
echo ""

# Sauvegarder /tmp rapidement
echo "Sauvegarde rapide de /tmp..."
BACKUP_DIR="/root/backups"
mkdir -p "${BACKUP_DIR}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/tmp_backup_${TIMESTAMP}.tar.gz"

if [ -d /tmp ] && [ "$(ls -A /tmp 2>/dev/null)" ]; then
    tar -czf "${BACKUP_FILE}" -C /tmp . 2>/dev/null || true
    if [ -f "${BACKUP_FILE}" ]; then
        SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        echo "✅ Sauvegarde créée: ${BACKUP_FILE} (${SIZE})"
    fi
fi

# Synchroniser
echo "Synchronisation des disques..."
sync

# Annuler tout redémarrage programmé
shutdown -c 2>/dev/null || true

echo ""
echo "⚠️ REDÉMARRAGE IMMÉDIAT EN COURS..."
echo ""

# Redémarrage immédiat
if command -v reboot >/dev/null 2>&1; then
    reboot
elif command -v systemctl >/dev/null 2>&1; then
    systemctl reboot
elif command -v shutdown >/dev/null 2>&1; then
    shutdown -r now
else
    /sbin/reboot
fi


