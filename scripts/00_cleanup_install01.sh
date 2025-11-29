#!/usr/bin/env bash
#
# 00_cleanup_install01.sh - Nettoyage et réinitialisation propre de install-01
#
# Usage:
#   ./00_cleanup_install01.sh [--force]
#
# Ce script nettoie les dossiers mélangés et réinitialise proprement install-01

set -euo pipefail

INSTALL_DIR="/opt/keybuzz-installer"
BACKUP_DIR="/opt/keybuzz-installer.backup."
BACKUP_TEMP="/tmp/keybuzz-installer-backup-$(date +%Y%m%d_%H%M%S)"
FORCE=false

# Parse arguments
if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

echo "=============================================================="
echo " [KeyBuzz] Nettoyage et réinitialisation de install-01"
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
  if [[ "${FORCE}" != "true" ]]; then
    read -p "Continuer quand même ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
fi

echo "[1/6] Sauvegarde des éléments importants..."
mkdir -p "${BACKUP_TEMP}"

# Sauvegarder credentials
if [[ -d "${INSTALL_DIR}/credentials" ]]; then
    echo "  → Sauvegarde credentials..."
    cp -r "${INSTALL_DIR}/credentials" "${BACKUP_TEMP}/" 2>/dev/null || true
fi

# Sauvegarder servers.tsv
if [[ -f "${INSTALL_DIR}/servers.tsv" ]]; then
    echo "  → Sauvegarde servers.tsv..."
    cp "${INSTALL_DIR}/servers.tsv" "${BACKUP_TEMP}/" 2>/dev/null || true
fi

# Sauvegarder .env
if [[ -f "${INSTALL_DIR}/.env" ]]; then
    echo "  → Sauvegarde .env..."
    cp "${INSTALL_DIR}/.env" "${BACKUP_TEMP}/" 2>/dev/null || true
fi

# Sauvegarder logs importants
if [[ -d "${INSTALL_DIR}/logs" ]]; then
    echo "  → Sauvegarde logs..."
    mkdir -p "${BACKUP_TEMP}/logs"
    find "${INSTALL_DIR}/logs" -type f -name "*.log" -mtime -7 -exec cp {} "${BACKUP_TEMP}/logs/" \; 2>/dev/null || true
fi

echo "  ✓ Sauvegarde terminée : ${BACKUP_TEMP}"
echo ""

echo "[2/6] Vérification de l'état actuel..."
echo "  → Taille de ${INSTALL_DIR}: $(du -sh ${INSTALL_DIR} 2>/dev/null | cut -f1 || echo 'N/A')"
if [[ -d "${BACKUP_DIR}" ]]; then
    echo "  → Taille de ${BACKUP_DIR}: $(du -sh ${BACKUP_DIR} 2>/dev/null | cut -f1 || echo 'N/A')"
fi
echo ""

if [[ "${FORCE}" != "true" ]]; then
    echo "⚠️  ATTENTION : Cette opération va :"
    echo "   1. Supprimer ${BACKUP_DIR}"
    echo "   2. Nettoyer ${INSTALL_DIR} (sauf credentials, servers.tsv, .env)"
    echo "   3. Réinitialiser depuis Git"
    echo ""
    read -p "Continuer ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Opération annulée"
        exit 1
    fi
fi

echo "[3/6] Suppression de l'ancien backup..."
if [[ -d "${BACKUP_DIR}" ]]; then
    rm -rf "${BACKUP_DIR}"
    echo "  ✓ ${BACKUP_DIR} supprimé"
else
    echo "  ✓ Aucun backup à supprimer"
fi
echo ""

echo "[4/6] Nettoyage de ${INSTALL_DIR}..."
cd "${INSTALL_DIR}" || exit 1

# Supprimer tout sauf les éléments importants
if [[ -d ".git" ]]; then
    echo "  → Nettoyage via Git..."
    git clean -fd
    git reset --hard HEAD
else
    echo "  → Suppression des dossiers non essentiels..."
    # Garder : credentials, servers.tsv, .env, logs
    # Supprimer : scripts, docs, configs, etc.
    for dir in scripts docs configs backups ssl inventory kb_build wgkeys; do
        if [[ -d "${dir}" ]]; then
            rm -rf "${dir}"
            echo "    ✓ ${dir} supprimé"
        fi
    done
fi
echo ""

echo "[5/6] Réinitialisation depuis Git..."
if [[ ! -d ".git" ]]; then
    echo "  → Clonage du dépôt..."
    cd /opt
    rm -rf "${INSTALL_DIR}"
    git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
    cd "${INSTALL_DIR}"
else
    echo "  → Mise à jour depuis Git..."
    git fetch origin
    git reset --hard origin/main || git reset --hard origin/master
    git clean -fd
fi
echo ""

echo "[6/6] Restauration des éléments sauvegardés..."
# Restaurer credentials
if [[ -d "${BACKUP_TEMP}/credentials" ]]; then
    echo "  → Restauration credentials..."
    cp -r "${BACKUP_TEMP}/credentials"/* "${INSTALL_DIR}/credentials/" 2>/dev/null || true
fi

# Restaurer servers.tsv
if [[ -f "${BACKUP_TEMP}/servers.tsv" ]]; then
    echo "  → Restauration servers.tsv..."
    cp "${BACKUP_TEMP}/servers.tsv" "${INSTALL_DIR}/" 2>/dev/null || true
    # Aussi dans inventory si le dossier existe
    if [[ -d "${INSTALL_DIR}/inventory" ]]; then
        cp "${BACKUP_TEMP}/servers.tsv" "${INSTALL_DIR}/inventory/" 2>/dev/null || true
    fi
fi

# Restaurer .env
if [[ -f "${BACKUP_TEMP}/.env" ]]; then
    echo "  → Restauration .env..."
    cp "${BACKUP_TEMP}/.env" "${INSTALL_DIR}/" 2>/dev/null || true
fi

# Restaurer logs
if [[ -d "${BACKUP_TEMP}/logs" ]] && [[ -d "${INSTALL_DIR}/logs" ]]; then
    echo "  → Restauration logs récents..."
    cp "${BACKUP_TEMP}/logs"/* "${INSTALL_DIR}/logs/" 2>/dev/null || true
fi

echo ""

# Rendre les scripts exécutables
echo "[Bonus] Configuration des permissions..."
find scripts -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
echo "  ✓ Permissions configurées"
echo ""

echo "=============================================================="
echo "✅ Nettoyage et réinitialisation terminés !"
echo "=============================================================="
echo ""
echo "Répertoire de travail : ${INSTALL_DIR}"
echo "Sauvegarde temporaire : ${BACKUP_TEMP}"
echo ""
echo "Vérifications :"
echo "  - servers.tsv : $([ -f ${INSTALL_DIR}/servers.tsv ] && echo '✓ Présent' || echo '✗ Manquant')"
echo "  - Scripts Module 2 : $([ -d ${INSTALL_DIR}/scripts/02_base_os_and_security ] && echo '✓ Présents' || echo '✗ Manquants')"
echo "  - Credentials : $([ -d ${INSTALL_DIR}/credentials ] && echo '✓ Présents' || echo '✗ Manquants')"
echo ""
echo "Prochaines étapes :"
echo "1. Vérifier servers.tsv : cat ${INSTALL_DIR}/servers.tsv | head -5"
echo "2. Vérifier ADMIN_IP dans base_os.sh :"
echo "   grep ADMIN_IP ${INSTALL_DIR}/scripts/02_base_os_and_security/base_os.sh"
echo "3. Lancer le Module 2 :"
echo "   cd ${INSTALL_DIR}/scripts/02_base_os_and_security"
echo "   ./apply_base_os_to_all.sh ../../servers.tsv"
echo ""
echo "=============================================================="

