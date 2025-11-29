#!/usr/bin/env bash
# Script à exécuter depuis install-01 pour ajouter les règles UFW sur tous les workers
# Utilise les IPs privées (10.0.0.x) pour se connecter aux workers

set +e

echo "=============================================================="
echo " [KeyBuzz] Ajout Règles UFW sur tous les Workers K3s"
echo "=============================================================="
echo ""

# Liste des workers avec leurs IPs PRIVÉES
declare -a WORKERS=(
    "k3s-worker-01|10.0.0.110"
    "k3s-worker-02|10.0.0.111"
    "k3s-worker-03|10.0.0.112"
    "k3s-worker-04|10.0.0.113"
    "k3s-worker-05|10.0.0.114"
)

echo "Total: ${#WORKERS[@]} workers à traiter"
echo ""

SUCCESS=0
FAIL=0

# Pour chaque worker
for worker_info in "${WORKERS[@]}"; do
    IFS='|' read -r name ip <<< "$worker_info"
    echo "=========================================="
    echo "Traitement de $name ($ip)..."
    echo "=========================================="
    
    # Exécuter les commandes UFW via SSH avec IP privée
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" "ufw allow from 10.42.0.0/16 to any comment 'K3s pods network' && ufw allow from 10.43.0.0/16 to any comment 'K3s services network' && ufw allow 8472/udp comment 'K3s flannel VXLAN' && ufw allow 10250/tcp comment 'K3s kubelet' && echo 'OK'" 2>&1; then
        echo "   ✅ Règles UFW ajoutées sur $name"
        ((SUCCESS++))
    else
        echo "   ❌ Échec sur $name"
        ((FAIL++))
    fi
    
    echo ""
done

echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Succès: $SUCCESS / ${#WORKERS[@]}"
echo "❌ Échecs: $FAIL / ${#WORKERS[@]}"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo "✅ Toutes les règles UFW ont été ajoutées avec succès !"
    echo ""
    echo "Attendez 10 secondes puis testez les URLs:"
    echo "  - https://platform.keybuzz.io"
    echo "  - https://platform-api.keybuzz.io"
else
    echo "⚠️  Certains workers ont échoué. Vérifiez l'accès SSH."
fi

echo ""
echo "=============================================================="

