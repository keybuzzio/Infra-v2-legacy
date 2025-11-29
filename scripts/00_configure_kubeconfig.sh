#!/usr/bin/env bash
# Script pour configurer le kubeconfig sur install-01

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Configuration kubeconfig sur install-01"
echo "=============================================================="
echo ""

# IP du premier master (hardcodé pour l'instant)
MASTER01_IP="10.0.0.100"

echo "IP de k3s-master-01 : ${MASTER01_IP}"
echo ""

# Créer le répertoire .kube
mkdir -p "${HOME}/.kube"

# Copier le kubeconfig depuis master-01
echo "Copie du kubeconfig depuis k3s-master-01..."
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"${MASTER01_IP}" "test -f /etc/rancher/k3s/k3s.yaml" 2>/dev/null; then
  ssh -o StrictHostKeyChecking=no root@"${MASTER01_IP}" "cat /etc/rancher/k3s/k3s.yaml" | \
    sed "s/127.0.0.1/${MASTER01_IP}/g" > "${HOME}/.kube/config"
  chmod 600 "${HOME}/.kube/config"
  echo "✅ kubeconfig configuré"
  echo ""
  
  # Tester l'accès
  echo "Test de l'accès au cluster..."
  if kubectl get nodes &>/dev/null; then
    echo "✅ Accès au cluster K3s validé"
    echo ""
    echo "Nœuds du cluster :"
    kubectl get nodes
    echo ""
    echo "Pods système :"
    kubectl get pods -n kube-system | head -10
  else
    echo "❌ L'accès au cluster échoue"
    echo "   Vérifiez la connectivité réseau vers ${MASTER01_IP}:6443"
  fi
else
  echo "❌ k3s.yaml introuvable sur k3s-master-01"
  echo "   Le cluster K3s n'est peut-être pas encore installé"
fi

echo ""
echo "=============================================================="

