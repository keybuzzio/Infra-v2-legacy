#!/bin/bash
set -e

cd /root/install-01/11_n8n

# Trouver servers.tsv
TSV_FILE=""
for path in /root/install-01/servers.tsv /root/servers.tsv /root/install-01/../servers.tsv; do
    if [[ -f "$path" ]]; then
        TSV_FILE="$path"
        break
    fi
done

if [[ -z "$TSV_FILE" ]]; then
    echo "ERREUR: servers.tsv introuvable"
    echo "Recherche dans:"
    find /root -maxdepth 3 -name "servers.tsv" 2>/dev/null || echo "Aucun fichier trouvé"
    exit 1
fi

echo "Utilisation de: $TSV_FILE"
bash 11_n8n_apply_all.sh "$TSV_FILE" --yes

