#!/usr/bin/env bash
#
# fix_ssh_host_key.sh - Supprime l'ancienne clé d'hôte SSH pour install-01
#
# Usage:
#   ./fix_ssh_host_key.sh [IP]
#
# Ce script supprime l'ancienne entrée de known_hosts pour permettre
# la reconnexion avec la nouvelle clé d'hôte

set -euo pipefail

INSTALL_01_IP="${1:-91.98.128.153}"
KNOWN_HOSTS="${HOME}/.ssh/known_hosts"

echo "=============================================================="
echo " [KeyBuzz] Nettoyage de la clé d'hôte SSH"
echo "=============================================================="
echo ""
echo "IP cible : ${INSTALL_01_IP}"
echo "Fichier known_hosts : ${KNOWN_HOSTS}"
echo ""

# Vérifier si known_hosts existe
if [[ ! -f "${KNOWN_HOSTS}" ]]; then
    echo "⚠️  Fichier known_hosts introuvable : ${KNOWN_HOSTS}"
    echo "✅ Aucune action nécessaire"
    exit 0
fi

# Afficher les entrées existantes
echo "Entrées existantes pour ${INSTALL_01_IP} :"
grep "${INSTALL_01_IP}" "${KNOWN_HOSTS}" || echo "Aucune entrée trouvée"
echo ""

# Supprimer l'ancienne entrée
if grep -q "${INSTALL_01_IP}" "${KNOWN_HOSTS}"; then
    echo "Suppression de l'ancienne clé d'hôte..."
    ssh-keygen -R "${INSTALL_01_IP}" 2>/dev/null || {
        # Méthode manuelle si ssh-keygen échoue
        echo "Utilisation de la méthode manuelle..."
        grep -v "${INSTALL_01_IP}" "${KNOWN_HOSTS}" > "${KNOWN_HOSTS}.tmp" && \
        mv "${KNOWN_HOSTS}.tmp" "${KNOWN_HOSTS}"
    }
    echo "✅ Ancienne clé supprimée"
else
    echo "✅ Aucune ancienne clé à supprimer"
fi

echo ""
echo "=============================================================="
echo "✅ Nettoyage terminé"
echo "=============================================================="
echo ""
echo "Prochaine étape :"
echo "  ssh root@${INSTALL_01_IP}"
echo ""
echo "Vous devrez accepter la nouvelle clé d'hôte (taper 'yes')"
echo ""


