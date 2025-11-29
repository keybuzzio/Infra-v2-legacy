#!/usr/bin/env bash
#
# verify_deployment.sh - Vérifie le déploiement des images placeholder
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=============================================================="
echo " [KeyBuzz] Vérification du déploiement Module 10"
echo "=============================================================="
echo ""

echo "📦 Images déployées:"
kubectl get deployments -n keybuzz -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
echo ""

echo "✅ État des Deployments:"
kubectl get deployments -n keybuzz
echo ""

echo "✅ État des Pods:"
kubectl get pods -n keybuzz
echo ""

echo "🌐 Services:"
kubectl get services -n keybuzz
echo ""

echo "🔗 Ingress:"
kubectl get ingress -n keybuzz
echo ""

echo "=============================================================="
echo "✅ Vérification terminée"
echo "=============================================================="
echo ""
echo "Pour tester les endpoints (si DNS configuré):"
echo "  curl -k https://platform-api.keybuzz.io/health"
echo "  curl -k https://platform.keybuzz.io"
echo "  curl -k https://my.keybuzz.io"
echo ""

