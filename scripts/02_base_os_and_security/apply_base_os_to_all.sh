#!/usr/bin/env bash
#
# apply_base_os_to_all.sh - Appliquer le Module 2 (Base OS & Sécurité)
#                           à tous les serveurs listés dans servers.tsv
#
# Usage:
#   ./apply_base_os_to_all.sh /chemin/vers/servers.tsv [--parallel N]
#
# Options:
#   --parallel N    : Nombre de serveurs à traiter en parallèle (défaut: 10)
#   --sequential    : Traitement séquentiel (un par un, mode original)
#
# Pré-requis :
#  - être exécuté depuis install-01
#  - accès SSH root sans mot de passe vers tous les serveurs
#  - base_os.sh présent dans le même répertoire que ce script

set -uo pipefail

TSV_FILE="${1:-./servers.tsv}"
PARALLEL_JOBS=10
SEQUENTIAL=false

# Parser les arguments
if [[ $# -gt 0 ]]; then
  shift
fi
while [[ $# -gt 0 ]]; do
  case $1 in
    --parallel)
      PARALLEL_JOBS="$2"
      shift 2
      ;;
    --sequential)
      SEQUENTIAL=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

BASE_OS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_OS_SCRIPT="${BASE_OS_SCRIPT_DIR}/base_os.sh"

# Détecter la clé SSH à utiliser
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

if [[ ! -f "${TSV_FILE}" ]]; then
  echo "❌ Fichier TSV introuvable: ${TSV_FILE}"
  exit 1
fi

if [[ ! -f "${BASE_OS_SCRIPT}" ]]; then
  echo "❌ base_os.sh introuvable dans ${BASE_OS_SCRIPT_DIR}"
  exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Module 2 - Application Base OS & Sécurité"
echo " Fichier d'inventaire : ${TSV_FILE}"
echo " Script base_os       : ${BASE_OS_SCRIPT}"
if [[ "${SEQUENTIAL}" == "true" ]]; then
  echo " Mode                : Séquentiel (1 serveur à la fois)"
else
  echo " Mode                : Parallèle (${PARALLEL_JOBS} serveurs simultanés)"
fi
echo "=============================================================="

# Fonction pour traiter un serveur
process_server() {
  local HOSTNAME="$1"
  local TARGET_IP="$2"
  local TARGET_USER="$3"
  local ROLE="$4"
  local SUBROLE="$5"
  local POOL="$6"
  local LOG_FILE="/tmp/module2_${HOSTNAME}.log"
  
  {
    echo "--------------------------------------------------------------"
    echo "▶ Traitement serveur : ${HOSTNAME} (${TARGET_IP})"
    echo "   Rôle: ${ROLE} / ${SUBROLE} | Pool: ${POOL}"
    echo "--------------------------------------------------------------"
    
    # Copier base_os.sh sur le serveur
    if scp ${SSH_KEY_OPTS} -q -o StrictHostKeyChecking=accept-new \
        "${BASE_OS_SCRIPT}" "${TARGET_USER}@${TARGET_IP}:/root/base_os.sh" 2>/dev/null; then
      
      # Rendre exécutable & lancer avec le bon rôle
      if ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
          "${TARGET_USER}@${TARGET_IP}" \
          "chmod +x /root/base_os.sh && /root/base_os.sh '${ROLE}' '${SUBROLE}'" 2>&1; then
        echo "✅ Serveur ${HOSTNAME} (${TARGET_IP}) traité avec succès."
        return 0
      else
        echo "❌ Erreur lors de l'exécution sur ${HOSTNAME} (${TARGET_IP})"
        return 1
      fi
    else
      echo "❌ Erreur lors de la copie vers ${HOSTNAME} (${TARGET_IP})"
      return 1
    fi
  } | tee "${LOG_FILE}"
}

# On suppose le header :
# ENV  IP_PUBLIQUE  HOSTNAME  IP_PRIVEE  FQDN  USER_SSH  POOL  ROLE  SUBROLE  DOCKER_STACK  CORE  NOTES
# séparé par TAB

# Collecter tous les serveurs à traiter
declare -a SERVERS=()
declare -a SERVER_IPS=()
declare -a SERVER_USERS=()
declare -a SERVER_ROLES=()
declare -a SERVER_SUBROLES=()
declare -a SERVER_POOLS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
  # Skip header
  if [[ "${ENV}" == "ENV" ]]; then
    continue
  fi

  # On ne traite que env=prod (par défaut)
  if [[ "${ENV}" != "prod" ]]; then
    continue
  fi

  TARGET_USER="${USER_SSH:-root}"
  TARGET_IP="${IP_PRIVEE}"

  if [[ -z "${TARGET_IP}" ]]; then
    echo "⚠️  IP privée vide pour ${HOSTNAME}, on saute."
    continue
  fi

  SERVERS+=("${HOSTNAME}")
  SERVER_IPS+=("${TARGET_IP}")
  SERVER_USERS+=("${TARGET_USER}")
  SERVER_ROLES+=("${ROLE}")
  SERVER_SUBROLES+=("${SUBROLE}")
  SERVER_POOLS+=("${POOL}")
done
exec 3<&-

TOTAL_SERVERS=${#SERVERS[@]}
echo ""
echo "📊 Total de serveurs à traiter : ${TOTAL_SERVERS}"
echo ""

# Compteurs
SUCCESS_COUNT=0
ERROR_COUNT=0

# Traitement séquentiel ou parallèle
if [[ "${SEQUENTIAL}" == "true" ]]; then
  # Mode séquentiel (original)
  for i in "${!SERVERS[@]}"; do
    if process_server "${SERVERS[$i]}" "${SERVER_IPS[$i]}" "${SERVER_USERS[$i]}" \
                      "${SERVER_ROLES[$i]}" "${SERVER_SUBROLES[$i]}" "${SERVER_POOLS[$i]}"; then
      ((SUCCESS_COUNT++))
    else
      ((ERROR_COUNT++))
    fi
    echo
  done
else
  # Mode parallèle avec contrôle du nombre de jobs
  declare -a PIDS=()
  CURRENT_INDEX=0
  
  while [[ ${CURRENT_INDEX} -lt ${TOTAL_SERVERS} ]]; do
    # Lancer jusqu'à PARALLEL_JOBS processus en parallèle
    while [[ ${#PIDS[@]} -lt ${PARALLEL_JOBS} ]] && [[ ${CURRENT_INDEX} -lt ${TOTAL_SERVERS} ]]; do
      (
        process_server "${SERVERS[$CURRENT_INDEX]}" "${SERVER_IPS[$CURRENT_INDEX]}" \
                       "${SERVER_USERS[$CURRENT_INDEX]}" "${SERVER_ROLES[$CURRENT_INDEX]}" \
                       "${SERVER_SUBROLES[$CURRENT_INDEX]}" "${SERVER_POOLS[$CURRENT_INDEX]}"
      ) &
      PIDS+=($!)
      ((CURRENT_INDEX++))
    done
    
    # Attendre qu'au moins un processus se termine
    if [[ ${#PIDS[@]} -gt 0 ]]; then
      wait -n
      # Retirer les PIDs terminés
      NEW_PIDS=()
      for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          NEW_PIDS+=("$pid")
        else
          # Vérifier le code de retour
          wait "$pid"
          if [[ $? -eq 0 ]]; then
            ((SUCCESS_COUNT++))
          else
            ((ERROR_COUNT++))
          fi
        fi
      done
      PIDS=("${NEW_PIDS[@]}")
    fi
  done
  
  # Attendre tous les processus restants
  for pid in "${PIDS[@]}"; do
    wait "$pid"
    if [[ $? -eq 0 ]]; then
      ((SUCCESS_COUNT++))
    else
      ((ERROR_COUNT++))
    fi
  done
fi

echo ""
echo "=============================================================="
echo "📊 Résumé de l'installation"
echo "=============================================================="
echo "✅ Serveurs traités avec succès : ${SUCCESS_COUNT}"
if [[ ${ERROR_COUNT} -gt 0 ]]; then
  echo "❌ Serveurs en erreur          : ${ERROR_COUNT}"
fi
echo "📦 Total                        : ${TOTAL_SERVERS}"
echo "=============================================================="

if [[ ${ERROR_COUNT} -eq 0 ]]; then
  echo "🎉 [KeyBuzz] Module 2 appliqué sur tous les serveurs prod."
else
  echo "⚠️  [KeyBuzz] Module 2 appliqué avec ${ERROR_COUNT} erreur(s)."
  exit 1
fi
echo "=============================================================="

