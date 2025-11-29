#!/bin/bash
#
# reboot_install01.sh - Script de redémarrage robuste pour install-01
# À exécuter directement sur install-01
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Redémarrage install-01"
echo "=============================================================="
echo ""

# Sauvegarder /tmp
echo "1. Sauvegarde de /tmp..."
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
echo ""

# Annuler tout redémarrage programmé
echo "2. Annulation des redémarrages programmés..."
shutdown -c 2>/dev/null || true
echo ""

# Synchroniser
echo "3. Synchronisation des disques..."
sync
echo "✅ Synchronisation terminée"
echo ""

# Vérifier l'uptime actuel
echo "4. État actuel:"
uptime
echo "Dernier redémarrage:"
who -b 2>/dev/null || last reboot 2>/dev/null | head -1 || echo "N/A"
echo ""

# Redémarrage
echo "5. REDÉMARRAGE"
echo "=============================================================="
echo "⚠️ Le serveur va redémarrer dans 5 secondes"
echo "   Appuyez sur Ctrl+C pour annuler"
echo ""
sleep 5

echo "Exécution de la commande reboot..."
echo ""

# Méthode 1: reboot direct
if command -v reboot >/dev/null 2>&1; then
    echo "Utilisation: reboot"
    exec reboot
# Méthode 2: systemctl
elif command -v systemctl >/dev/null 2>&1; then
    echo "Utilisation: systemctl reboot"
    exec systemctl reboot
# Méthode 3: shutdown
elif command -v shutdown >/dev/null 2>&1; then
    echo "Utilisation: shutdown -r now"
    exec shutdown -r now
# Méthode 4: /sbin/reboot
else
    echo "Utilisation: /sbin/reboot"
    exec /sbin/reboot
fi


