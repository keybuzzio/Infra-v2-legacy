#!/bin/bash
#
# backup_and_reboot.sh - Sauvegarde /tmp et redémarre install-01 proprement
#

set -euo pipefail

BACKUP_DIR="/root/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/tmp_backup_${TIMESTAMP}.tar.gz"

echo "=============================================================="
echo " [KeyBuzz] Sauvegarde /tmp et Redémarrage install-01"
echo "=============================================================="
echo ""

# 1. Créer le répertoire de sauvegarde
echo "1. Création du répertoire de sauvegarde..."
mkdir -p "${BACKUP_DIR}"
echo "✅ Répertoire créé: ${BACKUP_DIR}"
echo ""

# 2. Sauvegarder /tmp
echo "2. Sauvegarde de /tmp..."
if [ -d /tmp ] && [ "$(ls -A /tmp 2>/dev/null)" ]; then
    tar -czf "${BACKUP_FILE}" -C /tmp . 2>/dev/null || {
        echo "⚠️ Certains fichiers n'ont pas pu être sauvegardés (normal si en cours d'utilisation)"
        tar -czf "${BACKUP_FILE}" -C /tmp . 2>&1 | grep -v "file changed" || true
    }
    
    if [ -f "${BACKUP_FILE}" ]; then
        SIZE=$(du -h "${BACKUP_FILE}" | cut -f1)
        echo "✅ Sauvegarde créée: ${BACKUP_FILE} (${SIZE})"
    else
        echo "❌ Échec de la sauvegarde"
        exit 1
    fi
else
    echo "⚠️ /tmp est vide ou n'existe pas"
    touch "${BACKUP_FILE}"
    echo "✅ Fichier de sauvegarde créé (vide)"
fi
echo ""

# 3. Lister les sauvegardes existantes
echo "3. Sauvegardes existantes:"
ls -lh "${BACKUP_DIR}"/tmp_backup_*.tar.gz 2>/dev/null | tail -5 || echo "Aucune sauvegarde précédente"
echo ""

# 4. Vérifier les processus critiques
echo "4. Vérification des processus critiques..."
echo "   Jobs en cours:"
jobs 2>/dev/null || echo "   Aucun job en cours"
echo ""

# 5. Vérifier les services Kubernetes (si install-01 est un node)
echo "5. Vérification des services..."
if systemctl list-units --type=service | grep -q kubelet; then
    echo "   ⚠️ kubelet détecté - le cluster Kubernetes sera affecté"
else
    echo "   ✅ install-01 n'est pas un node Kubernetes"
fi
echo ""

# 6. Synchroniser les disques
echo "6. Synchronisation des disques..."
sync
echo "✅ Synchronisation terminée"
echo ""

# 7. Redémarrage
echo "7. Redémarrage du serveur..."
echo "   ⚠️ Le serveur va redémarrer dans 10 secondes"
echo "   Appuyez sur Ctrl+C dans les 10 prochaines secondes pour annuler"
echo ""
sleep 10

echo "Redémarrage en cours..."
shutdown -r +1 "Redémarrage demandé par script backup_and_reboot.sh"

echo ""
echo "=============================================================="
echo "✅ Redémarrage programmé dans 1 minute"
echo "   Sauvegarde: ${BACKUP_FILE}"
echo "=============================================================="


