#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== AJOUT IMAGEPULLSECRETS AUX DEPLOYMENTS MODULE 10 ==="
echo ""

for deployment in keybuzz-api keybuzz-ui keybuzz-my-ui; do
    echo "Ajout imagePullSecrets à $deployment..."
    kubectl patch deployment $deployment -n keybuzz --type='json' -p='[{"op": "add", "path": "/spec/template/spec/imagePullSecrets", "value": [{"name": "ghcr-secret"}]}]' 2>&1 || echo "Échec pour $deployment"
done

echo ""
echo "Redémarrage des Deployments..."
kubectl rollout restart deployment/keybuzz-api -n keybuzz
kubectl rollout restart deployment/keybuzz-ui -n keybuzz
kubectl rollout restart deployment/keybuzz-my-ui -n keybuzz

echo ""
echo "Attente 30s..."
sleep 30

echo ""
echo "État des pods:"
kubectl get pods -n keybuzz -o wide

