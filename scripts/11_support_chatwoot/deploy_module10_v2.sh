#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== DEPLOIEMENT MODULE 10 V2 ==="
echo ""

# 1. Transférer credentials si nécessaire
echo "1. Vérification credentials..."
if [ ! -d /opt/keybuzz-installer-v2/credentials ]; then
    echo "Transfert credentials depuis install-01..."
    scp -r root@91.98.128.153:/opt/keybuzz-installer-v2/credentials /opt/keybuzz-installer-v2/ 2>&1 || echo "Échec transfert credentials"
fi

# 2. Déployer Module 10
echo ""
echo "2. Déploiement Module 10..."
cd /opt/keybuzz-installer-v2/scripts/10_platform
./deploy_module10_kubernetes.sh 2>&1

# 3. Déployer les apps
echo ""
echo "3. Déploiement des applications Platform..."
./deploy_platform_apps.sh ghcr.io/keybuzzio/platform-api:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 2>&1

# 4. Mettre à jour les images
echo ""
echo "4. Mise à jour des images..."
./update_platform_images.sh ghcr.io/keybuzzio/platform-api:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 2>&1

# 5. Vérifier les pods
echo ""
echo "5. Vérification des pods..."
sleep 30
kubectl get pods -n keybuzz -o wide

echo ""
echo "=== DEPLOIEMENT TERMINE ==="

