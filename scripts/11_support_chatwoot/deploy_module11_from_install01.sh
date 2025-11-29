#!/usr/bin/env bash
set -euo pipefail

echo "=== DEPLOIEMENT MODULE 11 V2 depuis install-01 ==="
echo ""

# Transférer scripts vers master
echo "1. Transfert scripts Module 11 vers master..."
scp -o StrictHostKeyChecking=no -r /opt/keybuzz-installer-v2/scripts/11_support_chatwoot root@10.0.0.100:/opt/keybuzz-installer-v2/scripts/ 2>&1 || echo "Échec transfert scripts"

# Exécuter le déploiement sur le master
echo ""
echo "2. Déploiement Module 11 sur master..."
ssh root@10.0.0.100 << 'EOF'
export KUBECONFIG=/root/.kube/config
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
chmod +x *.sh
./11_ct_apply_all.sh 2>&1
EOF

echo ""
echo "3. Vérification des pods..."
sleep 30
ssh root@10.0.0.100 "export KUBECONFIG=/root/.kube/config && kubectl get pods -n chatwoot -o wide"

echo ""
echo "4. Vérification des ressources..."
ssh root@10.0.0.100 "export KUBECONFIG=/root/.kube/config && kubectl get deployments,svc,ingress -n chatwoot"

echo ""
echo "=== DEPLOIEMENT TERMINE ==="

