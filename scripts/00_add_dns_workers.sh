#!/usr/bin/env bash
# Script à exécuter depuis install-01 pour ajouter les DNS sur tous les workers
# Utilise les IPs privées (10.0.0.x) pour se connecter aux workers

set +e

echo "=============================================================="
echo " [KeyBuzz] Ajout DNS (8.8.8.8, 1.1.1.1) sur tous les Workers K3s"
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
    
    # Ajouter les DNS via SSH avec IP privée
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"$ip" "bash -c '
        # Sauvegarder la configuration actuelle
        cp /etc/resolv.conf /etc/resolv.conf.backup 2>/dev/null || true
        
        # Ajouter Google DNS et Cloudflare DNS si pas déjà présent
        if ! grep -q \"8.8.8.8\" /etc/resolv.conf; then
            echo \"nameserver 8.8.8.8\" >> /etc/resolv.conf
            echo \"nameserver 1.1.1.1\" >> /etc/resolv.conf
            echo \"✅ DNS ajoutés\"
        else
            echo \"ℹ️  DNS déjà présents\"
        fi
        
        # Vérifier
        echo \"Configuration DNS actuelle:\"
        cat /etc/resolv.conf
    '" 2>&1
    
    if [[ $? -eq 0 ]]; then
        echo "   ✅ DNS configurés sur $name"
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
    echo "✅ Tous les DNS ont été configurés avec succès !"
    echo ""
    echo "Redémarrage des déploiements KeyBuzz..."
    kubectl rollout restart deployment/keybuzz-api -n keybuzz 2>/dev/null || true
    kubectl rollout restart deployment/keybuzz-front -n keybuzz 2>/dev/null || true
    echo "✅ Déploiements redémarrés"
else
    echo "⚠️  Certains workers ont échoué. Vérifiez l'accès SSH."
fi

echo ""
echo "=============================================================="

