#!/bin/bash
export KUBECONFIG=/root/.kube/config

echo "=== Mise à jour images vers latest ==="
kubectl set image deployment/chatwoot-web -n chatwoot chatwoot-web=chatwoot/chatwoot:latest
kubectl set image deployment/chatwoot-worker -n chatwoot chatwoot-worker=chatwoot/chatwoot:latest

echo ""
echo "=== Suppression Job et relance ==="
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 3

cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
timeout 600 bash 11_ct_04_run_migrations.sh

