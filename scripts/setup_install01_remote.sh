#!/usr/bin/env bash
#
# setup_install01_remote.sh - Script à exécuter directement sur install-01
#
# Ce script doit être copié sur install-01 et exécuté là-bas
# Il initialise complètement install-01 pour KeyBuzz

set -euo pipefail

INSTALL_DIR="/opt/keybuzz-installer"
GIT_REPO="https://github.com/keybuzzio/Infra.git"

echo "=============================================================="
echo " [KeyBuzz] Initialisation de install-01"
echo "=============================================================="
echo ""

# Vérifier qu'on est root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté en root."
  exit 1
fi

# Vérifier qu'on est bien sur install-01
HOSTNAME=$(hostname)
echo "Hostname : ${HOSTNAME}"
echo ""

# Mise à jour du système
echo "[1/7] Mise à jour du système..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Installation des paquets de base
echo "[2/7] Installation des paquets de base..."
apt-get install -y \
  curl wget jq unzip gnupg htop net-tools git ca-certificates \
  software-properties-common ufw fail2ban auditd

# Création du répertoire de travail
echo "[3/7] Création du répertoire de travail..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Cloner le dépôt GitHub
echo "[4/7] Clonage du dépôt GitHub..."
if [[ -d ".git" ]]; then
  echo "⚠️  Le dépôt Git existe déjà. Mise à jour..."
  git pull origin main || git pull origin master || echo "⚠️  Impossible de mettre à jour"
else
  echo "Clonage du dépôt ${GIT_REPO}..."
  git clone "${GIT_REPO}" .
fi

# Rendre les scripts exécutables
echo "[5/7] Configuration des permissions des scripts..."
find scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Vérification de la structure
echo "[6/7] Vérification de la structure..."
if [[ ! -f "servers.tsv" ]]; then
  echo "⚠️  Fichier servers.tsv introuvable"
else
  SERVER_COUNT=$(tail -n +2 servers.tsv 2>/dev/null | wc -l || echo "0")
  echo "✅ Fichier servers.tsv trouvé (${SERVER_COUNT} serveurs)"
fi

if [[ ! -d "scripts/02_base_os_and_security" ]]; then
  echo "⚠️  Scripts Module 2 introuvables"
else
  echo "✅ Scripts Module 2 trouvés"
fi

# Afficher les informations
echo "[7/7] Informations du système..."
echo ""
echo "=============================================================="
echo "✅ Initialisation terminée !"
echo "=============================================================="
echo ""
echo "Répertoire de travail : ${INSTALL_DIR}"
echo "Hostname : $(hostname)"
echo "IP privée : $(ip addr show | grep 'inet 10.0.0' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo 'N/A')"
echo "OS : $(lsb_release -d 2>/dev/null | cut -f2 || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "Docker : $(docker --version 2>/dev/null || echo 'Non installé')"
echo "Git : $(git --version 2>/dev/null || echo 'Non installé')"
echo ""
echo "Prochaines étapes :"
echo "1. Éditer servers.tsv si nécessaire"
echo "2. Éditer scripts/02_base_os_and_security/base_os.sh"
echo "   - Remplacer ADMIN_IP=\"XXX.YYY.ZZZ.TTT\" par votre IP"
echo "3. Lancer l'installation du Module 2 :"
echo "   cd ${INSTALL_DIR}/scripts/02_base_os_and_security"
echo "   ./apply_base_os_to_all.sh ../../servers.tsv"
echo ""
echo "=============================================================="


