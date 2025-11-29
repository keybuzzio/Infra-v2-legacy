#!/bin/bash
#
# complete_module11.sh - Finalise le Module 11 Chatwoot
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

SCRIPT_DIR="/opt/keybuzz-installer-v2/scripts/11_support_chatwoot"

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Finalisation Complète"
echo "=============================================================="
echo ""

# Étape 1 : Migrations
echo "=== ÉTAPE 1/4 : Exécution des migrations ==="
cd "$SCRIPT_DIR"
bash 11_ct_04_run_migrations.sh

if [ $? -ne 0 ]; then
    echo "❌ Échec des migrations"
    exit 1
fi

echo ""
echo "=== ÉTAPE 2/4 : Exécution db:seed ==="
bash 11_ct_04b_run_seed.sh

if [ $? -ne 0 ]; then
    echo "⚠️ db:seed a échoué (peut être normal si déjà exécuté)"
fi

echo ""
echo "=== ÉTAPE 3/4 : Redémarrage des pods ==="
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot

echo "Attente du démarrage des pods (60 secondes)..."
sleep 60

echo ""
echo "État des pods:"
kubectl get pods -n chatwoot

echo ""
echo "=== ÉTAPE 4/4 : Tests de validation ==="
bash 11_ct_03_tests.sh

echo ""
echo "✅ Module 11 finalisé !"
echo ""

