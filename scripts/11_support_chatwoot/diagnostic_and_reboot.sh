#!/bin/bash
#
# diagnostic_and_reboot.sh - Diagnostic et redémarrage forcé d'install-01
#

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Diagnostic et Redémarrage install-01"
echo "=============================================================="
echo ""

# 1. État actuel du serveur
echo "1. ÉTAT ACTUEL DU SERVEUR"
echo "--------------------------------------------------------------"
echo "Uptime:"
uptime
echo ""
echo "Date/heure système:"
date
echo ""
echo "Dernier redémarrage:"
who -b 2>/dev/null || last reboot 2>/dev/null | head -1 || echo "Information non disponible"
echo ""

# 2. Vérification de la sauvegarde
echo "2. VÉRIFICATION SAUVEGARDE /tmp"
echo "--------------------------------------------------------------"
BACKUP_DIR="/root/backups"
if [ -d "${BACKUP_DIR}" ]; then
    echo "Répertoire de sauvegarde existe"
    ls -lh "${BACKUP_DIR}"/tmp_backup_*.tar.gz 2>/dev/null | tail -3 || echo "Aucune sauvegarde trouvée"
else
    echo "⚠️ Répertoire de sauvegarde n'existe pas, création..."
    mkdir -p "${BACKUP_DIR}"
fi
echo ""

# 3. Sauvegarder /tmp maintenant si pas déjà fait
echo "3. SAUVEGARDE /tmp"
echo "--------------------------------------------------------------"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/tmp_backup_${TIMESTAMP}.tar.gz"

if [ -d /tmp ] && [ "$(ls -A /tmp 2>/dev/null)" ]; then
    echo "Création de la sauvegarde..."
    tar -czf "${BACKUP_FILE}" -C /tmp . 2>/dev/null || {
        echo "⚠️ Certains fichiers n'ont pas pu être sauvegardés (normal)"
    }
    
    if [ -f "${BACKUP_FILE}" ]; then
        SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        echo "✅ Sauvegarde créée: ${BACKUP_FILE} (${SIZE})"
    else
        echo "❌ Échec de la sauvegarde"
    fi
else
    echo "⚠️ /tmp est vide ou n'existe pas"
fi
echo ""

# 4. Vérifier les redémarrages programmés
echo "4. VÉRIFICATION REDÉMARRAGES PROGRAMMÉS"
echo "--------------------------------------------------------------"
if shutdown -c 2>&1 | grep -q "scheduled"; then
    echo "⚠️ Un redémarrage est déjà programmé"
    shutdown -c
    echo "✅ Redémarrage programmé annulé"
else
    echo "Aucun redémarrage programmé"
fi
echo ""

# 5. Vérifier les processus qui pourraient bloquer
echo "5. PROCESSUS CRITIQUES"
echo "--------------------------------------------------------------"
echo "Processus shutdown/reboot en cours:"
ps aux | grep -E 'shutdown|reboot' | grep -v grep || echo "Aucun"
echo ""

# 6. Vérifier les services
echo "6. SERVICES SYSTÈME"
echo "--------------------------------------------------------------"
if systemctl list-units --type=service | grep -q kubelet; then
    echo "⚠️ kubelet détecté - install-01 pourrait être un node Kubernetes"
else
    echo "✅ install-01 n'est pas un node Kubernetes"
fi
echo ""

# 7. Synchroniser les disques
echo "7. SYNCHRONISATION DISQUES"
echo "--------------------------------------------------------------"
sync
echo "✅ Synchronisation terminée"
echo ""

# 8. Redémarrage
echo "8. REDÉMARRAGE"
echo "--------------------------------------------------------------"
echo "⚠️ ATTENTION: Le serveur va redémarrer dans 10 secondes"
echo "   Appuyez sur Ctrl+C dans les 10 prochaines secondes pour annuler"
echo ""
for i in {10..1}; do
    echo -ne "\r   Redémarrage dans $i seconde(s)...   "
    sleep 1
done
echo ""
echo ""

echo "Redémarrage en cours..."
echo ""

# Essayer plusieurs méthodes de redémarrage
if command -v reboot >/dev/null 2>&1; then
    echo "Utilisation de la commande 'reboot'..."
    reboot
elif command -v systemctl >/dev/null 2>&1; then
    echo "Utilisation de 'systemctl reboot'..."
    systemctl reboot
elif command -v shutdown >/dev/null 2>&1; then
    echo "Utilisation de 'shutdown -r now'..."
    shutdown -r now
else
    echo "❌ Aucune commande de redémarrage trouvée"
    echo "Tentative avec /sbin/reboot..."
    /sbin/reboot 2>/dev/null || /usr/sbin/reboot 2>/dev/null || {
        echo "❌ Impossible de redémarrer automatiquement"
        echo "Veuillez redémarrer manuellement"
        exit 1
    }
fi

echo "✅ Commande de redémarrage exécutée"
echo ""
echo "Le serveur devrait redémarrer dans quelques secondes..."
echo ""


