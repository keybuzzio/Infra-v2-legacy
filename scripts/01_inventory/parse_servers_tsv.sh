#!/usr/bin/env bash
#
# parse_servers_tsv.sh - Parser et valider le fichier servers.tsv
#
# Usage:
#   ./parse_servers_tsv.sh /chemin/vers/servers.tsv
#
# Ce script valide le format TSV et affiche des statistiques

set -euo pipefail

TSV_FILE="${1:-./servers.tsv}"

if [[ ! -f "${TSV_FILE}" ]]; then
  echo "❌ Fichier TSV introuvable: ${TSV_FILE}"
  exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Parsing de l'inventaire servers.tsv"
echo " Fichier : ${TSV_FILE}"
echo "=============================================================="

# Compter les lignes (sans header)
TOTAL_SERVERS=$(tail -n +2 "${TSV_FILE}" | wc -l)
echo "📊 Total de serveurs : ${TOTAL_SERVERS}"

# Compter par rôle
echo ""
echo "📋 Répartition par rôle :"
tail -n +2 "${TSV_FILE}" | cut -f8 | sort | uniq -c | sort -rn

# Compter par pool
echo ""
echo "📋 Répartition par pool :"
tail -n +2 "${TSV_FILE}" | cut -f7 | sort | uniq -c | sort -rn

# Lister les serveurs CORE
echo ""
echo "⭐ Serveurs CORE (indispensables pour KeyBuzz v1) :"
tail -n +2 "${TSV_FILE}" | awk -F'\t' '$11 == "yes" {print $3 " (" $4 ") - " $8 "/" $9}'

# Vérifier les IPs privées uniques
echo ""
echo "🔍 Vérification des IPs privées..."
DUPLICATES=$(tail -n +2 "${TSV_FILE}" | cut -f4 | sort | uniq -d)
if [[ -n "${DUPLICATES}" ]]; then
  echo "⚠️  IPs privées dupliquées détectées :"
  echo "${DUPLICATES}"
else
  echo "✅ Toutes les IPs privées sont uniques"
fi

echo ""
echo "=============================================================="
echo "✅ Parsing terminé"
echo "=============================================================="


