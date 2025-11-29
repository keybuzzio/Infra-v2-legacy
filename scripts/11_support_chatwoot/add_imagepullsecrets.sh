#!/usr/bin/env bash
#
# Ajoute imagePullSecrets aux Deployments Chatwoot
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== Ajout de imagePullSecrets aux Deployments ==="

# Créer un fichier YAML temporaire pour le patch
cat > /tmp/patch-imagepullsecrets.yaml <<EOF
spec:
  template:
    spec:
      imagePullSecrets:
      - name: ghcr-secret
EOF

# Appliquer le patch
kubectl patch deployment chatwoot-web -n chatwoot --patch-file=/tmp/patch-imagepullsecrets.yaml
kubectl patch deployment chatwoot-worker -n chatwoot --patch-file=/tmp/patch-imagepullsecrets.yaml

echo "ImagePullSecrets ajoutés avec succès"

# Nettoyer
rm -f /tmp/patch-imagepullsecrets.yaml

