#!/usr/bin/env bash
#
# fix_cilium_clean_install.sh - Installation propre de Cilium avec tunnel=disabled
#
# Ce script nettoie les interfaces réseau et réinstalle Cilium correctement.

set -euo pipefail

echo "=== Nettoyage et Réinstallation Cilium ==="

# Désinstaller Cilium
echo "1. Désinstallation de Cilium..."
cilium uninstall 2>&1 | tail -5 || true

# Nettoyer les interfaces sur tous les nœuds
echo "2. Nettoyage des interfaces réseau..."
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "ip link delete cilium_vxlan 2>/dev/null || true; ip link delete flannel.1 2>/dev/null || true; ip link delete cni0 2>/dev/null || true; echo OK $ip" || true
done

# Attendre
sleep 10

# Réinstaller Cilium avec la bonne configuration
echo "3. Réinstallation de Cilium (tunnel=disabled)..."
cilium install --version 1.15.3 \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=true \
  --set enableBPFMasquerade=true \
  --set kubeProxyReplacement=strict \
  --set ipv4NativeRoutingCIDR=10.42.0.0/16 2>&1 | tail -10

echo "4. Attente du déploiement (90 secondes)..."
sleep 90

# Vérifier
echo "5. Vérification..."
kubectl get pods -n kube-system -l k8s-app=cilium

echo ""
echo "=== Terminé ==="

