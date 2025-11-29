#!/usr/bin/env bash
#
# verify_setup.sh - Vérifie que l'environnement est prêt pour l'installation
#
# Usage:
#   ./verify_setup.sh
#
# Ce script vérifie tous les prérequis avant de commencer l'installation

set -euo pipefail

INSTALL_DIR="/opt/keybuzz-installer"
ERRORS=0
WARNINGS=0

echo "=============================================================="
echo " [KeyBuzz] Vérification de l'environnement"
echo "=============================================================="
echo ""

# Vérifier qu'on est root
if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Ce script doit être exécuté en root."
  exit 1
fi

# Vérifier le répertoire de travail
echo "[1/8] Vérification du répertoire de travail..."
if [[ -d "${INSTALL_DIR}" ]]; then
  echo "✅ Répertoire ${INSTALL_DIR} existe"
  cd "${INSTALL_DIR}"
else
  echo "❌ Répertoire ${INSTALL_DIR} n'existe pas"
  ((ERRORS++))
fi

# Vérifier Git
echo "[2/8] Vérification de Git..."
if command -v git >/dev/null 2>&1; then
  echo "✅ Git installé : $(git --version)"
else
  echo "❌ Git non installé"
  ((ERRORS++))
fi

# Vérifier le dépôt Git
echo "[3/8] Vérification du dépôt Git..."
if [[ -d "${INSTALL_DIR}/.git" ]]; then
  echo "✅ Dépôt Git initialisé"
  cd "${INSTALL_DIR}"
  if git remote -v | grep -q "keybuzzio/Infra"; then
    echo "✅ Remote GitHub configuré"
  else
    echo "⚠️  Remote GitHub non configuré"
    ((WARNINGS++))
  fi
else
  echo "⚠️  Dépôt Git non initialisé (normal si première installation)"
  ((WARNINGS++))
fi

# Vérifier servers.tsv
echo "[4/8] Vérification de servers.tsv..."
if [[ -f "${INSTALL_DIR}/servers.tsv" ]]; then
  SERVER_COUNT=$(tail -n +2 "${INSTALL_DIR}/servers.tsv" | wc -l)
  echo "✅ Fichier servers.tsv trouvé (${SERVER_COUNT} serveurs)"
else
  echo "❌ Fichier servers.tsv introuvable"
  ((ERRORS++))
fi

# Vérifier les scripts Module 2
echo "[5/8] Vérification des scripts Module 2..."
if [[ -f "${INSTALL_DIR}/scripts/02_base_os_and_security/base_os.sh" ]]; then
  echo "✅ Script base_os.sh trouvé"
  if grep -q "XXX.YYY.ZZZ.TTT" "${INSTALL_DIR}/scripts/02_base_os_and_security/base_os.sh"; then
    echo "⚠️  ADMIN_IP n'a pas été configuré dans base_os.sh"
    ((WARNINGS++))
  else
    echo "✅ ADMIN_IP configuré"
  fi
else
  echo "❌ Script base_os.sh introuvable"
  ((ERRORS++))
fi

if [[ -f "${INSTALL_DIR}/scripts/02_base_os_and_security/apply_base_os_to_all.sh" ]]; then
  echo "✅ Script apply_base_os_to_all.sh trouvé"
else
  echo "❌ Script apply_base_os_to_all.sh introuvable"
  ((ERRORS++))
fi

# Vérifier les permissions des scripts
echo "[6/8] Vérification des permissions..."
SCRIPTS_EXECUTABLES=$(find "${INSTALL_DIR}/scripts" -type f -name "*.sh" -perm +111 2>/dev/null | wc -l)
if [[ ${SCRIPTS_EXECUTABLES} -gt 0 ]]; then
  echo "✅ ${SCRIPTS_EXECUTABLES} scripts exécutables"
else
  echo "⚠️  Aucun script exécutable trouvé"
  echo "   Exécuter : find ${INSTALL_DIR}/scripts -type f -name '*.sh' -exec chmod +x {} \\;"
  ((WARNINGS++))
fi

# Vérifier l'accès SSH
echo "[7/8] Vérification de l'accès SSH..."
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]] || [[ -f "${HOME}/.ssh/id_rsa" ]] || [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
  echo "✅ Clé SSH trouvée"
else
  echo "⚠️  Aucune clé SSH trouvée"
  ((WARNINGS++))
fi

# Test de connexion SSH vers un serveur (optionnel)
echo "[8/8] Test de connexion SSH (optionnel)..."
if [[ -f "${INSTALL_DIR}/servers.tsv" ]]; then
  FIRST_SERVER_IP=$(tail -n +2 "${INSTALL_DIR}/servers.tsv" | head -1 | cut -f4)
  if [[ -n "${FIRST_SERVER_IP}" ]]; then
    if timeout 5 ssh -o ConnectTimeout=3 -o BatchMode=yes root@${FIRST_SERVER_IP} "echo OK" 2>/dev/null; then
      echo "✅ Connexion SSH testée vers ${FIRST_SERVER_IP}"
    else
      echo "⚠️  Impossible de se connecter à ${FIRST_SERVER_IP} (normal si clés non déposées)"
      ((WARNINGS++))
    fi
  fi
fi

echo ""
echo "=============================================================="
echo " Résumé de la vérification"
echo "=============================================================="
echo ""

if [[ ${ERRORS} -eq 0 ]] && [[ ${WARNINGS} -eq 0 ]]; then
  echo "✅ Tous les prérequis sont satisfaits !"
  echo ""
  echo "Vous pouvez maintenant lancer l'installation :"
  echo "  cd ${INSTALL_DIR}/scripts/02_base_os_and_security"
  echo "  ./apply_base_os_to_all.sh ../../servers.tsv"
  exit 0
elif [[ ${ERRORS} -eq 0 ]]; then
  echo "⚠️  ${WARNINGS} avertissement(s) détecté(s)"
  echo ""
  echo "Vous pouvez continuer, mais vérifiez les avertissements ci-dessus."
  exit 0
else
  echo "❌ ${ERRORS} erreur(s) détectée(s)"
  echo "⚠️  ${WARNINGS} avertissement(s) détecté(s)"
  echo ""
  echo "Veuillez corriger les erreurs avant de continuer."
  exit 1
fi


