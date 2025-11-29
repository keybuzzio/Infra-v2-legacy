#!/usr/bin/env bash
#
# 00_install_tools_install01.sh - Installation des outils nécessaires sur install-01
#
# Ce script installe tous les outils nécessaires pour gérer l'infrastructure KeyBuzz
# depuis install-01 : kubectl, helm, jq, etc.
#
# Usage:
#   ./00_install_tools_install01.sh
#
# Prérequis:
#   - Exécuter depuis install-01 en root
#   - Accès Internet

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Installation des Outils sur install-01"
echo "=============================================================="
echo ""

# Vérifier qu'on est root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté en root."
  exit 1
fi

# Vérifier qu'on est bien sur install-01
HOSTNAME=$(hostname)
if [[ "${HOSTNAME}" != "install-01" ]] && [[ "${HOSTNAME}" != "install-01.keybuzz.io" ]]; then
  echo "⚠️  Attention : Ce script est prévu pour install-01"
  echo "   Hostname actuel : ${HOSTNAME}"
  read -p "Continuer quand même ? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Mise à jour du système
echo "[1/8] Mise à jour du système..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Installation des paquets de base
echo "[2/8] Installation des paquets de base..."
apt-get install -y \
  curl wget jq unzip gnupg htop net-tools git ca-certificates \
  software-properties-common ufw fail2ban auditd \
  apt-transport-https lsb-release

# Installation de kubectl
echo "[3/8] Installation de kubectl..."
if ! command -v kubectl &> /dev/null; then
  # Télécharger kubectl
  KUBECTL_VERSION="v1.30.0"  # Version compatible avec K3s
  curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
  chmod +x kubectl
  mv kubectl /usr/local/bin/
  echo "✅ kubectl ${KUBECTL_VERSION} installé"
else
  echo "ℹ️  kubectl déjà installé : $(kubectl version --client --short 2>/dev/null || echo 'version inconnue')"
fi

# Installation de Helm
echo "[4/8] Installation de Helm..."
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
  echo "✅ Helm installé : $(helm version --short 2>/dev/null || echo 'version inconnue')"
else
  echo "ℹ️  Helm déjà installé : $(helm version --short 2>/dev/null || echo 'version inconnue')"
fi

# Vérification de jq
echo "[5/8] Vérification de jq..."
if ! command -v jq &> /dev/null; then
  echo "❌ jq n'est pas installé (devrait être installé avec les paquets de base)"
  apt-get install -y jq
else
  echo "✅ jq installé : $(jq --version)"
fi

# Configuration de l'accès au cluster K3s
echo "[6/8] Configuration de l'accès au cluster K3s..."

# Chercher le fichier servers.tsv
SERVERS_TSV=""
if [[ -f "/opt/keybuzz-installer/inventory/servers.tsv" ]]; then
  SERVERS_TSV="/opt/keybuzz-installer/inventory/servers.tsv"
elif [[ -f "/opt/keybuzz-installer/servers.tsv" ]]; then
  SERVERS_TSV="/opt/keybuzz-installer/servers.tsv"
elif [[ -f "/root/install-01/servers.tsv" ]]; then
  SERVERS_TSV="/root/install-01/servers.tsv"
elif [[ -f "./servers.tsv" ]]; then
  SERVERS_TSV="./servers.tsv"
fi

if [[ -n "${SERVERS_TSV}" ]] && [[ -f "${SERVERS_TSV}" ]]; then
  echo "   Fichier servers.tsv trouvé : ${SERVERS_TSV}"
  
  # Récupérer l'IP du premier master
  MASTER01_IP=$(awk -F'\t' '$2=="k3s-master-01" {print $3}' "${SERVERS_TSV}" | head -1)
  
  if [[ -n "${MASTER01_IP}" ]]; then
    echo "   IP de k3s-master-01 : ${MASTER01_IP}"
    
    # Créer le répertoire .kube
    mkdir -p "${HOME}/.kube"
    
    # Copier le kubeconfig depuis master-01
    echo "   Copie du kubeconfig depuis k3s-master-01..."
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 root@"${MASTER01_IP}" "test -f /etc/rancher/k3s/k3s.yaml" 2>/dev/null; then
      ssh -o StrictHostKeyChecking=no root@"${MASTER01_IP}" "cat /etc/rancher/k3s/k3s.yaml" | \
        sed "s/127.0.0.1/${MASTER01_IP}/g" > "${HOME}/.kube/config"
      chmod 600 "${HOME}/.kube/config"
      echo "✅ kubeconfig configuré"
      
      # Tester l'accès
      if kubectl get nodes &>/dev/null; then
        echo "✅ Accès au cluster K3s validé"
        echo ""
        echo "   Nœuds du cluster :"
        kubectl get nodes
      else
        echo "⚠️  kubeconfig copié mais l'accès au cluster échoue"
        echo "   Vérifiez la connectivité réseau vers ${MASTER01_IP}:6443"
      fi
    else
      echo "⚠️  k3s.yaml introuvable sur k3s-master-01"
      echo "   Le cluster K3s n'est peut-être pas encore installé"
    fi
  else
    echo "⚠️  Impossible de trouver l'IP de k3s-master-01 dans servers.tsv"
  fi
else
  echo "⚠️  Fichier servers.tsv introuvable"
  echo "   L'accès au cluster K3s ne sera pas configuré automatiquement"
fi

# Installation d'outils supplémentaires
echo "[7/8] Installation d'outils supplémentaires..."

# netcat (nc) pour les tests de connectivité
if ! command -v nc &> /dev/null; then
  apt-get install -y netcat-openbsd
  echo "✅ netcat installé"
else
  echo "ℹ️  netcat déjà installé"
fi

# traceroute pour le diagnostic réseau
if ! command -v traceroute &> /dev/null; then
  apt-get install -y traceroute
  echo "✅ traceroute installé"
else
  echo "ℹ️  traceroute déjà installé"
fi

# Vérification finale
echo "[8/8] Vérification finale..."
echo ""

TOOLS_OK=0
TOOLS_FAIL=0

check_tool() {
  local tool=$1
  if command -v "${tool}" &> /dev/null; then
    echo "✅ ${tool} : $(command -v ${tool})"
    TOOLS_OK=$((TOOLS_OK + 1))
  else
    echo "❌ ${tool} : non trouvé"
    TOOLS_FAIL=$((TOOLS_FAIL + 1))
  fi
}

check_tool "kubectl"
check_tool "helm"
check_tool "jq"
check_tool "curl"
check_tool "wget"
check_tool "git"
check_tool "nc"
check_tool "traceroute"

echo ""
echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "✅ Outils installés : ${TOOLS_OK}"
echo "❌ Outils manquants : ${TOOLS_FAIL}"
echo ""

if [[ ${TOOLS_FAIL} -eq 0 ]]; then
  echo "✅ Tous les outils sont installés !"
  echo ""
  echo "Vous pouvez maintenant utiliser :"
  echo "  - kubectl get nodes"
  echo "  - helm list -A"
  echo "  - kubectl get pods -A"
  echo ""
  
  # Afficher l'état du cluster si accessible
  if kubectl get nodes &>/dev/null 2>&1; then
    echo "📊 État du cluster K3s :"
    kubectl get nodes
    echo ""
    echo "📊 Pods système :"
    kubectl get pods -n kube-system | head -10
  fi
else
  echo "⚠️  Certains outils sont manquants. Vérifiez les erreurs ci-dessus."
fi

echo ""
echo "=============================================================="

