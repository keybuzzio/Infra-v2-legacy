#!/usr/bin/env bash
#
# 00_init_install01.sh - Initialisation de install-01
#
# Usage:
#   ./00_init_install01.sh
#
# Ce script prépare install-01 pour l'installation de l'infrastructure KeyBuzz
# Il doit être exécuté UNE SEULE FOIS sur install-01

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
echo "[1/6] Mise à jour du système..."
apt-get update -y
apt-get upgrade -y

# Installation des paquets de base
echo "[2/6] Installation des paquets de base..."
apt-get install -y \
  curl wget jq unzip gnupg htop net-tools git ca-certificates \
  software-properties-common ufw fail2ban auditd

# Création du répertoire de travail
echo "[3/6] Création du répertoire de travail..."
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

# Cloner le dépôt GitHub
echo "[4/6] Clonage du dépôt GitHub..."
if [[ -d ".git" ]]; then
  echo "⚠️  Le dépôt Git existe déjà. Mise à jour..."
  git pull origin main || git pull origin master
else
  echo "Clonage du dépôt ${GIT_REPO}..."
  git clone "${GIT_REPO}" .
fi

# Rendre les scripts exécutables
echo "[5/6] Configuration des permissions des scripts..."
find scripts -type f -name "*.sh" -exec chmod +x {} \;

# Vérification de la structure
echo "[6/6] Vérification de la structure..."
if [[ ! -f "servers.tsv" ]]; then
  echo "⚠️  Fichier servers.tsv introuvable"
fi

if [[ ! -d "scripts/02_base_os_and_security" ]]; then
  echo "⚠️  Scripts Module 2 introuvables"
fi

echo ""
echo "=============================================================="
echo "✅ Initialisation terminée !"
echo "=============================================================="
echo ""
echo "Répertoire de travail : ${INSTALL_DIR}"
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


