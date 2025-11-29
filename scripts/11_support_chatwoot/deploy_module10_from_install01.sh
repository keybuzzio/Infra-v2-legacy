#!/usr/bin/env bash
set -euo pipefail

echo "=== DEPLOIEMENT MODULE 10 V2 depuis install-01 ==="
echo ""

# Transférer credentials vers master
echo "1. Transfert credentials vers master..."
scp -o StrictHostKeyChecking=no -r /opt/keybuzz-installer-v2/credentials root@10.0.0.100:/opt/keybuzz-installer-v2/ 2>&1 || echo "Échec transfert"

# Exécuter le déploiement sur le master
echo ""
echo "2. Déploiement Module 10 sur master..."
ssh root@10.0.0.100 << 'EOF'
export KUBECONFIG=/root/.kube/config
cd /opt/keybuzz-installer-v2/scripts/10_platform
./deploy_module10_kubernetes.sh 2>&1
EOF

echo ""
echo "3. Déploiement des applications Platform..."
ssh root@10.0.0.100 << 'EOF'
export KUBECONFIG=/root/.kube/config
cd /opt/keybuzz-installer-v2/scripts/10_platform
./deploy_platform_apps.sh ghcr.io/keybuzzio/platform-api:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 2>&1
EOF

echo ""
echo "4. Mise à jour des images..."
ssh root@10.0.0.100 << 'EOF'
export KUBECONFIG=/root/.kube/config
cd /opt/keybuzz-installer-v2/scripts/10_platform
./update_platform_images.sh ghcr.io/keybuzzio/platform-api:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 2>&1
EOF

echo ""
echo "5. Vérification des pods..."
sleep 30
ssh root@10.0.0.100 "export KUBECONFIG=/root/.kube/config && kubectl get pods -n keybuzz -o wide"

echo ""
echo "=== DEPLOIEMENT TERMINE ==="

